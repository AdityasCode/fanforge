import Foundation

public final class SMCWriter {
    private let connection: SMCConnection
    private let reader: SMCReader
    private var writeAcceptance: [Int: Bool] = [:]

    public init(connection: SMCConnection) {
        self.connection = connection
        self.reader = SMCReader(connection: connection)
    }

    public func encodeFPE2(_ value: Float) -> (UInt8, UInt8) {
        let scaled = UInt16(max(0, value * 4.0))
        // FPE2 stores the fixed-point payload in two big-endian bytes.
        return (UInt8((scaled >> 8) & 0xFF), UInt8(scaled & 0xFF))
    }

    public func writeFanForceFlag(_ value: UInt8) throws {
        try writeKey(
            SMCKey.FAN_FORCE,
            bytes: [value],
            dataType: .ui8,
            dataSize: 1
        )
    }

    public func setFanMode(fanIndex: Int, manual: Bool) throws {
        guard fanIndex >= 0 else {
            throw SMCError.keyNotFound
        }

        let key = "F\(fanIndex)Md"
        let modeValue: UInt8 = manual ? 1 : 0

        try writeKey(
            key,
            bytes: [modeValue],
            dataType: .ui8,
            dataSize: 1
        )
    }

    public func setFanTargetRPM(fanIndex: Int, rpm: Float) throws {
        guard fanIndex >= 0 else {
            throw SMCError.keyNotFound
        }

        let fanMin = try reader.readFanMin(fanIndex: fanIndex)
        let fanMax = try reader.readFanMax(fanIndex: fanIndex)

        guard rpm >= fanMin, rpm <= fanMax else {
            throw SMCError.firmwareLocked(
                message: "Requested RPM \(Int(rpm)) is outside allowed range \(Int(fanMin))...\(Int(fanMax))."
            )
        }

        try writeFanForceFlag(1)
        try setFanMode(fanIndex: fanIndex, manual: true)

        let encoded = encodeFPE2(rpm)
        let targetKey = "F\(fanIndex)Tg"

        do {
            try writeKey(
                targetKey,
                bytes: [encoded.0, encoded.1],
                dataType: .fpe2,
                dataSize: 2
            )
        } catch {
            writeAcceptance[fanIndex] = false
            throw error
        }

        Thread.sleep(forTimeInterval: 0.2)

        let actualRPM = try reader.readFanRPM(fanIndex: fanIndex)
        let accepted = abs(actualRPM - rpm) <= 50.0
        writeAcceptance[fanIndex] = accepted

        if !accepted {
            throw SMCError.firmwareLocked(
                message: "Firmware ignored fan target write for fan \(fanIndex). Requested \(Int(rpm)) RPM, read back \(Int(actualRPM)) RPM."
            )
        }
    }

    public func resetFanToAuto(fanIndex: Int) throws {
        guard fanIndex >= 0 else {
            throw SMCError.keyNotFound
        }

        try setFanMode(fanIndex: fanIndex, manual: false)
        try writeFanForceFlag(0)
        writeAcceptance[fanIndex] = true
    }

    public func lastWriteAccepted(for fanIndex: Int) -> Bool {
        writeAcceptance[fanIndex] ?? true
    }

    private func writeKey(
        _ key: String,
        bytes: [UInt8],
        dataType: DataType,
        dataSize: UInt32
    ) throws {
        guard key.utf8.count == 4 else {
            throw SMCError.keyNotFound
        }

        var input = SMCParamStruct()
        input.key = key.fourCharCode
        input.data8 = SMCSelector.kSMCWriteKey.rawValue
        input.keyInfo = SMCKeyInfoData(
            dataSize: dataSize,
            dataType: dataType.rawValue.fourCharCode,
            dataAttributes: 0
        )

        // AppleSMC write payloads are fixed-width, so we pack up to 32 bytes and zero-fill the tail.
        input.bytes = paddedBytesTuple(from: bytes)

        let output = try connection.callSMC(&input, allowSMCErrorResult: true)
        guard output.result == 0 else {
            throw SMCError.writeNotPermitted
        }

        // For target writes, verify that fan actual speed follows the request; large deltas imply firmware lockout.
        if key.hasSuffix("Tg"), dataType == .fpe2, bytes.count >= 2, let fanIndex = fanIndexFromFanKey(key) {
            let requestedRaw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            let requestedRPM = Float(requestedRaw >> 2)
            let actualRPM = try reader.readFanRPM(fanIndex: fanIndex)

            if abs(actualRPM - requestedRPM) > 50.0 {
                writeAcceptance[fanIndex] = false
                throw SMCError.firmwareLocked(
                    message: "Firmware accepted write call but did not apply target RPM for fan \(fanIndex)."
                )
            }
        }
    }

    private func paddedBytesTuple(from bytes: [UInt8]) -> SMCBytes {
        var padded = Array(repeating: UInt8(0), count: 32)

        for (index, byte) in bytes.enumerated() where index < padded.count {
            padded[index] = byte
        }

        // The tuple mirrors the exact 32-byte C layout expected by SMCParamStruct.
        return (
            padded[0], padded[1], padded[2], padded[3],
            padded[4], padded[5], padded[6], padded[7],
            padded[8], padded[9], padded[10], padded[11],
            padded[12], padded[13], padded[14], padded[15],
            padded[16], padded[17], padded[18], padded[19],
            padded[20], padded[21], padded[22], padded[23],
            padded[24], padded[25], padded[26], padded[27],
            padded[28], padded[29], padded[30], padded[31]
        )
    }

    private func fanIndexFromFanKey(_ key: String) -> Int? {
        guard key.count == 4, key.first == "F" else {
            return nil
        }

        let digit = key[key.index(key.startIndex, offsetBy: 1)]
        return Int(String(digit))
    }
}


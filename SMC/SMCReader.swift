import Foundation

public final class SMCReader {
    private let connection: SMCConnection

    public init(connection: SMCConnection) {
        self.connection = connection
    }

    public func readKey(_ key: String) throws -> SMCParamStruct {
        // Ask AppleSMC for the metadata first so we know how many bytes to expect when reading the value.
        let keyInfo = try getKeyInfo(key)

        var input = makeInput(for: key, selector: .kSMCReadKey)
        input.keyInfo = keyInfo

        return try connection.callSMC(&input)
    }

    public func getKeyInfo(_ key: String) throws -> SMCKeyInfoData {
        var input = makeInput(for: key, selector: .kSMCGetKeyInfo)
        let output = try connection.callSMC(&input)
        return output.keyInfo
    }

    public func decodeFPE2(_ bytes: SMCBytes) -> Float {
        // FPE2 is a 16-bit unsigned fixed-point number: the top 14 bits hold the integer value, the bottom 2 bits are fractional precision.
        let rawValue = (UInt16(bytes.0) << 8) | UInt16(bytes.1)
        let integerAndFractionBits = rawValue >> 2
        return Float(integerAndFractionBits)
    }

    public func decodeSP78(_ bytes: SMCBytes) -> Float {
        // SP78 is a signed 16-bit fixed-point number: the high byte carries the signed integer, the low byte carries 1/256 steps.
        let signedValue = Int16(bitPattern: (UInt16(bytes.0) << 8) | UInt16(bytes.1))
        return Float(signedValue) / 256.0
    }

    public func readFanCount() throws -> Int {
        let output = try readKey(SMCKey.FAN_NUM)

        guard let dataType = DataType(rawValue: output.keyInfo.dataType.toString) else {
            throw SMCError.unsupportedDataType
        }

        switch dataType {
        case .ui8:
            // The fan count is a single byte when AppleSMC exposes it as ui8.
            return Int(output.bytes.0)
        case .ui16:
            // If the firmware exposes the count as 16 bits, combine the first two bytes in big-endian order.
            return Int((UInt16(output.bytes.0) << 8) | UInt16(output.bytes.1))
        case .ui32:
            // Some firmware builds may widen the count; still read the first four bytes in big-endian order.
            return Int(
                (UInt32(output.bytes.0) << 24) |
                (UInt32(output.bytes.1) << 16) |
                (UInt32(output.bytes.2) << 8) |
                UInt32(output.bytes.3)
            )
        default:
            throw SMCError.unsupportedDataType
        }
    }

    public func readFanRPM(fanIndex: Int) throws -> Float {
        try readFanMetric("Ac", fanIndex: fanIndex)
    }

    public func readFanMin(fanIndex: Int) throws -> Float {
        try readFanMetric("Mn", fanIndex: fanIndex)
    }

    public func readFanMax(fanIndex: Int) throws -> Float {
        try readFanMetric("Mx", fanIndex: fanIndex)
    }

    private func readFanMetric(_ suffix: String, fanIndex: Int) throws -> Float {
        guard fanIndex >= 0 else {
            throw SMCError.keyNotFound
        }

        let key = "F\(fanIndex)\(suffix)"
        let output = try readKey(key)

        guard let dataType = DataType(rawValue: output.keyInfo.dataType.toString) else {
            throw SMCError.unsupportedDataType
        }

        switch dataType {
        case .fpe2:
            return decodeFPE2(output.bytes)
        case .sp78:
            return decodeSP78(output.bytes)
        default:
            throw SMCError.unsupportedDataType
        }
    }

    private func makeInput(for key: String, selector: SMCSelector) -> SMCParamStruct {
        var input = SMCParamStruct()

        // Convert the four-character key name into a big-endian UInt32 so AppleSMC sees the raw ASCII bytes in the expected order.
        input.key = key.fourCharCode

        // The selector is also a byte-sized command; AppleSMC reads the low byte from data8 to decide which action to execute.
        input.data8 = selector.rawValue
        return input
    }
}


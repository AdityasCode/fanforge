import Foundation
import IOKit
import SwiftUI

public final class SMCConnection: ObservableObject {
    private struct MockFan {
        var currentRPM: Float
        var minRPM: Float
        var maxRPM: Float
        var targetRPM: Float
        var isManualMode: Bool
    }

    private struct MockState {
        var fanCount: Int = 2
        var fans: [MockFan] = [
            MockFan(currentRPM: 2400, minRPM: 1200, maxRPM: 6400, targetRPM: 2400, isManualMode: false),
            MockFan(currentRPM: 3200, minRPM: 1200, maxRPM: 6400, targetRPM: 3200, isManualMode: true)
        ]
        var fanForce: UInt8 = 0
    }

    private static let queueKey = DispatchSpecificKey<UInt8>()
    private static let queueToken: UInt8 = 1

    public let smcQueue = DispatchQueue(label: "com.fanforge.smc")
    private var connection: io_connect_t = 0
    private var service: io_service_t = 0
    private var mockState: MockState?

    public init() {
        smcQueue.setSpecific(key: Self.queueKey, value: Self.queueToken)
    }

    private init(mockState: MockState) {
        self.mockState = mockState
        connection = 1
        service = 1
        smcQueue.setSpecific(key: Self.queueKey, value: Self.queueToken)
    }

    public static func mock() -> SMCConnection {
        SMCConnection(mockState: MockState())
    }

    deinit {
        close()
    }

    public var isOpen: Bool {
        syncOnSMCQueue {
            connection != 0
        }
    }

    public func open() throws {
        if mockState != nil {
            connection = 1
            service = 1
            return
        }

        try syncOnSMCQueue {
            if connection != 0 || service != 0 {
                closeLocked()
            }

            guard let matchingDictionary = IOServiceMatching("AppleSMC") else {
                throw SMCError.connectionFailed
            }

            // IOServiceGetMatchingService hands us a retained AppleSMC service object that must be released later.
            service = IOServiceGetMatchingService(kIOMainPortDefault, matchingDictionary)
            guard service != 0 else {
                throw SMCError.connectionFailed
            }

            // IOServiceOpen creates the live user-space connection to AppleSMC.
            let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
            guard result == KERN_SUCCESS, connection != 0 else {
                IOObjectRelease(service)
                service = 0
                throw SMCError.connectionFailed
            }
        }
    }

    public func close() {
        if mockState != nil {
            connection = 0
            service = 0
            return
        }

        syncOnSMCQueue {
            closeLocked()
        }
    }

    public func callSMC(
        _ input: inout SMCParamStruct,
        allowSMCErrorResult: Bool = false
    ) throws -> SMCParamStruct {
        if mockState != nil {
            return try syncOnSMCQueue {
                try mockCallSMC(&input)
            }
        }

        try syncOnSMCQueue {
            guard connection != 0 else {
                throw SMCError.connectionFailed
            }

            var output = SMCParamStruct()
            var outputSize = MemoryLayout<SMCParamStruct>.stride

            // AppleSMC exposes a single struct-method entry point; the selector is sent as a byte-sized command number.
            let result = IOConnectCallStructMethod(
                connection,
                UInt32(SMCSelector.kSMCHandleYPCEvent.rawValue),
                &input,
                MemoryLayout<SMCParamStruct>.stride,
                &output,
                &outputSize
            )

            guard result == KERN_SUCCESS else {
                throw SMCError.connectionFailed
            }

            // AppleSMC reports command-specific failures in the result byte even when the IOKit call itself succeeds.
            if !allowSMCErrorResult, output.result != 0 {
                throw SMCError.keyNotFound
            }

            return output
        }
    }

    private func closeLocked() {
        if connection != 0 {
            _ = IOServiceClose(connection)
            connection = 0
        }

        if service != 0 {
            _ = IOObjectRelease(service)
            service = 0
        }
    }

    private func syncOnSMCQueue<T>(_ operation: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: Self.queueKey) == Self.queueToken {
            return try operation()
        }

        return try smcQueue.sync {
            try operation()
        }
    }

    private func mockCallSMC(_ input: inout SMCParamStruct) throws -> SMCParamStruct {
        guard var state = mockState else {
            throw SMCError.connectionFailed
        }

        let key = input.key.toString
        let selector = input.data8
        var output = SMCParamStruct()
        output.key = input.key

        switch selector {
        case SMCSelector.kSMCGetKeyInfo.rawValue:
            output.keyInfo = mockKeyInfo(for: key)
        case SMCSelector.kSMCReadKey.rawValue:
            output.keyInfo = mockKeyInfo(for: key)
            output.bytes = mockBytes(for: key, state: state)
        case SMCSelector.kSMCWriteKey.rawValue:
            applyMockWrite(key: key, input: input, state: &state)
            output.keyInfo = mockKeyInfo(for: key)
        default:
            break
        }

        output.result = 0
        mockState = state
        return output
    }

    private func mockKeyInfo(for key: String) -> SMCKeyInfoData {
        switch key {
        case SMCKey.FAN_NUM:
            return SMCKeyInfoData(dataSize: 1, dataType: DataType.ui8.rawValue.fourCharCode, dataAttributes: 0)
        case SMCKey.FAN_FORCE, "F0Md", "F1Md":
            return SMCKeyInfoData(dataSize: 1, dataType: DataType.ui8.rawValue.fourCharCode, dataAttributes: 0)
        case "F0Ac", "F0Mn", "F0Mx", "F0Tg", "F1Ac", "F1Mn", "F1Mx", "F1Tg":
            return SMCKeyInfoData(dataSize: 2, dataType: DataType.fpe2.rawValue.fourCharCode, dataAttributes: 0)
        default:
            return SMCKeyInfoData(dataSize: 1, dataType: DataType.ui8.rawValue.fourCharCode, dataAttributes: 0)
        }
    }

    private func mockBytes(for key: String, state: MockState) -> SMCBytes {
        var bytes = Array(repeating: UInt8(0), count: 32)

        func write(_ value: UInt16) {
            bytes[0] = UInt8((value >> 8) & 0xFF)
            bytes[1] = UInt8(value & 0xFF)
        }

        switch key {
        case SMCKey.FAN_NUM:
            bytes[0] = UInt8(state.fanCount)
        case SMCKey.FAN_FORCE:
            bytes[0] = state.fanForce
        case "F0Ac": write(UInt16(state.fans[0].currentRPM * 4))
        case "F0Mn": write(UInt16(state.fans[0].minRPM * 4))
        case "F0Mx": write(UInt16(state.fans[0].maxRPM * 4))
        case "F0Tg": write(UInt16(state.fans[0].targetRPM * 4))
        case "F0Md": bytes[0] = state.fans[0].isManualMode ? 1 : 0
        case "F1Ac": write(UInt16(state.fans[1].currentRPM * 4))
        case "F1Mn": write(UInt16(state.fans[1].minRPM * 4))
        case "F1Mx": write(UInt16(state.fans[1].maxRPM * 4))
        case "F1Tg": write(UInt16(state.fans[1].targetRPM * 4))
        case "F1Md": bytes[0] = state.fans[1].isManualMode ? 1 : 0
        default:
            break
        }

        return tuple(from: bytes)
    }

    private func applyMockWrite(key: String, input: SMCParamStruct, state: inout MockState) {
        switch key {
        case SMCKey.FAN_FORCE:
            state.fanForce = input.bytes.0
        case "F0Md":
            state.fans[0].isManualMode = input.bytes.0 != 0
        case "F1Md":
            state.fans[1].isManualMode = input.bytes.0 != 0
        case "F0Tg":
            let value = Float((UInt16(input.bytes.0) << 8) | UInt16(input.bytes.1)) / 4.0
            state.fans[0].targetRPM = value
            state.fans[0].currentRPM = value
            state.fans[0].isManualMode = true
        case "F1Tg":
            let value = Float((UInt16(input.bytes.0) << 8) | UInt16(input.bytes.1)) / 4.0
            state.fans[1].targetRPM = value
            state.fans[1].currentRPM = value
            state.fans[1].isManualMode = true
        default:
            break
        }
    }

    private func tuple(from bytes: [UInt8]) -> SMCBytes {
        (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15],
            bytes[16], bytes[17], bytes[18], bytes[19],
            bytes[20], bytes[21], bytes[22], bytes[23],
            bytes[24], bytes[25], bytes[26], bytes[27],
            bytes[28], bytes[29], bytes[30], bytes[31]
        )
    }
}




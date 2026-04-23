import Foundation
import IOKit
import SwiftUI

public final class SMCConnection: ObservableObject {
    private static let queueKey = DispatchSpecificKey<UInt8>()
    private static let queueToken: UInt8 = 1

    public let smcQueue = DispatchQueue(label: "com.fanforge.smc")
    private var connection: io_connect_t = 0
    private var service: io_service_t = 0

    public init() {
        smcQueue.setSpecific(key: Self.queueKey, value: Self.queueToken)
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
        syncOnSMCQueue {
            closeLocked()
        }
    }

    public func callSMC(
        _ input: inout SMCParamStruct,
        allowSMCErrorResult: Bool = false
    ) throws -> SMCParamStruct {
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
}



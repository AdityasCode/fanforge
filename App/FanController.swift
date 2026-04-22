import Foundation
import Combine

struct FanState: Identifiable, Equatable {
    let id: Int
    var currentRPM: Float
    var minRPM: Float
    var maxRPM: Float
    var targetRPM: Float
    var isManualMode: Bool
    var label: String
    var lastWriteAccepted: Bool
}

@MainActor
final class FanController: ObservableObject {
    @Published var fans: [FanState] = []
    @Published var isPolling: Bool = false
    @Published var lastError: SMCError? = nil
    @Published var firmwareLocked: Bool = false
    @Published var smcUnavailable: Bool = false
    @Published var helperInstalled: Bool = false
    @Published var helperErrorMessage: String?

    private var pollingTimer: AnyCancellable?

    private let connection: SMCConnection
    private let reader: SMCReader
#if DEBUG_NO_HELPER
    private let writer: SMCWriter
#else
    private let helperConnection: HelperConnection
#endif

    init(
        connection: SMCConnection,
#if DEBUG_NO_HELPER
        helperConnection: HelperConnection? = nil
#else
        helperConnection: HelperConnection = HelperConnection()
#endif
    ) {
        self.connection = connection
        self.reader = SMCReader(connection: connection)
#if DEBUG_NO_HELPER
        self.writer = SMCWriter(connection: connection)
#else
        self.helperConnection = helperConnection
#endif
    }

    var writeControlsEnabled: Bool {
#if DEBUG_NO_HELPER
        return !smcUnavailable
#else
        return !smcUnavailable && helperInstalled
#endif
    }

    func connect() async {
        if connection.isOpen {
            smcUnavailable = false
#if DEBUG_NO_HELPER
            helperInstalled = true
#endif
        } else {
            do {
                try await performBackgroundRead {
                    try self.connection.open()
                }
                smcUnavailable = false
            } catch let error as SMCError {
                lastError = error
                if case .connectionFailed = error {
                    smcUnavailable = true
                }
            } catch {
                lastError = .connectionFailed
                smcUnavailable = true
            }
        }

#if DEBUG_NO_HELPER
        helperInstalled = !smcUnavailable
#else
        helperInstalled = await helperConnection.isHelperReachable()
#endif
    }

    func enableFanControl() async {
#if DEBUG_NO_HELPER
        helperInstalled = !smcUnavailable
        helperErrorMessage = nil
#else
        do {
            try await helperConnection.installHelperIfNeeded()
            helperInstalled = true
            helperErrorMessage = nil
        } catch {
            helperInstalled = false
            helperErrorMessage = error.localizedDescription
        }
#endif
    }

    func refreshNow() async {
        await refreshFanStates()
    }

    func startPolling(interval: TimeInterval = 2.0) {
        guard pollingTimer == nil else {
            return
        }

        isPolling = true

        pollingTimer = Timer
            .publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .receive(on: DispatchQueue.global(qos: .utility))
            .sink { [weak self] _ in
                guard let self else { return }
                Task {
                    await self.refreshFanStates()
                }
            }

        Task {
            await refreshFanStates()
        }
    }

    func stopPolling() {
        pollingTimer?.cancel()
        pollingTimer = nil
        isPolling = false
    }

    private func refreshFanStates() async {
        do {
            let refreshedFans = try await performBackgroundRead {
                try self.readAllFanStates()
            }
            fans = refreshedFans
            lastError = nil
        } catch let error as SMCError {
            lastError = error
            if case .firmwareLocked = error {
                firmwareLocked = true
            } else if case .connectionFailed = error {
                smcUnavailable = true
            }
        } catch {
            lastError = .connectionFailed
            smcUnavailable = true
        }
    }

    func setFanSpeed(fanIndex: Int, rpm: Float) async {
        guard writeControlsEnabled else {
            lastError = .writeNotPermitted
            return
        }

        do {
#if DEBUG_NO_HELPER
            try await performBackgroundRead {
                try self.writer.setFanTargetRPM(fanIndex: fanIndex, rpm: rpm)
            }
#else
            try await helperConnection.setFanSpeed(fanIndex: fanIndex, rpm: rpm)
#endif
            if let existingIndex = fans.firstIndex(where: { $0.id == fanIndex }) {
                fans[existingIndex].targetRPM = rpm
                fans[existingIndex].isManualMode = true
#if DEBUG_NO_HELPER
                fans[existingIndex].lastWriteAccepted = writer.lastWriteAccepted(for: fanIndex)
#else
                fans[existingIndex].lastWriteAccepted = true
#endif
            }
            firmwareLocked = false
            lastError = nil
        } catch let error as SMCError {
            if case .firmwareLocked = error {
                firmwareLocked = true
            } else if case .connectionFailed = error {
                smcUnavailable = true
            }
            lastError = error
            if let existingIndex = fans.firstIndex(where: { $0.id == fanIndex }) {
                fans[existingIndex].lastWriteAccepted = false
            }
        } catch {
            lastError = .connectionFailed
            smcUnavailable = true
        }
    }

    func resetFanToAuto(fanIndex: Int) async {
        guard writeControlsEnabled else {
            lastError = .writeNotPermitted
            return
        }

        do {
#if DEBUG_NO_HELPER
            try await performBackgroundRead {
                try self.writer.resetFanToAuto(fanIndex: fanIndex)
            }
#else
            try await helperConnection.resetFan(fanIndex: fanIndex)
#endif
            if let existingIndex = fans.firstIndex(where: { $0.id == fanIndex }) {
                fans[existingIndex].isManualMode = false
#if DEBUG_NO_HELPER
                fans[existingIndex].lastWriteAccepted = writer.lastWriteAccepted(for: fanIndex)
#else
                fans[existingIndex].lastWriteAccepted = true
#endif
            }
            firmwareLocked = false
            lastError = nil
        } catch let error as SMCError {
            if case .firmwareLocked = error {
                firmwareLocked = true
            }
            lastError = error
        } catch {
            lastError = .connectionFailed
        }
    }

    func resetAllToAuto() async {
        guard writeControlsEnabled else {
            lastError = .writeNotPermitted
            return
        }

        do {
#if DEBUG_NO_HELPER
            let fanIDs = fans.map(\.id)
            try await performBackgroundRead {
                for fanID in fanIDs {
                    try self.writer.resetFanToAuto(fanIndex: fanID)
                }
            }
#else
            try await helperConnection.resetAllFans()
#endif
            firmwareLocked = false
            lastError = nil
            for index in fans.indices {
                fans[index].isManualMode = false
                fans[index].lastWriteAccepted = true
            }
        } catch let error as SMCError {
            lastError = error
            if case .firmwareLocked = error {
                firmwareLocked = true
            } else if case .connectionFailed = error {
                smcUnavailable = true
            }
        } catch {
            lastError = .connectionFailed
            smcUnavailable = true
        }
    }

    private func readAllFanStates() throws -> [FanState] {
        let fanCount = try reader.readFanCount()

        var output: [FanState] = []
        output.reserveCapacity(max(fanCount, 0))

        for fanIndex in 0..<fanCount {
            let current = try reader.readFanRPM(fanIndex: fanIndex)
            let min = try reader.readFanMin(fanIndex: fanIndex)
            let max = try reader.readFanMax(fanIndex: fanIndex)
            let target = try readFanTargetRPM(fanIndex: fanIndex)
            let mode = try readFanManualMode(fanIndex: fanIndex)
            let accepted: Bool
#if DEBUG_NO_HELPER
            accepted = writer.lastWriteAccepted(for: fanIndex)
#else
            accepted = fans.first(where: { $0.id == fanIndex })?.lastWriteAccepted ?? true
#endif

            output.append(
                FanState(
                    id: fanIndex,
                    currentRPM: current,
                    minRPM: min,
                    maxRPM: max,
                    targetRPM: target,
                    isManualMode: mode,
                    label: labelForFan(index: fanIndex, totalCount: fanCount),
                    lastWriteAccepted: accepted
                )
            )
        }

        return output
    }

    private func readFanTargetRPM(fanIndex: Int) throws -> Float {
        let key = "F\(fanIndex)Tg"
        let output = try reader.readKey(key)

        guard let dataType = DataType(rawValue: output.keyInfo.dataType.toString) else {
            throw SMCError.unsupportedDataType
        }

        switch dataType {
        case .fpe2:
            return reader.decodeFPE2(output.bytes)
        case .sp78:
            return reader.decodeSP78(output.bytes)
        case .ui16:
            // Some firmwares expose target RPM as an integer 16-bit value.
            let raw = (UInt16(output.bytes.0) << 8) | UInt16(output.bytes.1)
            return Float(raw)
        default:
            throw SMCError.unsupportedDataType
        }
    }

    private func readFanManualMode(fanIndex: Int) throws -> Bool {
        let key = "F\(fanIndex)Md"
        let output = try reader.readKey(key)

        guard let dataType = DataType(rawValue: output.keyInfo.dataType.toString) else {
            throw SMCError.unsupportedDataType
        }

        switch dataType {
        case .ui8, .flag:
            // Non-zero mode byte means the firmware currently considers the fan in manual mode.
            return output.bytes.0 != 0
        default:
            throw SMCError.unsupportedDataType
        }
    }

    private func labelForFan(index: Int, totalCount: Int) -> String {
        let defaultLabel: String

        if totalCount == 2 {
            defaultLabel = index == 0 ? "Left Fan" : "Right Fan"
        } else {
            defaultLabel = "Fan \(index)"
        }

        let key = Self.customFanLabelKey(for: index)
        if let override = UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty {
            return override
        }

        return defaultLabel
    }

    private func performBackgroundRead<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func customFanLabelKey(for fanIndex: Int) -> String {
        "fanforge.customFanLabel.\(fanIndex)"
    }
}


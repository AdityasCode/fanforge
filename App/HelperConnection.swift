import Foundation
import ServiceManagement
import Security

@MainActor
final class HelperConnection: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var helperVersion: String?

    private var connection: NSXPCConnection?
    private let machServiceName: String

    init(machServiceName: String = fanForgeHelperMachServiceName) {
        self.machServiceName = machServiceName
    }

    deinit {
        connection?.invalidate()
    }

    func connect() {
        connection?.invalidate()

        let xpcConnection = NSXPCConnection(machServiceName: machServiceName, options: .privileged)
        xpcConnection.remoteObjectInterface = NSXPCInterface(with: FanForgeHelperProtocol.self)
        xpcConnection.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.isConnected = false
            }
        }
        xpcConnection.interruptionHandler = { [weak self] in
            Task { @MainActor in
                self?.isConnected = false
            }
        }
        xpcConnection.resume()

        connection = xpcConnection
        isConnected = true
    }

    func installHelperIfNeeded() async throws {
        connect()

        do {
            let version = try await getVersion()
            helperVersion = version
            return
        } catch {
            connection?.invalidate()
            connection = nil
            isConnected = false
        }

        try blessHelper()
        connect()
        helperVersion = try await getVersion()
    }

    func isHelperReachable() async -> Bool {
        connect()

        do {
            helperVersion = try await getVersion()
            return true
        } catch {
            isConnected = false
            connection?.invalidate()
            connection = nil
            return false
        }
    }

    func setFanSpeed(fanIndex: Int, rpm: Float) async throws {
        let proxy = try helperProxy()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            proxy.setFanSpeed(fanIndex: fanIndex, rpm: rpm) { success, message in
                if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: SMCError.firmwareLocked(message: message ?? "Helper rejected fan speed request."))
                }
            }
        }
    }

    func resetFan(fanIndex: Int) async throws {
        let proxy = try helperProxy()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            proxy.resetFanToAuto(fanIndex: fanIndex) { success, message in
                if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: SMCError.firmwareLocked(message: message ?? "Helper rejected fan reset request."))
                }
            }
        }
    }

    func resetAllFans() async throws {
        let proxy = try helperProxy()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            proxy.resetAllFans { success, message in
                if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: SMCError.firmwareLocked(message: message ?? "Helper rejected reset-all request."))
                }
            }
        }
    }

    private func getVersion() async throws -> String {
        let proxy = try helperProxy()

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            proxy.getVersion { version in
                continuation.resume(returning: version)
            }
        }
    }

    private func helperProxy() throws -> FanForgeHelperProtocol {
        guard let connection else {
            throw HelperConnectionError.notConnected
        }

        let remote = connection.remoteObjectProxyWithErrorHandler { error in
            Task { @MainActor in
                self.isConnected = false
            }
            NSLog("Helper XPC error: \(error.localizedDescription)")
        }

        guard let proxy = remote as? FanForgeHelperProtocol else {
            throw HelperConnectionError.notConnected
        }

        return proxy
    }

    private func blessHelper() throws {
        var authorizationRef: AuthorizationRef?

        var authItem = AuthorizationItem(
            name: kSMRightBlessPrivilegedHelper,
            valueLength: 0,
            value: nil,
            flags: 0
        )
        var authRights = AuthorizationRights(count: 1, items: &authItem)

        let authFlags: AuthorizationFlags = [.interactionAllowed, .extendRights, .preAuthorize]
        let authStatus = AuthorizationCreate(&authRights, nil, authFlags, &authorizationRef)
        guard authStatus == errAuthorizationSuccess, let authorizationRef else {
            throw HelperConnectionError.authorizationFailed(status: authStatus)
        }

        defer {
            AuthorizationFree(authorizationRef, [])
        }

        var cfError: Unmanaged<CFError>?
        let blessed = SMJobBless(kSMDomainSystemLaunchd, machServiceName as CFString, authorizationRef, &cfError)
        guard blessed else {
            let error = cfError?.takeRetainedValue()
            throw HelperConnectionError.installFailed(message: error?.localizedDescription)
        }
    }
}

enum HelperConnectionError: LocalizedError {
    case notConnected
    case authorizationFailed(status: OSStatus)
    case installFailed(message: String?)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Unable to connect to the FanForge privileged helper."
        case .authorizationFailed(let status):
            return "Authorization for helper installation failed (status: \(status))."
        case .installFailed(let message):
            return message ?? "SMJobBless could not install or update the privileged helper."
        }
    }
}


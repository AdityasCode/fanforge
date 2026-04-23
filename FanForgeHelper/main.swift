import Foundation

final class HelperXPCDelegate: NSObject, NSXPCListenerDelegate, FanForgeHelperProtocol {
    private let helperWriter: HelperSMCWriter?

    override init() {
        self.helperWriter = try? HelperSMCWriter()
        super.init()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: FanForgeHelperProtocol.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }

    func setFanSpeed(fanIndex: Int, rpm: Float, reply: @escaping (Bool, String?) -> Void) {
        guard let helperWriter else {
            reply(false, "SMC helper not initialized")
            return
        }

        do {
            try helperWriter.setFanSpeed(fanIndex: fanIndex, rpm: rpm)
            reply(true, nil)
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    func resetFanToAuto(fanIndex: Int, reply: @escaping (Bool, String?) -> Void) {
        guard let helperWriter else {
            reply(false, "SMC helper not initialized")
            return
        }

        do {
            try helperWriter.resetFanToAuto(fanIndex: fanIndex)
            reply(true, nil)
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    func resetAllFans(reply: @escaping (Bool, String?) -> Void) {
        guard let helperWriter else {
            reply(false, "SMC helper not initialized")
            return
        }

        do {
            try helperWriter.resetAllFans()
            reply(true, nil)
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    func getVersion(reply: @escaping (String) -> Void) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        reply(version)
    }
}

let delegate = HelperXPCDelegate()
let listener = NSXPCListener(machServiceName: fanForgeHelperMachServiceName)
listener.delegate = delegate
listener.resume()
RunLoop.current.run()

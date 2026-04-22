import Foundation

let fanForgeHelperMachServiceName = "com.adityagandhi.FanForge.helper"

@objc protocol FanForgeHelperProtocol {
    func setFanSpeed(fanIndex: Int, rpm: Float, reply: @escaping (Bool, String?) -> Void)
    func resetFanToAuto(fanIndex: Int, reply: @escaping (Bool, String?) -> Void)
    func resetAllFans(reply: @escaping (Bool, String?) -> Void)
    func getVersion(reply: @escaping (String) -> Void)
}


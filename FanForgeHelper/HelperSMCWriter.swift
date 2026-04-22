import Foundation

final class HelperSMCWriter {
    private let connection: SMCConnection
    private let writer: SMCWriter

    init(connection: SMCConnection = SMCConnection()) throws {
        self.connection = connection
        self.writer = SMCWriter(connection: connection)
        try connection.open()
    }

    func setFanSpeed(fanIndex: Int, rpm: Float) throws {
        try writer.setFanTargetRPM(fanIndex: fanIndex, rpm: rpm)
    }

    func resetFanToAuto(fanIndex: Int) throws {
        try writer.resetFanToAuto(fanIndex: fanIndex)
    }

    func resetAllFans() throws {
        let reader = SMCReader(connection: connection)
        let fanCount = try reader.readFanCount()
        for fanIndex in 0..<fanCount {
            try writer.resetFanToAuto(fanIndex: fanIndex)
        }
    }
}


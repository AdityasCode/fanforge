import Foundation

public extension FanController {
    var statusBarLabel: String {
        guard !fans.isEmpty else {
            return "≋ Auto"
        }

        if fans.contains(where: { $0.isManualMode }) {
            let maxTarget = fans
                .filter { $0.isManualMode }
                .map(\.targetRPM)
                .max() ?? 0
            return "⚙ \(Int(maxTarget)) rpm"
        }

        return "≋ Auto"
    }
}



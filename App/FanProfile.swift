import Foundation

struct FanProfile: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var icon: String
    var fanSpeeds: [Int: Float]
    let createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        icon: String,
        fanSpeeds: [Int: Float],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.fanSpeeds = fanSpeeds
        self.createdAt = createdAt
    }

    static let presets: [FanProfile] = [
        FanProfile(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "Silent",
            icon: "moon.fill",
            fanSpeeds: [:],
            createdAt: Date(timeIntervalSince1970: 1)
        ),
        FanProfile(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            name: "Balanced",
            icon: "slider.horizontal.3",
            fanSpeeds: [0: 2400, 1: 2400],
            createdAt: Date(timeIntervalSince1970: 2)
        ),
        FanProfile(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            name: "Performance",
            icon: "flame.fill",
            fanSpeeds: [0: 4000, 1: 4000],
            createdAt: Date(timeIntervalSince1970: 3)
        ),
        FanProfile(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            name: "Max Cool",
            icon: "wind",
            fanSpeeds: [0: 6000, 1: 6000],
            createdAt: Date(timeIntervalSince1970: 4)
        )
    ]

    static var presetIDs: Set<UUID> {
        Set(presets.map(\.id))
    }
}


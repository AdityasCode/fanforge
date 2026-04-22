import Foundation

@MainActor
final class ProfileManager: ObservableObject {
    @Published var profiles: [FanProfile] = []
    @Published var activeProfileID: UUID?

    private let defaults = UserDefaults.standard
    private let profilesKey = "fanforge.profiles"
    private let activeKey = "fanforge.activeProfile"

    init() {
        load()
    }

    func save() {
        do {
            let data = try JSONEncoder.fanForgeProfiles.encode(profiles)
            defaults.set(data, forKey: profilesKey)
            defaults.set(activeProfileID?.uuidString, forKey: activeKey)
        } catch {
            // Persistence errors should not crash the UI; keep the in-memory state.
        }
    }

    func load() {
        let savedProfiles: [FanProfile]

        if let data = defaults.data(forKey: profilesKey),
           let decoded = try? JSONDecoder.fanForgeProfiles.decode([FanProfile].self, from: data) {
            savedProfiles = decoded
        } else {
            savedProfiles = []
        }

        let customProfiles = savedProfiles.filter { !FanProfile.presetIDs.contains($0.id) }
        profiles = FanProfile.presets + customProfiles

        if let activeString = defaults.string(forKey: activeKey),
           let activeID = UUID(uuidString: activeString),
           profiles.contains(where: { $0.id == activeID }) {
            activeProfileID = activeID
        } else {
            activeProfileID = nil
        }
    }

    func activate(_ profile: FanProfile, using controller: FanController) async {
        if profile.fanSpeeds.isEmpty {
            await controller.resetAllToAuto()
        } else {
            for fanIndex in profile.fanSpeeds.keys.sorted() {
                if let rpm = profile.fanSpeeds[fanIndex] {
                    await controller.setFanSpeed(fanIndex: fanIndex, rpm: rpm)
                }
            }
        }

        activeProfileID = profile.id
        save()
        await controller.refreshNow()
    }

    func createProfile(name: String, icon: String, from controller: FanController) -> FanProfile {
        let snapshotSpeeds = Dictionary(uniqueKeysWithValues: controller.fans.map { ($0.id, $0.targetRPM) })
        let profile = FanProfile(name: name, icon: icon, fanSpeeds: snapshotSpeeds)
        profiles.append(profile)
        activeProfileID = profile.id
        save()
        return profile
    }

    func deleteProfile(_ profile: FanProfile) {
        guard !FanProfile.presetIDs.contains(profile.id) else { return }
        profiles.removeAll { $0.id == profile.id }
        if activeProfileID == profile.id {
            activeProfileID = nil
        }
        save()
    }

    func isPreset(_ profile: FanProfile) -> Bool {
        FanProfile.presetIDs.contains(profile.id)
    }

    func exportProfilesJSON() throws -> Data {
        try JSONEncoder.fanForgeProfiles.encode(profiles)
    }
}

private extension JSONEncoder {
    static var fanForgeProfiles: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var fanForgeProfiles: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}


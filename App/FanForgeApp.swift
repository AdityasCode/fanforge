import SwiftUI
import AppKit

@main
struct FanForgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var fanController: FanController
    @StateObject private var profileManager: ProfileManager

    init() {
        let connection = SMCConnection()
        _fanController = StateObject(wrappedValue: FanController(connection: connection))
        _profileManager = StateObject(wrappedValue: ProfileManager())
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(fanController)
                .environmentObject(profileManager)
                .frame(width: 320)
        } label: {
            Label(fanController.statusBarLabel, systemImage: "fan")
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Settings", id: "settings") {
            SettingsView()
                .environmentObject(fanController)
                .environmentObject(profileManager)
        }
        .defaultSize(width: 420, height: 320)
    }
}




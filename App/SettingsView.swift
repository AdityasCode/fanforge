import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject private var fanController: FanController
    @EnvironmentObject private var profileManager: ProfileManager
    @AppStorage("fanforge.pollingInterval") private var pollingInterval: Double = 2.0
    @AppStorage(FanController.customFanLabelKey(for: 0)) private var fan0Label: String = ""
    @AppStorage(FanController.customFanLabelKey(for: 1)) private var fan1Label: String = ""
    @State private var launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    @State private var lastLoginItemError: String?
    @State private var exportMessage: String?

    private let pollingOptions: [Double] = [1, 2, 5, 10]

    var body: some View {
        NavigationStack {
            Form {
                Section("General") {
                    Picker("Polling interval", selection: $pollingInterval) {
                        ForEach(pollingOptions, id: \.self) { value in
                            Text("\(Int(value))s").tag(value)
                        }
                    }

                    Toggle("Launch at login", isOn: Binding(
                        get: { launchAtLoginEnabled },
                        set: { newValue in
                            setLoginItemEnabled(newValue)
                        }
                    ))

                    if let lastLoginItemError {
                        Text(lastLoginItemError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("Fan Labels") {
                    TextField("Fan 0 Label", text: $fan0Label)
                    TextField("Fan 1 Label", text: $fan1Label)
                }

                Section("Profiles") {
                    ForEach(profileManager.profiles) { profile in
                        HStack(spacing: 10) {
                            Label(profile.name, systemImage: profile.icon)
                            Spacer()

                            if profileManager.activeProfileID == profile.id {
                                Text("Active")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if !profileManager.isPreset(profile) {
                                Button {
                                    profileManager.deleteProfile(profile)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.red)
                            }
                        }
                    }

                    Button("Export Profiles") {
                        exportProfiles()
                    }

                    if let exportMessage {
                        Text(exportMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        resetAllSettings()
                    } label: {
                        Text("Reset All Settings")
                    }
                }
            }
            .padding(12)
            .navigationTitle("Settings")
        }
        .frame(minWidth: 420, minHeight: 280)
        .onAppear {
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        }
        .onChange(of: fan0Label) { _ in
            Task { await fanController.refreshNow() }
        }
        .onChange(of: fan1Label) { _ in
            Task { await fanController.refreshNow() }
        }
    }

    private func setLoginItemEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginEnabled = enabled
            lastLoginItemError = nil
        } catch {
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
            lastLoginItemError = error.localizedDescription
        }
    }

    private func resetAllSettings() {
        pollingInterval = 2.0
        fan0Label = ""
        fan1Label = ""
        setLoginItemEnabled(false)
        profileManager.load()
        exportMessage = nil
        Task { await fanController.refreshNow() }
    }

    private func exportProfiles() {
        do {
            let data = try profileManager.exportProfilesJSON()
            let desktopURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Desktop")
                .appendingPathComponent("FanForgeProfiles.json")
            try data.write(to: desktopURL, options: [.atomic])
            exportMessage = "Exported to Desktop/FanForgeProfiles.json"
        } catch {
            exportMessage = error.localizedDescription
        }
    }
}


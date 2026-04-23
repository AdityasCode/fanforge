import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var fanController: FanController
    @EnvironmentObject private var profileManager: ProfileManager
    @Environment(\.openWindow) private var openWindow

    @AppStorage("fanforge.pollingInterval") private var pollingInterval: Double = 2.0

    @State private var isResettingAll = false
    @State private var showingCreateProfile = false
    @State private var newProfileName = "Custom"
    @State private var newProfileIcon = "slider.horizontal.3"

    private let createProfileIcons = [
        "moon.fill",
        "slider.horizontal.3",
        "flame.fill",
        "wind",
        "snowflake",
        "leaf.fill",
        "hare.fill",
        "tortoise.fill"
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                headerRow

                if fanController.smcUnavailable {
                    unavailableBanner
                }

                if fanController.firmwareLocked {
                    firmwareBanner
                }

                if !fanController.writeControlsEnabled {
                    enableFanControlRow
                }

                profileChipsRow

                ForEach($fanController.fans) { $fan in
                    FanCardView(fan: $fan) { rpm in
                        Task {
                            await fanController.setFanSpeed(fanIndex: fan.id, rpm: rpm)
                        }
                    }
                }

                footerRow
            }
            .padding(12)
        }
        .frame(width: 320)
        .task {
            await fanController.connect()
            if !fanController.smcUnavailable {
                fanController.startPolling(interval: pollingInterval)
            }
        }
        .onChange(of: pollingInterval) { newValue in
            fanController.stopPolling()
            if !fanController.smcUnavailable {
                fanController.startPolling(interval: newValue)
            }
        }
        .sheet(isPresented: $showingCreateProfile) {
            createProfileSheet
        }
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "wind")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("FanForge")
                .font(.headline)

            Spacer()

            Button {
                openWindow(id: "settings")
            } label: {
                Image(systemName: "gearshape")
                    .imageScale(.medium)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Open Settings")
        }
    }

    private var unavailableBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.secondary)

            Text("SMC unavailable — read-only mode or virtual machine detected")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
        )
    }

    private var firmwareBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)

            Text("M-series firmware is managing fans. Speed overrides are limited.")
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.16))
        )
    }

    private var enableFanControlRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fan speed writes require the privileged helper.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Enable fan control") {
                Task {
                    await fanController.enableFanControl()
                }
            }
            .buttonStyle(.borderedProminent)

            if let helperErrorMessage = fanController.helperErrorMessage {
                Text(helperErrorMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.10))
        )
    }

    private var profileChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(profileManager.profiles) { profile in
                    Button {
                        Task {
                            guard fanController.writeControlsEnabled else { return }
                            await profileManager.activate(profile, using: fanController)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: profile.icon)
                            Text(profile.name)
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(profileChipBackground(for: profile))
                        .foregroundStyle(profileManager.activeProfileID == profile.id ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!fanController.writeControlsEnabled)
                }

                Button {
                    showingCreateProfile = true
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.weight(.bold))
                        .frame(width: 30, height: 30)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!fanController.writeControlsEnabled)
            }
        }
    }

    private var footerRow: some View {
        HStack {
            Button {
                Task {
                    isResettingAll = true
                    defer { isResettingAll = false }
                    await fanController.resetAllToAuto()
                    await fanController.refreshNow()
                }
            } label: {
                HStack(spacing: 8) {
                    if isResettingAll {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text("Reset All to Auto")
                }
            }
            .disabled(isResettingAll || fanController.fans.isEmpty || !fanController.writeControlsEnabled)
            .redacted(reason: isResettingAll ? .placeholder : [])

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(fanController.isPolling ? Color.green : Color.secondary.opacity(0.45))
                    .frame(width: 8, height: 8)

                Text(fanController.isPolling ? "Polling" : "Paused")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }

    private func profileChipBackground(for profile: FanProfile) -> some View {
        Capsule(style: .continuous)
            .fill(profileManager.activeProfileID == profile.id ? Color.accentColor : Color.secondary.opacity(0.12))
    }

    private var createProfileSheet: some View {
        CreateProfileSheet(
            name: $newProfileName,
            icon: $newProfileIcon,
            icons: createProfileIcons,
            onCreate: {
                let trimmed = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
                _ = profileManager.createProfile(name: trimmed, icon: newProfileIcon, from: fanController)
                showingCreateProfile = false
                newProfileName = "Custom"
                newProfileIcon = createProfileIcons.first ?? "slider.horizontal.3"
            },
            onCancel: {
                showingCreateProfile = false
            }
        )
        .frame(width: 320, height: 300)
        .padding()
    }
}

private struct CreateProfileSheet: View {
    @Binding var name: String
    @Binding var icon: String
    let icons: [String]
    let onCreate: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Profile")
                .font(.headline)

            TextField("Profile Name", text: $name)

            Picker("Icon", selection: $icon) {
                ForEach(icons, id: \.self) { symbol in
                    Label(symbol, systemImage: symbol).tag(symbol)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(icons, id: \.self) { symbol in
                        Button {
                            icon = symbol
                        } label: {
                            Image(systemName: symbol)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Create", action: onCreate)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

#Preview {
    let connection = SMCConnection.mock()
    let controller = FanController(connection: connection)
    controller.fans = [
        FanState(id: 0, currentRPM: 2400, minRPM: 1200, maxRPM: 6400, targetRPM: 2400, isManualMode: false, label: "Left Fan", lastWriteAccepted: true),
        FanState(id: 1, currentRPM: 3200, minRPM: 1200, maxRPM: 6400, targetRPM: 3200, isManualMode: true, label: "Right Fan", lastWriteAccepted: false)
    ]

    let profileManager = ProfileManager()

    return MenuBarView()
        .environmentObject(controller)
        .environmentObject(profileManager)
}
import SwiftUI
import AppKit

struct FanCardView: View {
    @EnvironmentObject private var fanController: FanController
    @Binding var fan: FanState
    let onSetSpeed: (Float) -> Void

    @State private var isApplying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            topRow
            rangeRow
            modeToggle

            if fan.isManualMode {
                manualControls
            }
        }
        .padding(12)
        .background(cardBackground)
        .overlay(alignment: .center) {
            if isApplying {
                ProgressView()
                    .controlSize(.regular)
            }
        }
        .redacted(reason: isApplying ? .placeholder : [])
    }

    private var topRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Label(fan.label, systemImage: "fan")
                .font(.headline)

            Spacer()

            Text("\(Int(fan.currentRPM))")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())

            Text("rpm")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var rangeRow: some View {
        Text("min: \(Int(fan.minRPM)) rpm  •  max: \(Int(fan.maxRPM)) rpm")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var modeToggle: some View {
        Toggle("Manual Control", isOn: Binding(
            get: { fan.isManualMode },
            set: { newValue in
                guard !isApplying else { return }
                fan.isManualMode = newValue

                if !newValue {
                    Task {
                        isApplying = true
                        defer { isApplying = false }
                        await fanController.resetFanToAuto(fanIndex: fan.id)
                    }
                }
            }
        ))
        .toggleStyle(.switch)
        .disabled(!fanController.writeControlsEnabled)
    }

    private var manualControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Target")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(Int(fan.targetRPM)) rpm")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }

            Slider(
                value: Binding(
                    get: { Double(fan.targetRPM) },
                    set: { fan.targetRPM = Float($0) }
                ),
                in: Double(fan.minRPM)...Double(fan.maxRPM),
                step: 100
            )
            .disabled(!fanController.writeControlsEnabled)

            HStack {
                Button("Apply") {
                    Task {
                        isApplying = true
                        defer { isApplying = false }
                        onSetSpeed(fan.targetRPM)
                        try? await Task.sleep(nanoseconds: 250_000_000)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isApplying || !fanController.writeControlsEnabled)

                Spacer()
            }

            if fan.lastWriteAccepted == false {
                Label("Last write rejected by firmware", systemImage: "xmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
            } else {
                Label("Write accepted", systemImage: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .opacity(0.75)
            }
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.5))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}

private struct FanCardPreviewHost: View {
    @State private var mockFans: [FanState] = [
        FanState(id: 0, currentRPM: 2400, minRPM: 1200, maxRPM: 6400, targetRPM: 2400, isManualMode: false, label: "Left Fan", lastWriteAccepted: true),
        FanState(id: 1, currentRPM: 3200, minRPM: 1200, maxRPM: 6400, targetRPM: 3200, isManualMode: true, label: "Right Fan", lastWriteAccepted: false)
    ]

    let controller = FanController(connection: SMCConnection.mock())

    var body: some View {
        FanCardView(
            fan: $mockFans[1],
            onSetSpeed: { _ in }
        )
        .environmentObject(controller)
        .padding()
        .frame(width: 320)
    }
}

#Preview {
    FanCardPreviewHost()
}



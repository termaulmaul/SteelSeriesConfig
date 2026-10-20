import SwiftUI

/// Save / discard / re-apply, plus whatever the store last reported.
///
/// Save keeps the profile and commits it to the mouse's onboard memory. The separate
/// Apply button re-sends the saved profile, which is how you recover after another
/// tool reprogrammed the mouse.
///
/// Apply is a two-tap confirm rather than a sheet: this view lives inside a
/// non-activating `NSPanel`, where presenting modal UI is unreliable.
struct BarActionsView: View {

    @Environment(ConfigurationStore.self) private var store

    @State private var isDeployArmed = false

    private var canWrite: Bool { store.canReachDevice && !store.isBusy }

    var body: some View {
        VStack(spacing: BarMetrics.s) {
            if let message = store.statusMessage {
                HStack(spacing: BarMetrics.xs) {
                    if store.isBusy || store.isLiveApplying {
                        ProgressView()
                            .controlSize(.small)
                    } else if store.statusIsError {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }

                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button("Dismiss") {
                        store.statusMessage = nil
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }

            HStack(spacing: BarMetrics.s) {
                Button {
                    Task { await store.save() }
                } label: {
                    Text(store.isDirty ? "Save" : "Saved")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(!store.isDirty || store.isBusy)
                .help("Save the profile and write it to the mouse's onboard memory.")

                Button {
                    store.reloadDraft()
                } label: {
                    Text("Discard")
                }
                .controlSize(.large)
                .buttonStyle(.bordered)
                .disabled(!store.isDirty || store.isBusy)

                Button {
                    if isDeployArmed {
                        isDeployArmed = false
                        Task { await store.deploy() }
                    } else {
                        armDeploy()
                    }
                } label: {
                    Text(isDeployArmed ? "Confirm" : "Apply")
                }
                .controlSize(.large)
                .buttonStyle(.bordered)
                .disabled(!canWrite || store.draft == nil)
                .help(isDeployArmed ? "Tap again to re-send the saved profile to the mouse." : "Re-send the saved profile to the mouse.")
            }
        }
    }

    private func armDeploy() {
        isDeployArmed = true
        Task {
            try? await Task.sleep(for: .seconds(4))
            isDeployArmed = false
        }
    }
}

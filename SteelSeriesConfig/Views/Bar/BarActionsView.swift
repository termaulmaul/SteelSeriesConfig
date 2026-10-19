import SwiftUI

/// Save / discard / deploy, plus whatever the store last reported.
///
/// Deploy is a two-tap confirm rather than a sheet: this view lives inside a
/// non-activating `NSPanel`, where presenting modal UI is unreliable, and an
/// accidental deploy rewrites the mouse's live profile.
struct BarActionsView: View {

    @Environment(ConfigurationStore.self) private var store

    @State private var isDeployArmed = false

    var body: some View {
        VStack(spacing: 10) {
            if let message = store.statusMessage {
                HStack(spacing: 6) {
                    if store.isBusy {
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

            HStack(spacing: 8) {
                Button {
                    Task { await store.save() }
                } label: {
                    Text(store.isDirty ? "Save Changes" : "Saved")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(!store.isDirty || store.isBusy)

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
                    Text(isDeployArmed ? "Confirm" : "Deploy")
                }
                .controlSize(.large)
                .buttonStyle(.bordered)
                .disabled(store.isBusy || store.draft == nil)
                .help(isDeployArmed ? "Tap again to push this configuration to the device." : "Push the saved configuration to the device.")
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

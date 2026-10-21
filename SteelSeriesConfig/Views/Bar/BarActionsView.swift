import SwiftUI

/// Status line under the popover controls.
///
/// Edits save themselves, so there is no Save / Discard / Apply row any more: this view
/// only reports what the store last did (saved, skipped because the mouse is asleep, or
/// failed) and lets the message be dismissed.
struct BarActionsView: View {

    @Environment(ConfigurationStore.self) private var store

    var body: some View {
        if let message = store.statusMessage {
            HStack(spacing: BarMetrics.xs) {
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
    }
}

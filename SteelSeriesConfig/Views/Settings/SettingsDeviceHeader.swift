import SwiftUI

/// Store bar at the top of the Device tab: what is selected, whether the hardware is
/// in sync, and the two actions that change anything.
struct SettingsDeviceHeader: View {

    @Environment(ConfigurationStore.self) private var store

    var body: some View {
        HStack(spacing: 14) {
            EngineDeviceImage(
                urlString: store.selectedDevice?.imageUrl,
                fallbackSystemImage: "computermouse",
                height: 44
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(store.selectedDevice?.localizedName ?? "No device")
                    .font(.title3.weight(.semibold))

                HStack(spacing: 8) {
                    Text(store.selectedConfiguration?.name ?? "No configuration")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    statusBadge
                }
            }

            Spacer()

            Button("Discard") {
                store.reloadDraft()
            }
            .disabled(!store.isDirty || store.isBusy)

            Button("Save") {
                Task { await store.save() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!store.isDirty || store.isBusy)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if let sync = store.syncStatus {
            Label(
                sync.isSynced.value ? "In sync with device" : "Saved, not deployed",
                systemImage: sync.isSynced.value ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath"
            )
            .font(.caption)
            .foregroundColor(sync.isSynced.value ? .green : .orange)
        } else {
            Label("Device status unknown", systemImage: "questionmark.circle")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

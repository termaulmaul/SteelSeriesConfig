import SwiftUI

/// Store bar at the top of the Device tab: what is selected, whether the hardware is
/// in sync, and the two actions that change anything.
struct SettingsDeviceHeader: View {

    @Environment(ConfigurationStore.self) private var store

    var body: some View {
        HStack(spacing: 14) {
            DeviceGlyph(
                imageName: store.selectedDevice?.imageUrl,
                systemImage: "computermouse",
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

                    if let battery = store.batteryStatus {
                        BatteryBadgeView(status: battery)
                    }
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
            .help("Save the profile and write it to the mouse's onboard memory.")
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusBadge: some View {
        Label(
            store.isDirty ? "Unsaved changes" : "Saved",
            systemImage: store.isDirty ? "pencil.circle" : "checkmark.circle.fill"
        )
        .font(.caption)
        .foregroundColor(store.isDirty ? .orange : .green)
    }
}

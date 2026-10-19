import SwiftUI

/// Popover header: device artwork, name, and a one-line status.
///
/// The status line deliberately reports what the *engine* says — connected and
/// in-sync are separate facts, and a mouse that is connected but running a stale
/// profile looks fine until you notice it.
struct BarHeaderView: View {

    @Environment(ConfigurationStore.self) private var store

    var body: some View {
        HStack(spacing: 8) {
            EngineDeviceImage(
                urlString: store.selectedDevice?.imageUrl,
                fallbackSystemImage: "computermouse",
                height: 26
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(store.selectedDevice?.localizedName ?? "SteelSeries")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(statusLine)
                    .font(.caption2)
                    .foregroundColor(statusColor)
                    .lineLimit(1)
            }

            BarSettingsButton()
        }
        .padding(.horizontal, 4)
    }

    private var statusLine: String {
        guard let device = store.selectedDevice else { return "No device" }
        guard device.connected.value else { return "Disconnected" }

        var parts = ["Connected"]
        if let sync = store.syncStatus {
            parts.append(sync.isSynced.value ? "in sync" : "not deployed")
        } else {
            parts.append("connected")
        }
        return parts.joined(separator: " · ")
    }

    private var statusColor: Color {
        guard store.selectedDevice?.connected.value == true else { return .secondary }
        guard let sync = store.syncStatus else { return .secondary }
        return sync.isSynced.value ? .secondary : .orange
    }
}

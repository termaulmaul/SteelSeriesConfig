import SwiftUI

/// Popover header: device artwork, name, and one line of live status.
///
/// The line folds three independent facts — engine attachment, wireless link, and
/// deployment sync — into one readable string. They stay separate in the store because
/// they come from separate sources and can disagree: a mouse whose dongle is plugged in
/// but which is switched off is attached and not linked, and reporting only one of
/// those would tell a story the other half contradicts.
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

                HStack(spacing: 4) {
                    ConnectionDotView(phase: store.displayPhase)

                    Text(statusLine)
                        .font(.caption2)
                        .foregroundColor(statusColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    if let battery = store.batteryStatus, store.canReachDevice {
                        Text("·")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        BatteryBadgeView(status: battery)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }

            BarSettingsButton()
        }
        .padding(.horizontal, 4)
    }

    private var statusLine: String {
        guard store.selectedDevice != nil else { return "No device" }

        let phase = store.displayPhase
        guard phase.isUsable, let sync = store.syncStatus else { return phase.label }

        return sync.isSynced.value ? "\(phase.label) · in sync" : "\(phase.label) · not deployed"
    }

    private var statusColor: Color {
        if !store.canReachDevice { return .secondary }
        if let sync = store.syncStatus, !sync.isSynced.value { return .orange }
        if store.displayPhase == .ready { return .secondary }
        return store.displayPhase.isUsable ? .secondary : .orange
    }
}

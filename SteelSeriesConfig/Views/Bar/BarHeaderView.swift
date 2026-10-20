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
        HStack(spacing: BarMetrics.m) {
            DeviceGlyph(
                imageName: store.selectedDevice?.imageUrl,
                systemImage: "computermouse",
                height: 30
            )

            VStack(alignment: .leading, spacing: BarMetrics.xxs) {
                Text(store.selectedDevice?.localizedName ?? "SteelSeries")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: BarMetrics.xs) {
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
    }

    private var statusLine: String {
        guard store.selectedDevice != nil else { return "No device" }

        let phase = store.displayPhase
        guard phase.isUsable, store.isDirty else { return phase.label }

        return "\(phase.label) · unsaved"
    }

    private var statusColor: Color {
        if !store.canReachDevice { return .secondary }
        if store.isDirty { return .orange }
        if store.displayPhase == .ready { return .secondary }
        return store.displayPhase.isUsable ? .secondary : .orange
    }
}

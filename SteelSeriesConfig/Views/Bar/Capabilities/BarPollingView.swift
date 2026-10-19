import SwiftUI

/// Polling rate picker. Codes are mapped in `MouseSettings.pollingCode(forHz:)`,
/// matching the GG client's own switch — 1000 Hz is code 0, not 1000.
struct BarPollingView: View {

    @Environment(ConfigurationStore.self) private var store

    private var settings: MouseSettings? { store.mouseSettings }

    var body: some View {
        BarSectionView(title: "Polling Rate", value: valueText) {
            if let settings {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(MouseSettings.pollingRateOptions, id: \.self) { hz in
                        ModeCircleView(
                            name: hzLabel(hz),
                            isActive: settings.pollingRateHz == hz
                        ) {
                            store.mutate { $0.setPollingRateHz(hz) }
                        } content: {
                            Text("\(hz)")
                                .font(.system(size: hz >= 1000 ? 11 : 13, weight: .semibold))
                                .monospacedDigit()
                        }
                    }
                }
                .disabled(store.isBusy)
            } else {
                Text("Not available for this device.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var valueText: String? {
        settings.map { "\($0.pollingRateHz) Hz" }
    }

    /// Sub-label under each circle: the number is already in the circle, so this
    /// names the trade-off instead of repeating it.
    private func hzLabel(_ hz: Int) -> String {
        switch hz {
        case 1000: return "Fastest"
        case 500: return "Balanced"
        case 250: return "Smooth"
        default: return "Least load"
        }
    }
}

import SwiftUI

/// Quick CPI control: the ladder as tappable steps plus a slider for the active step.
///
/// The engine stores steps in its own units (real CPI ÷ 50, verified against the GG
/// client's own renderer); the user only ever sees and edits real CPI.
struct BarCPIView: View {

    @Environment(ConfigurationStore.self) private var store

    private var settings: MouseSettings? { store.mouseSettings }

    var body: some View {
        BarSectionView(title: "CPI", value: valueText) {
            if let settings {
                VStack(spacing: 10) {
                    if settings.cpiLevelCount > 1 {
                        HStack(spacing: 6) {
                            ForEach(0..<settings.cpiLevelCount, id: \.self) { index in
                                ModeBarView(
                                    name: "\(settings.cpiLevels[index])",
                                    isActive: index == settings.activeCPILevelIndex
                                ) {
                                    store.mutate { $0.setActiveCPILevelIndex(index) }
                                }
                            }
                        }
                    }

                    Slider(value: activeCPIBinding, in: Double(MouseSettings.cpiMinimum)...Double(MouseSettings.cpiMaximum), step: Double(MouseSettings.cpiScale))
                        .disabled(store.isBusy)

                    HStack {
                        Text("\(MouseSettings.cpiMinimum)")
                        Spacer()
                        Text("\(MouseSettings.cpiMaximum)")
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                }
            } else {
                Text(unavailableText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var valueText: String? {
        guard let settings else { return nil }
        return "\(settings.activeCPI) CPI"
    }

    private var unavailableText: String {
        store.draft == nil ? "No configuration loaded." : "This device's CPI schema is not modelled yet."
    }

    private var activeCPIBinding: Binding<Double> {
        Binding(
            get: { Double(store.mouseSettings?.activeCPI ?? MouseSettings.cpiMinimum) },
            set: { newValue in
                store.mutate { $0.setActiveCPIValue(Int(newValue)) }
            }
        )
    }
}

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
                        .disabled(store.isBusy || !store.canReachDevice)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Presets")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        HStack(spacing: 6) {
                            ForEach(MouseSettings.cpiPresets, id: \.self) { cpi in
                                presetButton(cpi)
                            }
                        }
                    }

                    Slider(value: activeCPIBinding, in: Double(MouseSettings.cpiMinimum)...Double(MouseSettings.cpiMaximum), step: Double(MouseSettings.cpiScale))
                        .disabled(store.isBusy || !store.canReachDevice)

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

    /// One-tap shortcut that overwrites the *active* ladder step with the preset value.
    ///
    /// Deliberately not a shortcut that rebuilds the ladder: the ladder belongs to the
    /// device's own profile, and a button that silently reshaped five stored steps
    /// would undo tuning the user did not ask to touch. Nothing is written either —
    /// the mutation goes through `mutate`, which live-applies and leaves the draft
    /// dirty until `save()`.
    private func presetButton(_ cpi: Int) -> some View {
        let isCurrent = settings?.activeCPI == cpi

        return Button {
            store.mutate { $0.setActiveCPIValue(cpi) }
        } label: {
            Text("\(cpi)")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isCurrent ? Color.accentColor : Color.secondary.opacity(0.18))
                )
                .foregroundColor(isCurrent ? .white : .primary)
        }
        .buttonStyle(.plain)
        .disabled(store.isBusy || !store.canReachDevice)
        .help("Set the active CPI step to \(cpi) and apply it to the mouse.")
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

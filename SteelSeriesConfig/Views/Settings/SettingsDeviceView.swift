import AppKit
import SwiftUI

/// Full mouse configuration editor.
///
/// Grouped `Form` rather than a custom layout: on macOS this is what gives you the
/// native section chrome, correct focus order, and controls that resize with the
/// window. Everything here writes through `ConfigurationStore.mutate`, which pushes the
/// change to the device and persists it to the profile after a short debounce — there
/// is no separate Apply step.
struct SettingsDeviceView: View {

    @Environment(ConfigurationStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            SettingsDeviceHeader()
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 16)

            Divider()

            if store.mouseSettings != nil {
                editor
            } else {
                unavailable
            }
        }
    }

    private var editor: some View {
        Form {
            Section("Sensitivity") {
                cpiSection
                pollingRow
            }

            // Only settings the HID protocol can express are shown. Angle snapping,
            // Exact Aim/Accel, Low-Power Gaming Mode, brightness and Smart Lighting
            // have no known command, so they are hidden rather than faked.
            Section("Power") {
                powerSaveRow
            }

            Section("Illumination") {
                IlluminationZonesEditor()
                idleTimeoutRow
                reactiveColorRow
                toggleRow(
                    "Rainbow at Startup",
                    "Runs the rainbow effect when the mouse powers up.",
                    keyPath: \.defaultLightingEnabled,
                    setter: { $0.setDefaultLightingEnabled($1) }
                )
                toggleRow(
                    "Reactive Lighting",
                    "Flashes a colour on clicks instead of running a static effect.",
                    keyPath: \.reactiveLightingEnabled,
                    setter: { $0.setReactiveLightingEnabled($1) }
                )
            }

            if store.mouseSettings?.hasButtonMappings == true {
                Section {
                    ButtonMappingEditor()
                } header: {
                    Text("Buttons")
                } footer: {
                    Text("Click a button on the mouse or pick its row, then choose an action. Changes save to the profile and the mouse automatically.")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var unavailable: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("Editing unavailable")
                .font(.headline)
            Text(unavailableReason)
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button("Rescan") {
                Task { await store.bootstrap() }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(30)
    }

    private var unavailableReason: String {
        if store.phase == .booting {
            return "Still looking for the mouse."
        }
        if store.draft == nil {
            return "No configuration was loaded for this device."
        }
        return "This device's settings schema is not modelled yet, so it is shown read-only instead of risking an unsupported write."
    }

    // MARK: - Sensitivity

    @ViewBuilder
    private var cpiSection: some View {
        if let settings = store.mouseSettings {
            SettingsRow(
                title: "CPI Ladder",
                description: "Steps the mouse cycles through. Type a count or use the arrows; click a step below to make it active."
            ) {
                NumericField(
                    value: Binding(
                        get: { settings.cpiLevelCount },
                        set: { value in store.mutate { $0.setCPILevelCount(value) } }
                    ),
                    range: 1...MouseSettings.maxCPILevels,
                    step: 1,
                    unit: "steps"
                )
            }

            ForEach(0..<settings.cpiLevelCount, id: \.self) { index in
                SettingsRow(
                    title: "Step \(index + 1)",
                    description: index == settings.activeCPILevelIndex
                        ? "Active now."
                        : "\(settings.cpiLevels[index]) CPI available in the cycle."
                ) {
                    HStack(spacing: 10) {
                        Button {
                            store.mutate { $0.setActiveCPILevelIndex(index) }
                        } label: {
                            Image(systemName: index == settings.activeCPILevelIndex
                                  ? "largecircle.fill.circle"
                                  : "circle")
                                .foregroundColor(index == settings.activeCPILevelIndex ? .accentColor : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Make this the active step")

                        NumericField(
                            value: Binding(
                                get: { settings.cpiLevels[index] },
                                set: { value in store.mutate { $0.setCPILevelAt(index, cpi: value) } }
                            ),
                            range: MouseSettings.cpiMinimum...MouseSettings.cpiMaximum,
                            step: MouseSettings.cpiScale,
                            unit: "CPI"
                        )
                    }
                }
            }
        }
    }


    private var pollingRow: some View {
        SettingsRow(
            title: "Polling Rate",
            description: "USB report rate. Higher is more responsive and uses slightly more power."
        ) {
            if let settings = store.mouseSettings {
                Picker("", selection: Binding(
                    get: { settings.pollingRateHz },
                    set: { value in store.mutate { $0.setPollingRateHz(value) } }
                )) {
                    ForEach(MouseSettings.pollingRateOptions, id: \.self) { hz in
                        Text("\(hz) Hz").tag(hz)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    private var powerSaveRow: some View {
        SettingsRow(
            title: "Idle Sleep",
            description: "Seconds of inactivity before the sensor powers down. 0 disables it."
        ) {
            if let settings = store.mouseSettings {
                NumericField(
                    value: Binding(
                        get: { settings.powerSaveSeconds },
                        set: { value in store.mutate { $0.setPowerSaveSeconds(value) } }
                    ),
                    range: 0...1200,
                    step: 30,
                    unit: "sec"
                )
            }
        }
    }

    // MARK: - Illumination

    private var reactiveColorRow: some View {
        SettingsRow(
            title: "Reactive Colour",
            description: "Colour flashed on clicks when Reactive Lighting is on."
        ) {
            if let settings = store.mouseSettings {
                HStack(spacing: 8) {
                    Text(String(
                        format: "#%02X%02X%02X",
                        settings.reactiveColor.red,
                        settings.reactiveColor.green,
                        settings.reactiveColor.blue
                    ))
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)

                    ColorPicker("", selection: reactiveColorBinding(settings), supportsOpacity: false)
                        .labelsHidden()
                        .accessibilityIdentifier("lighting.reactive.color")
                }
            }
        }
    }

    private func reactiveColorBinding(_ settings: MouseSettings) -> Binding<Color> {
        Binding(
            get: {
                Color(nsColor: NSColor(
                    srgbRed: CGFloat(settings.reactiveColor.red) / 255,
                    green: CGFloat(settings.reactiveColor.green) / 255,
                    blue: CGFloat(settings.reactiveColor.blue) / 255,
                    alpha: 1
                ))
            },
            set: { newValue in
                guard let rgb = NSColor(newValue).usingColorSpace(.sRGB) else { return }
                store.mutate {
                    $0.setReactiveColor(
                        red: Int((rgb.redComponent * 255).rounded()),
                        green: Int((rgb.greenComponent * 255).rounded()),
                        blue: Int((rgb.blueComponent * 255).rounded())
                    )
                }
            }
        )
    }

    private var idleTimeoutRow: some View {
        SettingsRow(
            title: "Dim Lighting After",
            description: "Seconds of inactivity before the lighting dims. 0 disables it."
        ) {
            if let settings = store.mouseSettings {
                NumericField(
                    value: Binding(
                        get: { settings.idleTimeoutSeconds },
                        set: { value in store.mutate { $0.setIdleTimeoutSeconds(value) } }
                    ),
                    range: 0...1200,
                    step: 5,
                    unit: "sec"
                )
            }
        }
    }

    // MARK: - Bindings

    private func toggleRow(
        _ title: String,
        _ description: String,
        keyPath: KeyPath<MouseSettings, Bool>,
        setter: @escaping (inout MouseSettings, Bool) -> Void
    ) -> some View {
        SettingsRow(title: title, description: description) {
            Toggle("", isOn: Binding(
                get: { store.mouseSettings?[keyPath: keyPath] ?? false },
                set: { newValue in store.mutate { setter(&$0, newValue) } }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
    }
}

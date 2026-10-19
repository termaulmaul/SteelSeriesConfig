import SwiftUI

/// Full mouse configuration editor.
///
/// Grouped `Form` rather than a custom layout: on macOS this is what gives you the
/// native section chrome, correct focus order, and controls that resize with the
/// window. Everything here writes through `ConfigurationStore.mutate`, which pushes the
/// change to the device as a live apply and leaves the draft dirty until Save
/// persists and deploys it for real.
struct SettingsDeviceView: View {

    @Environment(ConfigurationStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            SettingsDeviceHeader()
                .padding([.horizontal, .top], 20)
                .padding(.bottom, 4)

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

            Section("Sensor") {
                toggleRow(
                    "Angle Snapping",
                    "Straightens fast flicks. Off is usually better for aiming.",
                    keyPath: \.angleSnapping,
                    setter: { $0.setAngleSnapping($1) }
                )
                toggleRow(
                    "Exact Aim",
                    "Disables angle snapping while a mapped aim button is held.",
                    keyPath: \.exactAim,
                    setter: { $0.setExactAim($1) }
                )
                toggleRow(
                    "Exact Acceleration",
                    "Raw input with no acceleration compensation.",
                    keyPath: \.exactAccel,
                    setter: { $0.setExactAccel($1) }
                )
                toggleRow(
                    "Low-Power Gaming Mode",
                    "Keeps the sensor in its high-performance state while gaming.",
                    keyPath: \.lowPowerGamingMode,
                    setter: { $0.setLowPowerGamingMode($1) }
                )
                powerSaveRow
            }

            Section("Illumination") {
                brightnessRow
                idleBrightnessRow
                idleTimeoutRow
                toggleRow(
                    "Smart Lighting",
                    "Dims the lighting when the sensor detects no movement.",
                    keyPath: \.smartLighting,
                    setter: { $0.setSmartLighting($1) }
                )
                toggleRow(
                    "Default Lighting",
                    "Applies the default effect when no per-application profile is active.",
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
                    buttonRows
                } header: {
                    Text("Buttons")
                } footer: {
                    Text("Button remapping is read-only for now: the action-code table has not been reverse-engineered, and guessing would silently rebind your mouse.")
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
            return "Still looking for the SteelSeries engine."
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
                description: "Steps the mouse cycles through. Click a step to make it active; use the arrows to retune it."
            ) {
                Stepper(
                    value: Binding(
                        get: { settings.cpiLevelCount },
                        set: { value in store.mutate { $0.setCPILevelCount(value) } }
                    ),
                    in: 1...MouseSettings.maxCPILevels
                ) {
                    Text("\(settings.cpiLevelCount) step\(settings.cpiLevelCount == 1 ? "" : "s")")
                        .monospacedDigit()
                        .frame(minWidth: 70, alignment: .trailing)
                }
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

                        Stepper(
                            value: Binding(
                                get: { settings.cpiLevels[index] },
                                set: { value in store.mutate { $0.setCPILevelAt(index, cpi: value) } }
                            ),
                            in: MouseSettings.cpiMinimum...MouseSettings.cpiMaximum,
                            step: MouseSettings.cpiScale
                        ) {
                            Text("\(settings.cpiLevels[index]) CPI")
                                .monospacedDigit()
                                .frame(minWidth: 74, alignment: .trailing)
                        }
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
            description: "Seconds of inactivity before the sensor powers down."
        ) {
            if let settings = store.mouseSettings {
                Stepper(
                    value: Binding(
                        get: { settings.powerSaveSeconds },
                        set: { value in store.mutate { $0.setPowerSaveSeconds(value) } }
                    ),
                    in: 0...3600,
                    step: 30
                ) {
                    Text(formatDuration(settings.powerSaveSeconds))
                        .frame(minWidth: 74, alignment: .trailing)
                }
            }
        }
    }

    // MARK: - Illumination

    private var brightnessRow: some View {
        SettingsRow(
            title: "Brightness",
            description: "Overall lighting brightness while the mouse is in use."
        ) {
            if let settings = store.mouseSettings {
                Stepper(
                    value: Binding(
                        get: { settings.brightness },
                        set: { value in store.mutate { $0.setBrightness(value) } }
                    ),
                    in: 0...15
                ) {
                    Text("\(settings.brightness) / 15")
                        .monospacedDigit()
                        .frame(minWidth: 74, alignment: .trailing)
                }
            }
        }
    }

    private var idleBrightnessRow: some View {
        SettingsRow(
            title: "Idle Brightness",
            description: "Brightness used after the mouse stops moving."
        ) {
            if let settings = store.mouseSettings {
                Stepper(
                    value: Binding(
                        get: { settings.idleBrightness },
                        set: { value in store.mutate { $0.setIdleBrightness(value) } }
                    ),
                    in: 0...15
                ) {
                    Text("\(settings.idleBrightness) / 15")
                        .monospacedDigit()
                        .frame(minWidth: 74, alignment: .trailing)
                }
            }
        }
    }

    private var idleTimeoutRow: some View {
        SettingsRow(
            title: "Idle Timeout",
            description: "Seconds before idle brightness takes over."
        ) {
            if let settings = store.mouseSettings {
                Stepper(
                    value: Binding(
                        get: { settings.idleTimeoutSeconds },
                        set: { value in store.mutate { $0.setIdleTimeoutSeconds(value) } }
                    ),
                    in: 0...3600,
                    step: 5
                ) {
                    Text(formatDuration(settings.idleTimeoutSeconds))
                        .frame(minWidth: 74, alignment: .trailing)
                }
            }
        }
    }

    // MARK: - Buttons

    private var buttonRows: some View {
        ForEach(store.mouseSettings?.buttons ?? []) { button in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(button.label)
                        .font(.body)
                    Text("HID code \(button.function)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }

                Spacer()

                Text(button.isFactoryDefault ? "Default" : "Remapped")
                    .font(.caption)
                    .foregroundColor(button.isFactoryDefault ? .secondary : .accentColor)
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

    private func formatDuration(_ seconds: Int) -> String {
        guard seconds > 0 else { return "Off" }
        if seconds % 60 == 0 && seconds >= 60 {
            let minutes = seconds / 60
            return "\(minutes) min"
        }
        return "\(seconds) sec"
    }
}

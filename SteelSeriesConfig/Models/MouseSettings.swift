import Foundation

/// A mouse button as stored in `settings.button_mappings.buttons`.
///
/// `function` is the button's HID code, not an action id: `1…5` are B1…B5, `49`/`50`
/// are scroll up/down, `48` is the sixth physical button on six-button mice.
/// `key_codes` is a four-slot HID remap; all zeros means "factory default action".
/// Remapping is intentionally not exposed yet — the action-code table has not been
/// extracted, and guessing would silently rebind someone's mouse.
struct MouseButton: Identifiable, Equatable, Sendable {
    let function: Int
    let keyCodes: [Int]

    var id: Int { function }

    /// Physical position label. Unknown codes fall back to a numeric label rather
    /// than being hidden.
    var label: String {
        switch function {
        case 1: return "Left click"
        case 2: return "Right click"
        case 3: return "Middle click"
        case 4: return "Back"
        case 5: return "Forward"
        case 48: return "Button 6"
        case 49: return "Scroll up"
        case 50: return "Scroll down"
        default: return "Button \(function)"
        }
    }

    var isFactoryDefault: Bool { keyCodes.allSatisfy { $0 == 0 } }
}

/// Typed, editable view over the free-form `settings` document for a mouse.
///
/// Only keys whose semantics were verified against the GG client's own renderer are
/// exposed; everything else stays untouched inside `json`. Conversion constants below
/// are copied from the client, not guessed:
///
/// - CPI: webpack module `28352` maps `resolution_i * 50` to display CPI, across the
///   allowed range 50…18000 in steps of 50.
/// - Polling: `polling_rate.val` → `3 = 125 Hz, 2 = 250 Hz, 1 = 500 Hz, 0 = 1000 Hz`.
struct MouseSettings: Equatable, Sendable {
    var json: [String: AnyJSONValue]

    /// Engine raw unit → displayed CPI. Verified from the GG client.
    static let cpiScale = 50
    static let cpiStep = 50
    static let cpiMinimum = 50
    static let cpiMaximum = 18_000
    static let maxCPILevels = 5

    init(json: [String: AnyJSONValue]) { self.json = json }

    /// - Throws: if the document is not a JSON object. Callers must treat a throw as
    ///   "do not offer editing", never as "start from an empty document".
    init(parsing raw: String) throws {
        let value = try AnyJSONValue.parse(raw)
        guard let object = value.objectValue, !object.isEmpty else {
            throw MouseSettingsError.notAnObject
        }
        json = object
    }

    enum MouseSettingsError: Error, LocalizedError {
        case notAnObject
        var errorDescription: String? {
            switch self {
            case .notAnObject: return "Settings document is not a JSON object."
            }
        }
    }

    // MARK: - Reading

    private func value(_ path: [String]) -> AnyJSONValue? {
        var current: AnyJSONValue = .object(json)
        for key in path {
            guard let object = current.objectValue, let next = object[key] else { return nil }
            current = next
        }
        return current
    }

    func int(_ path: String..., orElse: Int = 0) -> Int {
        value(path)?.intValue ?? orElse
    }

    func bool(_ path: String..., orElse: Bool = false) -> Bool {
        value(path)?.boolValue ?? orElse
    }

    // MARK: CPI

    /// Number of active CPI steps, as stored (1…5).
    var cpiLevelCount: Int { int("batch_resolution", "num_cpi_levels", orElse: 1) }

    /// Index of the active step, zero-based as stored.
    var activeCPILevelIndex: Int { int("batch_resolution", "active_level_index") }

    /// Displayed CPI steps, in engine units already converted to real CPI.
    var cpiLevels: [Int] {
        (1...MouseSettings.maxCPILevels).map { rawCPI(step: $0) * MouseSettings.cpiScale }
    }

    /// Active step in real CPI.
    var activeCPI: Int {
        let index = min(max(activeCPILevelIndex, 0), MouseSettings.maxCPILevels - 1)
        return cpiLevels.indices.contains(index) ? cpiLevels[index] : 0
    }

    func rawCPI(step: Int) -> Int { int("batch_resolution", "resolution_\(step)") }

    /// Replace the whole CPI ladder. Input is real CPI and is clamped to the range the
    /// GG client offers, then divided back into engine units.
    mutating func setCPILevels(_ levels: [Int], activeIndex: Int) {
        let cleaned = levels
            .map { max(MouseSettings.cpiMinimum, min(MouseSettings.cpiMaximum, $0)) }
            .map { $0 / MouseSettings.cpiScale * MouseSettings.cpiScale }
        let count = min(max(cleaned.count, 1), MouseSettings.maxCPILevels)
        let active = min(max(activeIndex, 0), count - 1)

        setInt(count, "batch_resolution", "num_cpi_levels")
        setInt(active, "batch_resolution", "active_level_index")
        for step in 1...MouseSettings.maxCPILevels {
            let value = step <= cleaned.count ? cleaned[step - 1] / MouseSettings.cpiScale : rawCPI(step: step)
            setInt(value, "batch_resolution", "resolution_\(step)")
        }
    }

    /// Replace the CPI of one step (zero-based index) with a real-CPI value.
    mutating func setCPILevelAt(_ index: Int, cpi: Int) {
        guard (0..<MouseSettings.maxCPILevels).contains(index) else { return }
        setInt(Self.quantise(cpi) / MouseSettings.cpiScale, "batch_resolution", "resolution_\(index + 1)")
    }

    /// Change how many steps are offered (1…5), keeping the active step valid.
    mutating func setCPILevelCount(_ count: Int) {
        let clamped = min(max(count, 1), MouseSettings.maxCPILevels)
        setInt(clamped, "batch_resolution", "num_cpi_levels")
        if activeCPILevelIndex > clamped - 1 {
            setInt(clamped - 1, "batch_resolution", "active_level_index")
        }
    }

    /// Select which stored step is active (zero-based, clamped to the ladder length).
    mutating func setActiveCPILevelIndex(_ index: Int) {
        let count = min(max(cpiLevelCount, 1), MouseSettings.maxCPILevels)
        setInt(min(max(index, 0), count - 1), "batch_resolution", "active_level_index")
    }

    /// Overwrite the CPI of the currently active step. Input is real CPI and is
    /// quantised to the 50-CPI grid the GG client offers.
    mutating func setActiveCPIValue(_ cpi: Int) {
        let index = min(max(activeCPILevelIndex, 0), MouseSettings.maxCPILevels - 1)
        let quantised = quantise(cpi)
        setInt(quantised / MouseSettings.cpiScale, "batch_resolution", "resolution_\(index + 1)")
    }

    static let pollingRateOptions = [1000, 500, 250, 125]

    /// One-tap CPI presets offered in the menu bar, mirroring the reference app's mode
    /// circles. All four sit exactly on the 50-CPI grid, so they survive the trip into
    /// engine units without rounding.
    static let cpiPresets = [1000, 2000, 5000, 6000]

    /// Snap to the 50-CPI grid inside the client's allowed range, rounding to the
    /// nearest step so that typing 1234 lands on 1250 rather than being quietly
    /// rounded down to 1200.
    static func quantise(_ cpi: Int) -> Int {
        let clamped = max(cpiMinimum, min(cpiMaximum, cpi))
        return (clamped + cpiScale / 2) / cpiScale * cpiScale
    }

    private func quantise(_ cpi: Int) -> Int { Self.quantise(cpi) }

    // MARK: Polling rate

    /// Stored code → Hz, matching the GG client's switch statement.
    static func hz(forPollingCode code: Int) -> Int {
        switch code {
        case 3: return 125
        case 2: return 250
        case 1: return 500
        default: return 1000
        }
    }

    static func pollingCode(forHz hz: Int) -> Int {
        switch hz {
        case 125: return 3
        case 250: return 2
        case 500: return 1
        default: return 0
        }
    }

    var pollingRateHz: Int { MouseSettings.hz(forPollingCode: int("polling_rate", "val")) }

    mutating func setPollingRateHz(_ hz: Int) {
        setInt(MouseSettings.pollingCode(forHz: hz), "polling_rate", "val")
    }

    // MARK: Sensor toggles

    var angleSnapping: Bool { int("angle_snapping", "level") != 0 }
    mutating func setAngleSnapping(_ on: Bool) { setInt(on ? 1 : 0, "angle_snapping", "level") }

    var exactAim: Bool { int("exact_aim", "level") != 0 }
    mutating func setExactAim(_ on: Bool) { setInt(on ? 1 : 0, "exact_aim", "level") }

    var exactAccel: Bool { int("exact_accel", "level") != 0 }
    mutating func setExactAccel(_ on: Bool) { setInt(on ? 1 : 0, "exact_accel", "level") }

    var lowPowerGamingMode: Bool { int("low_power_gaming_mode_sensor", "lpgm_mode_on") != 0 }
    mutating func setLowPowerGamingMode(_ on: Bool) {
        setInt(on ? 1 : 0, "low_power_gaming_mode_sensor", "lpgm_mode_on")
    }

    /// Idle timeout in seconds, stored in milliseconds.
    var powerSaveSeconds: Int { int("power_saving_timeout", "timeout", orElse: 300_000) / 1000 }
    mutating func setPowerSaveSeconds(_ seconds: Int) {
        setInt(max(0, seconds) * 1000, "power_saving_timeout", "timeout")
    }

    // MARK: Illumination

    var brightness: Int { int("lighting_settings", "brightness", orElse: 15) }
    mutating func setBrightness(_ value: Int) { setInt(clamped(value, 0, 15), "lighting_settings", "brightness") }

    var idleBrightness: Int { int("lighting_settings", "idle_brightness", orElse: 1) }
    mutating func setIdleBrightness(_ value: Int) {
        setInt(clamped(value, 0, 15), "lighting_settings", "idle_brightness")
    }

    /// Idle timeout in seconds; stored in milliseconds.
    var idleTimeoutSeconds: Int { int("lighting_settings", "idle_timeout", orElse: 30_000) / 1000 }
    mutating func setIdleTimeoutSeconds(_ seconds: Int) {
        setInt(max(0, seconds) * 1000, "lighting_settings", "idle_timeout")
    }

    /// Stored as `0`/`1`, not JSON booleans — kept as integers so a write does not
    /// silently change the value's type in the engine's document.
    var smartLighting: Bool { int("lighting_settings", "smart_lighting") != 0 }
    mutating func setSmartLighting(_ on: Bool) {
        setInt(on ? 1 : 0, "lighting_settings", "smart_lighting")
    }

    var defaultLightingEnabled: Bool { int("default_lighting_enabled", "default_lighting_enabled") != 0 }
    mutating func setDefaultLightingEnabled(_ on: Bool) {
        setInt(on ? 1 : 0, "default_lighting_enabled", "default_lighting_enabled")
    }

    var reactiveLightingEnabled: Bool { int("reactive_lighting", "enable_random_color") != 0 }
    mutating func setReactiveLightingEnabled(_ on: Bool) {
        setInt(on ? 1 : 0, "reactive_lighting", "enable_random_color")
    }

    /// Reactive colour as stored, in 0…255 per channel.
    var reactiveColor: (red: Int, green: Int, blue: Int) {
        (
            int("reactive_lighting", "color", "r", orElse: 255),
            int("reactive_lighting", "color", "g", orElse: 255),
            int("reactive_lighting", "color", "b", orElse: 255)
        )
    }

    mutating func setReactiveColor(red: Int, green: Int, blue: Int) {
        setInt(clamped(red, 0, 255), "reactive_lighting", "color", "r")
        setInt(clamped(green, 0, 255), "reactive_lighting", "color", "g")
        setInt(clamped(blue, 0, 255), "reactive_lighting", "color", "b")
    }

    // MARK: Buttons

    var buttons: [MouseButton] {
        guard let array = value(["button_mappings", "buttons"])?.arrayValue else { return [] }
        return array.compactMap { entry in
            guard let object = entry.objectValue,
                  let function = object["function"]?.intValue else { return nil }
            let codes = (object["key_codes"]?.arrayValue ?? []).compactMap { $0.intValue }
            return MouseButton(function: function, keyCodes: codes)
        }
    }

    var hasButtonMappings: Bool { value(["button_mappings"]) != nil }

    // MARK: - Writing

    private mutating func setInt(_ number: Int, _ path: String...) {
        set(.int(number), path)
    }

    /// Writes `newValue` at `path`, creating intermediate objects as needed and
    /// preserving every sibling key at each level of the chain.
    private mutating func set(_ newValue: AnyJSONValue, _ path: [String]) {
        guard !path.isEmpty else { return }
        json = Self.inserting(newValue, at: ArraySlice(path), into: json)
    }

    private static func inserting(
        _ newValue: AnyJSONValue,
        at path: ArraySlice<String>,
        into dictionary: [String: AnyJSONValue]
    ) -> [String: AnyJSONValue] {
        guard let head = path.first else { return dictionary }
        var result = dictionary
        if path.count == 1 {
            result[head] = newValue
            return result
        }
        var child = (result[head]?.objectValue) ?? [:]
        child = inserting(newValue, at: path.dropFirst(), into: child)
        result[head] = .object(child)
        return result
    }

    private func clamped(_ value: Int, _ lower: Int, _ upper: Int) -> Int {
        min(max(value, lower), upper)
    }

    // MARK: - Serialisation

    /// Serialise for `PUT`. Throws if the document would not round-trip as an object.
    func encodedString() throws -> String {
        try AnyJSONValue.object(json).compactString()
    }

    /// Serialise for `POST configuration/liveDeploy`.
    ///
    /// The GG client deletes every top-level key whose document carries a truthy
    /// `no_live_deploy` before live-deploying, and this does the same. For a mouse that
    /// key is `button_mappings`, and live-applying a button map is how a button gets
    /// rebound with no confirmation — precisely the write this app refuses to make.
    func encodedStringForLiveDeploy() throws -> String {
        let deployable = json.filter { _, value in
            value.objectValue?["no_live_deploy"]?.boolValue != true
        }
        return try AnyJSONValue.object(deployable).compactString()
    }

    /// Top-level keys a live deploy would drop — the ones carrying a truthy
    /// `no_live_deploy`.
    ///
    /// Exposed so a live deploy can verify afterwards that the engine *merged* the
    /// partial document rather than replacing the stored revision with it. If it
    /// replaced, those keys are gone from the engine's copy and have to be put back.
    static func livePreviewExcludedKeys(in raw: String) -> [String] {
        guard let object = (try? AnyJSONValue.parse(raw))?.objectValue else { return [] }
        return object
            .compactMap { key, value in
                value.objectValue?["no_live_deploy"]?.boolValue == true ? key : nil
            }
            .sorted()
    }
}

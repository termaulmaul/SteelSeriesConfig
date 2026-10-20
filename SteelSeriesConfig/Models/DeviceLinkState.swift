import Foundation

/// Wireless link state of the selected device.
///
/// `/devices` cannot answer this for a wireless mouse: its `connected` flag only says
/// the receiver is attached, not that the mouse is talking to it. The real link state
/// comes from the GG client's own `rf_status` device command, whose mode/status pairs
/// are (both tables copied from the client's renderer, not guessed):
///
/// | `rf_mode` | `rf_status` | meaning              |
/// | --------- | ----------- | -------------------- |
/// | 4         | 1           | link, ready          |
/// | 16        | 2           | wired, powered on    |
/// | 17        | 2           | wired, powered off   |
/// | 1         | any         | shut down            |
/// | 2         | any         | pairing / linking    |
///
/// With `rfModeToText` = `1: shutdown, 2: pairing, 4: link, 16: wiredAndOn,
/// 17: wiredAndOff` and `rfStatusToText` = `1: ready, 2: lost, 4: busy, 8: error`.
///
/// An empty `command_data` means the device did not answer the query, which has two
/// causes that look nothing alike on screen:
///
/// - **off, asleep, or out of range** — the mouse really is gone. `/devices` will say
///   `connected: 0` as well;
/// - **a healthy Bluetooth connection** — `rf_status` is a 2.4 GHz dongle concept, so a
///   mouse paired over Bluetooth answers with nothing at all while `/devices` reports
///   `connected: 1`. Observed live: `connected_product_id` pointed at
///   `aerox_3_wireless_bluetooth`, and both `rf_status` and `charge_status` came back
///   with an empty `command_data`.
///
/// Both read as ``offline`` here, and `ConfigurationStore.displayPhase` promotes the
/// second one back to ``ready`` using `/devices`. That is not a guess about what GG
/// does: the client's own `updateDeviceStatus` is guarded by `if (null != i)`, so on a
/// Bluetooth mouse it simply never paints a status or a battery icon at all.
enum LinkPhase: Equatable, Sendable {
    /// Nothing has been polled yet.
    case unknown
    /// The device did not answer. Off, asleep, or out of range.
    case offline
    /// Negotiating the link.
    case connecting
    /// Link is up and the device is reporting.
    case ready
    /// Running over a cable, sensor live.
    case wired
    /// Cabled but powered down (charging, or switched off at the mouse).
    case wiredIdle
    /// The link dropped mid-session without the device powering down.
    case linkLost

    /// True when the device is actually talking to us — the gate for offering edits.
    var isUsable: Bool {
        self == .ready || self == .wired
    }

    /// True while the state is expected to change on its own, which is when a spinner
    /// communicates more than a static dot does.
    var isTransitional: Bool {
        self == .connecting || self == .unknown
    }

    var label: String {
        switch self {
        case .unknown: return "Checking…"
        case .offline: return "Disconnected"
        case .connecting: return "Connecting…"
        case .ready: return "Connected"
        case .wired: return "Wired"
        case .wiredIdle: return "Cable connected · device off"
        case .linkLost: return "Link lost"
        }
    }

    /// Longer, action-oriented sentence for the panel body when the device is not
    /// usable.
    var recoveryHint: String? {
        switch self {
        case .offline:
            return "Turn the device on, or click its receiver back in."
        case .connecting:
            return "Waiting for the device to finish pairing."
        case .wiredIdle:
            return "The mouse is powered down. Move it or switch it on."
        case .linkLost:
            return "The wireless link dropped. Switch the mouse off and on."
        case .ready, .wired, .unknown:
            return nil
        }
    }

    /// Build from a parsed `rf_status` command payload (the whole `command_data`
    /// document, key included). Returns `nil` when the device answered with nothing,
    /// which callers should read as ``offline`` rather than as an error.
    init(rfPayload: AnyJSONValue) {
        guard let rf = rfPayload.objectValue?["rf_status"]?.objectValue else {
            self = .offline
            return
        }

        let mode = rf["rf_mode"]?.intValue ?? 0
        let status = rf["rf_status"]?.intValue ?? 0

        switch (mode, status) {
        case (4, 1):
            self = .ready
        case (16, 2):
            self = .wired
        case (17, 2):
            self = .wiredIdle
        case (2, _):
            self = .connecting
        default:
            // GG distinguishes "lost but present" (warn, wait for a wake) from
            // "shut down" (tell the user to turn it on). The panel shows a hint for
            // both, so one state is enough here.
            self = status == 1 ? .connecting : .linkLost
        }
    }
}

/// Battery state of the selected device, normalised to a percentage.
///
/// The engine reports `charge_status` in two different shapes depending on the device
/// family, and both exist in the GG client's renderer:
///
/// - **level-code family** — what this app's mouse actually uses. `battery_level` is a
///   coarse code (`0, 1, 2, 4` — there is no `3`) and `charge_mode` is
///   `1 = remaining, 2 = charging, 4 = charged, 8 = error`. Copied from the module the
///   mouse's own device card imports (`chargeModeToClass`, `batteryLevelToClass`).
/// - **percentage family** — `battery_level` is 0…100 and `charge_mode` is
///   `0 = remaining, 1 = charging, 2 = charged`. Used by the card layout that drives
///   `batteryLevelToClass` through its ≤10 / ≤30 / ≤50 / ≤100 thresholds.
///
/// The two give mode `2` *opposite* meanings, which is why they are told apart by range
/// rather than by folding the tables together.
///
/// They are told apart by range: a percentage can exceed 4, a level code cannot. The
/// one reading that can be wrong is a genuine 0…4% battery on a percentage-family
/// device, which would be read as the highest code (100%). A battery that flat is
/// already an emergency, so the normalised value stays useful either way — but it is
/// a known ceiling, recorded in the README's Limitations.
struct BatteryStatus: Equatable, Sendable {

    /// Normalised charge, 0…100.
    let percent: Int
    let isCharging: Bool
    let isCharged: Bool

    /// Charge at or below this is flagged low.
    ///
    /// Not lifted from GG — the client has no red state to copy. Its battery indicator
    /// is a set of sprite images whose widths differ per level (`iconBatteryEmpty`
    /// 0 px, `iconBatteryDepleted` 6 px, `iconBatteryUsed` 10 px,
    /// `iconBatteryFull` 14 px), so there is no threshold and no colour to match in
    /// the stylesheet.
    ///
    /// 25 is chosen for the reason GG *does* encode: on the mouse's coarse level-code
    /// scale it is the second-lowest code, the one the client labels
    /// `iconBatteryDepleted`. Below it there is only "empty", and above it there is
    /// half a tank — flagging that as an emergency would cry wolf.
    static let lowThreshold = 25

    var isLow: Bool { !isCharging && percent <= Self.lowThreshold }

    var label: String { "\(percent)%" }

    /// Short word for the charge state, or `nil` when the battery is merely discharging
    /// — the percentage already says that, and a permanent "Discharging" tag would be
    /// noise on the line the connection status also lives on.
    var stateLabel: String? {
        if isCharged { return "Charged" }
        if isCharging { return "Charging" }
        if isLow { return "Low" }
        return nil
    }

    /// Symbol for the charge state, matching the percentage where it can.
    ///
    /// The bolt variants are reserved for a cable being attached, because that is the
    /// only thing they add over the plain battery symbol: that the number is rising.
    var symbolName: String {
        if isCharged { return "battery.100.bolt" }
        if isCharging { return "battery.100.bolt" }
        switch percent {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }

    /// Parse a `charge_status` command payload. Returns `nil` when the device did not
    /// report a level — treated as "unknown", never as "empty".
    init?(payload: AnyJSONValue) {
        guard let object = payload.objectValue?["charge_status"]?.objectValue,
              let raw = object["battery_level"]?.intValue
        else { return nil }

        let mode = object["charge_mode"]?.intValue ?? 0

        if raw <= 4 {
            percent = Self.percent(forLevelCode: raw)
            isCharging = mode == 2
            isCharged = mode == 4
        } else {
            percent = min(max(raw, 0), 100)
            isCharging = mode == 1
            isCharged = mode == 2
        }
    }

    init(percent: Int, isCharging: Bool, isCharged: Bool) {
        self.percent = min(max(percent, 0), 100)
        self.isCharging = isCharging
        self.isCharged = isCharged
    }

    /// Level code → percentage, following the client's own table:
    /// `batteryLevelToClass` = `0 empty, 1 depleted, 2 used, 4 full`, with the other
    /// family's `batteryLevelToText` filling in `3 → 75`. Anything outside 0…4 is not a
    /// code at all and cannot be interpreted; 50 is returned so the badge stays in a
    /// plausible range instead of claiming the battery is flat or full.
    static func percent(forLevelCode code: Int) -> Int {
        switch code {
        case 0: return 0
        case 1: return 25
        case 2: return 50
        case 3: return 75
        case 4: return 100
        default: return 50
        }
    }
}

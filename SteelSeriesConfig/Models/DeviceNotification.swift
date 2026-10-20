import SwiftUI

/// One floating notification, as data.
///
/// Kept a plain value rather than a view so the *decision* to notify — which lives in
/// ``DeviceNotificationPolicy`` and is unit-tested — has nothing to do with AppKit or
/// SwiftUI. The panel layer renders whatever value it is handed.
struct DeviceNotification: Identifiable, Equatable, Sendable {

    enum Kind: Equatable, Sendable {
        case connected
        case disconnected
        /// Charge crossed one of the low-step thresholds.
        case batteryLow
        /// A charge just completed.
        case batteryFull

        var symbolName: String {
            switch self {
            case .connected: return "bolt.horizontal.circle.fill"
            case .disconnected: return "bolt.slash.fill"
            case .batteryLow: return "battery.25"
            case .batteryFull: return "battery.100.bolt"
            }
        }

        var tint: Color {
            switch self {
            case .connected: return .green
            case .disconnected: return .orange
            case .batteryLow: return .red
            case .batteryFull: return .green
            }
        }
    }

    let id = UUID()
    let kind: Kind
    /// Device name as the menu bar header shows it.
    let deviceName: String
    /// Bundled artwork name, or `nil` to fall back to a symbol.
    let imageName: String?
    /// One supporting line — the link label, or the battery state.
    let detail: String
    /// Charge 0…1 for the ring gauge, or `nil` when the event has no battery meaning.
    let batteryProgress: Double?
}

/// Decides *when* a notification is warranted, given the state before and after a poll.
///
/// Pure and free of any I/O, so the whole rule set is testable without a mouse: the
/// interesting cases (a first sighting is not a reconnection, a battery that is already
/// low must not re-announce itself every poll) are exactly the ones that are awkward to
/// reproduce by plugging hardware in and out.
enum DeviceNotificationPolicy {

    /// Low thresholds, highest first. Crossing one downward raises a notification once.
    ///
    /// The ladder is the reference app's `[20, 10, 5]`, stepped down rather than
    /// compared absolutely: a level sitting at 18 % must not notify on every poll, only
    /// when it falls *past* a step. 25 — this app's ``BatteryStatus/lowThreshold`` — is
    /// deliberately not a step: it is the "flag it in the UI" line, and a warning toast
    /// there would fire while the badge has barely changed, crying wolf before the
    /// battery is actually a problem.
    static let batterySteps = [20, 10, 5]

    /// The event, if any, that the transition `previous → current` deserves.
    ///
    /// - `previous == nil` is the first poll after launch. A link that is already up is
    ///   not news, so nothing is raised — but a battery that is *already* below a step
    ///   is, because the user would otherwise get no warning at all for a mouse that was
    ///   low before the app started.
    static func event(
        previousPhase: LinkPhase?,
        phase: LinkPhase,
        previousBattery: BatteryStatus?,
        battery: BatteryStatus?
    ) -> DeviceNotification.Kind? {
        if let link = linkEvent(previous: previousPhase, current: phase) { return link }
        return batteryEvent(previous: previousBattery, current: battery)
    }

    /// Link transitions. Only the crossings the user can act on are announced:
    /// a drop to ``LinkPhase/offline`` or ``LinkPhase/linkLost``, and a return to a
    /// usable phase from a non-usable one. Intermediate states (`connecting`, `unknown`)
    /// are deliberately silent — they are exactly what the header spinner is for, and a
    /// toast for each would turn pairing into a slideshow.
    static func linkEvent(previous: LinkPhase?, current: LinkPhase) -> DeviceNotification.Kind? {
        guard let previous else { return nil }
        if previous == current { return nil }

        // A move *into* a transitional phase is the app re-negotiating the link, not a
        // link the user lost — the header spinner says so, and it usually resolves
        // within the next poll. Toasting "Disconnected" here would cry wolf on every
        // reconnect. Only a *settled* unusable phase counts as a drop.
        if current.isTransitional { return nil }

        let wasUsable = previous.isUsable
        let isUsable = current.isUsable

        if wasUsable && !isUsable {
            return .disconnected
        }
        if !wasUsable && isUsable {
            return .connected
        }
        return nil
    }

    /// Battery transitions. Two events only: falling past a low step, and completing a
    /// charge. Everything else — climbing back up after a charge, a wobble within a
    /// step, an unknown reading appearing — is silent on purpose.
    static func batteryEvent(previous: BatteryStatus?, current: BatteryStatus?) -> DeviceNotification.Kind? {
        guard let current else { return nil }

        // A charge finishing is a single, one-way transition: `isCharged` flips on and
        // stays on until the mouse comes off the cable.
        if current.isCharged, previous?.isCharged != true {
            return .batteryFull
        }

        // A mouse on its cable is not dying, so a low reading while charging is skipped
        // for the same reason ``BatteryStatus/isLow`` skips it.
        guard !current.isCharging else { return nil }

        let crossed = steppedBelow(from: previous?.percent, to: current.percent)
        return crossed ? .batteryLow : nil
    }

    /// Whether `current` crossed under a step that `previous` was still above.
    ///
    /// On a first reading (`previous == nil`) the *lowest* step is used: a fresh reading
    /// that is already flat is worth saying, but one at 18 % is not — the user just
    /// watched it connect, and the badge now shows the level.
    static func steppedBelow(from previousPercent: Int?, to current: Int) -> Bool {
        guard let previousPercent else {
            return current <= (batterySteps.last ?? 0)
        }
        guard !batterySteps.isEmpty else { return false }
        // Walk the steps above `current`; if any of them was still above the old level,
        // the fall crossed it.
        return batterySteps.contains { step in
            previousPercent > step && current <= step
        }
    }
}

import Foundation
import Observation

/// Appearance of the floating notification a device event raises.
///
/// Two shapes, matching the reference app's pair: ``classic`` is the roomier card that
/// carries the device artwork and sits in the top-right corner of the screen, and
/// ``apple`` is the compact one that hangs directly under the menu bar item, where a
/// system accessory alert would appear. Both are the same information — only the
/// footprint and the anchoring differ.
enum NotificationStyle: String, CaseIterable, Identifiable, Sendable {
    case classic
    case apple

    var id: String { rawValue }

    static let `default`: NotificationStyle = .apple

    var title: String {
        switch self {
        case .classic: return "Classic"
        case .apple: return "Apple"
        }
    }

    var summary: String {
        switch self {
        case .classic: return "Larger card in the top-right corner, with the device artwork."
        case .apple: return "Compact card under the menu bar item, like a system accessory alert."
        }
    }
}

/// The device events that can raise a notification, and the per-app switches for them.
///
/// Only the two families the reference app models are here. Everything a notification
/// says is about the *link* or the *battery*, because those are the two facts the
/// device reports on its own; a notification tied to an edit would be a status message,
/// which the popover already shows inline.
///
/// Persisted in `UserDefaults` so the choice survives a relaunch. The type is
/// `@Observable` and held as a shared singleton because the notification centre is not
/// a SwiftUI view and cannot read the environment.
@MainActor
@Observable
final class AppPreferences {

    static let shared = AppPreferences()

    private enum Key {
        static let style = "notifications.style"
        static let connect = "notifications.connect"
        static let battery = "notifications.battery"
    }

    /// How the notification looks. Changing it takes effect on the next one — a
    /// notification already on screen is left alone rather than reshaped underneath the
    /// user's eyes.
    var notificationStyle: NotificationStyle {
        didSet { defaults.set(notificationStyle.rawValue, forKey: Key.style) }
    }

    /// Connected / disconnected transitions.
    var notifyOnConnect: Bool {
        didSet { defaults.set(notifyOnConnect, forKey: Key.connect) }
    }

    /// Battery crossings of the low ladder, and the moment a charge completes.
    var notifyOnBattery: Bool {
        didSet { defaults.set(notifyOnBattery, forKey: Key.battery) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        notificationStyle = defaults.string(forKey: Key.style)
            .flatMap(NotificationStyle.init(rawValue:)) ?? .default

        // Defaults mirror the reference app: both families are on out of the box, since
        // a menu bar app the user never sees otherwise cannot tell them the mouse died.
        notifyOnConnect = defaults.object(forKey: Key.connect) as? Bool ?? true
        notifyOnBattery = defaults.object(forKey: Key.battery) as? Bool ?? true
    }
}

import SwiftUI

/// Animated connection indicator for the header.
///
/// Motion is the whole point: a static dot cannot distinguish "the mouse is talking to
/// us" from "the app has not checked yet". A live link breathes, a link being
/// negotiated spins, and a link that is gone is deliberately still — an animation that
/// keeps running while nothing is connected would be lying.
struct ConnectionDotView: View {

    let phase: LinkPhase

    var body: some View {
        Group {
            if phase.isTransitional {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.7)
            } else {
                Image(systemName: "circle.fill")
                    .font(.system(size: 7))
                    .foregroundColor(color)
                    .symbolEffect(.pulse, options: .repeating, isActive: isLive)
            }
        }
        .frame(width: 12, height: 12)
        // The status text next to this dot already carries the phase verbatim; letting
        // this contribute its own label makes VoiceOver say "Disconnected" twice.
        .accessibilityHidden(true)
    }

    private var isLive: Bool {
        phase == .ready || phase == .wired
    }

    private var color: Color {
        switch phase {
        case .ready: return .green
        case .wired: return .blue
        case .connecting: return .orange
        case .wiredIdle: return .orange
        case .linkLost: return .red
        case .offline: return .secondary
        case .unknown: return .secondary
        }
    }
}

/// Battery level with a symbol that matches the percentage, pulsing when low.
///
/// The pulse is bounded to the low state on purpose: this badge is on screen
/// permanently for anyone using a wireless mouse, and a permanently animated icon in a
/// menu bar popover is a distraction rather than a signal.
struct BatteryBadgeView: View {

    let status: BatteryStatus

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbolName)
                .font(.system(size: 9, weight: .semibold))
                .symbolEffect(.pulse, options: .repeating, isActive: status.isLow)

            Text(status.label)
                .font(.caption2)
                .monospacedDigit()
        }
        .foregroundColor(color)
        .accessibilityLabel("Battery \(status.percent) percent\(chargingSuffix)")
    }

    private var chargingSuffix: String {
        if status.isCharged { return ", charged" }
        if status.isCharging { return ", charging" }
        return status.isLow ? ", low" : ""
    }

    private var symbolName: String {
        if status.isCharging || status.isCharged { return "battery.100.bolt" }
        switch status.percent {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }

    private var color: Color {
        if status.isCharged { return .green }
        if status.isCharging { return .green }
        if status.isLow { return .red }
        return .secondary
    }
}

/// Shown in place of the controls when the device is not reachable.
///
/// The reference app collapses to the header rather than rendering disabled controls,
/// which is the better answer here too: a greyed-out slider invites the user to keep
/// fiddling, while a sentence tells them what to actually do.
struct DisconnectedNoticeView: View {

    let phase: LinkPhase

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: phase == .wiredIdle ? "power" : "bolt.horizontal.circle")
                .font(.system(size: 13))
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(phase.label)
                    .font(.caption.weight(.semibold))

                if let hint = phase.recoveryHint {
                    Text(hint)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

/// Shown when a device is attached but its settings schema is not modelled.
struct ReadOnlyNoticeView: View {

    var body: some View {
        Text("This device is read-only: its settings schema is not modelled yet.")
            .font(.caption2)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
    }
}

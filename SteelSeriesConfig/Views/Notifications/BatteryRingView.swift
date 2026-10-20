import SwiftUI

/// Circular charge gauge with the percentage inside it.
///
/// Chosen over a bar because the notification is small and the ring reads at a glance
/// where a short bar would be ambiguous against the card it sits on — the same reason
/// the reference app uses one. The ring is grey when there is no link, and its colour
/// tracks the level so a low battery is legible without reading the number.
struct BatteryRingView: View {

    enum Size {
        case small
        case medium

        var frameSize: CGFloat {
            switch self {
            case .small: return 26
            case .medium: return 32
            }
        }

        var lineWidth: CGFloat {
            switch self {
            case .small: return 3
            case .medium: return 4
            }
        }

        var fontSize: CGFloat {
            switch self {
            case .small: return 10
            case .medium: return 12
            }
        }
    }

    /// 0…1, or `nil` when the event carries no battery meaning — then only the empty
    /// track is drawn and no number is shown.
    let progress: Double?
    let isConnected: Bool
    let size: Size

    private var color: Color {
        guard isConnected, let progress else { return .secondary }
        if progress <= 0.05 { return .red }
        if progress <= 0.25 { return .orange }
        return .green
    }

    var body: some View {
        ZStack {
            if let progress, progress > 0 {
                Text("\(Int((progress * 100).rounded()))")
                    .font(.system(size: size.fontSize, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(progress <= 0.05 ? .red : .primary)
            }

            Circle()
                .stroke(lineWidth: size.lineWidth)
                .foregroundColor(.gray)
                .opacity(0.15)

            Circle()
                .trim(from: 0, to: min(max(progress ?? 0, 0), 1))
                .stroke(style: StrokeStyle(lineWidth: size.lineWidth, lineCap: .round))
                .foregroundColor(color)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.25), value: progress)
        }
        .frame(width: size.frameSize, height: size.frameSize)
        .accessibilityHidden(true)
    }
}

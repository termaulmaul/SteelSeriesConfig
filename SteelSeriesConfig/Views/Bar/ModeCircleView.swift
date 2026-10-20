import SwiftUI

/// One round choice in a row of mutually exclusive options — polling rates, sensor
/// modes. Geometry matches the reference app's mode circles so the popover reads the
/// same way even though the subject is a mouse rather than headphones.
struct ModeCircleView<Content: View>: View {

    let name: String
    let isActive: Bool
    let onTap: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: BarMetrics.xxs) {
                ZStack {
                    Circle()
                        .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.35))
                        .frame(width: 44, height: 44)

                    content
                        .foregroundColor(isActive ? .white : .primary)
                }
                .frame(width: 60, height: 60)

                Text(name)
                    .font(.caption)
                    .foregroundColor(.primary.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 66)
        }
        .buttonStyle(.plain)
        .disabled(isActive)
    }
}

/// Thin underline bar where a full circle would be too heavy — CPI ladder steps.
struct ModeBarView: View {

    let name: String
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: BarMetrics.xxs) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.4))
                    .frame(height: 6)

                Text(name)
                    .font(.caption)
                    .foregroundColor(isActive ? .primary.opacity(0.9) : .primary.opacity(0.6))
                    .monospacedDigit()
            }
            .frame(minWidth: 34)
        }
        .buttonStyle(.plain)
        .disabled(isActive)
    }
}

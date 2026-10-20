import SwiftUI

/// Shared chrome for a notification card: device artwork, title, one caption line, and
/// the charge ring on the trailing edge.
///
/// Both styles are this same arrangement at different sizes and radii — the difference
/// between "classic" and "apple" is the footprint and where the panel is anchored, not
/// what the card says, so the content lives here once and the two styles only frame it.
struct NotificationCard: View {

    let notification: DeviceNotification
    let iconSize: CGFloat
    let maxWidth: CGFloat
    let cornerRadius: CGFloat
    let spacing: CGFloat

    var body: some View {
        HStack(spacing: spacing) {
            artwork

            VStack(alignment: .leading, spacing: 2) {
                Text(notification.deviceName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(notification.detail)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            BatteryRingView(
                progress: notification.batteryProgress,
                isConnected: notification.kind != .disconnected,
                size: .small
            )
        }
        .frame(maxWidth: maxWidth)
        .padding(10)
        .background(background)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var artwork: some View {
        if let image = DeviceArtwork.image(named: notification.imageName) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: iconSize, height: iconSize)
        } else {
            Image(systemName: notification.kind.symbolName)
                .font(.system(size: iconSize * 0.55, weight: .semibold))
                .foregroundColor(notification.kind.tint)
                .frame(width: iconSize, height: iconSize)
        }
    }

    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return shape
            .fill(.regularMaterial)
            .overlay {
                shape.strokeBorder(.white.opacity(0.12), lineWidth: 1)
            }
    }
}

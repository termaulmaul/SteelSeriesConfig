import SwiftUI

/// Titled block inside the menu bar popover.
///
/// Mirrors the reference app's section rhythm: bold title on the left, the current
/// value on the right in a deliberately non-`.secondary` tone (`.secondary` reads as
/// "disabled" at this size), content underneath with a 4pt horizontal inset.
struct BarSectionView<Content: View>: View {

    let title: LocalizedStringKey
    /// Current value shown opposite the title, or `nil` to omit the row.
    let value: String?

    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                if let value {
                    Text(value)
                        .font(.subheadline)
                        .foregroundColor(.primary.opacity(0.6))
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.15), value: value)
                        .monospacedDigit()
                }
            }

            content
        }
        .padding(.horizontal, 4)
    }
}

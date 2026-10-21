import AppKit
import SwiftUI

/// Visual button-map editor.
///
/// Each mapped input gets a numbered tag parked outside the mouse silhouette and a
/// thin arrow pointing at the physical control. Tags sit clear of one another, which is
/// what keeps the crowded scroll-wheel cluster readable; selecting a row (or a tag)
/// highlights its arrow. Rows are keyed by array position, not function code, because a
/// remap can give two rows the same function.
struct ButtonMappingEditor: View {

    @Environment(ConfigurationStore.self) private var store

    @State private var selectedIndex: Int?

    private var buttons: [MouseButton] {
        store.mouseSettings?.buttons ?? []
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            mouseMap

            VStack(spacing: 4) {
                ForEach(buttons) { button in
                    row(button)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .onAppear {
            if selectedIndex == nil { selectedIndex = buttons.first?.index }
        }
    }

    // MARK: - Artwork

    /// Where the tag for each button sits, as a fraction of the artwork. Positions are
    /// deliberately outside the shell so the labels never cover it.
    private func tagAnchor(for button: MouseButton) -> CGPoint {
        switch button.function {
        case 1: return CGPoint(x: 0.09, y: 0.10)
        case 2: return CGPoint(x: 0.91, y: 0.10)
        case 3: return CGPoint(x: 0.50, y: 0.055)
        case 4: return CGPoint(x: 0.09, y: 0.44)
        case 5: return CGPoint(x: 0.09, y: 0.55)
        case 48: return CGPoint(x: 0.91, y: 0.34)
        case 49: return CGPoint(x: 0.91, y: 0.20)
        case 50: return CGPoint(x: 0.91, y: 0.27)
        default:
            // Unknown action: stack the extra tags down the right flank.
            let slot = Double(button.index % 4)
            return CGPoint(x: 0.91, y: 0.62 + slot * 0.08)
        }
    }

    /// The physical control the tag points at.
    private func target(for button: MouseButton) -> CGPoint {
        switch button.function {
        case 1: return CGPoint(x: 0.34, y: 0.19)
        case 2: return CGPoint(x: 0.66, y: 0.19)
        case 3: return CGPoint(x: 0.50, y: 0.135)
        case 4: return CGPoint(x: 0.155, y: 0.36)
        case 5: return CGPoint(x: 0.155, y: 0.47)
        case 48: return CGPoint(x: 0.50, y: 0.275)
        case 49: return CGPoint(x: 0.54, y: 0.115)
        case 50: return CGPoint(x: 0.46, y: 0.16)
        default:
            return CGPoint(x: 0.72, y: 0.70)
        }
    }

    private var mouseMap: some View {
        ZStack {
            if let image = DeviceArtwork.image(named: "DeviceAerox3") {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.12))
                    .overlay {
                        Image(systemName: "computermouse")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                    }
            }

            GeometryReader { proxy in
                leaderLines(in: proxy.size)

                ForEach(buttons) { button in
                    tag(button)
                        .position(
                            x: proxy.size.width * tagAnchor(for: button).x,
                            y: proxy.size.height * tagAnchor(for: button).y
                        )
                }
            }
        }
        // The artwork is 260 × 469, so this frame avoids letterboxing and keeps the tags
        // on the canvas instead of the transparent margins.
        .frame(width: 166, height: 300)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mouse buttons")
    }

    /// Thin lines from each tag to its control, with a small arrowhead at the control.
    private func leaderLines(in size: CGSize) -> some View {
        Canvas { context, _ in
            for button in buttons {
                let isSelected = button.index == selectedIndex
                let color = isSelected ? Color.accentColor : Color.secondary.opacity(0.55)
                let width: CGFloat = isSelected ? 1.8 : 1

                let anchor = tagAnchor(for: button)
                let target = target(for: button)
                let from = CGPoint(x: size.width * anchor.x, y: size.height * anchor.y)
                let to = CGPoint(x: size.width * target.x, y: size.height * target.y)

                let dx = to.x - from.x
                let dy = to.y - from.y
                let length = max(1, sqrt(dx * dx + dy * dy))
                let start = CGPoint(x: from.x + dx / length * 10, y: from.y + dy / length * 10)

                var line = Path()
                line.move(to: start)
                line.addLine(to: to)
                context.stroke(line, with: .color(color), lineWidth: width)

                let angle = atan2(dy, dx)
                let head: CGFloat = 5
                let wing: CGFloat = 0.45
                var arrow = Path()
                arrow.move(to: to)
                arrow.addLine(to: CGPoint(
                    x: to.x - head * cos(angle - wing),
                    y: to.y - head * sin(angle - wing)
                ))
                arrow.move(to: to)
                arrow.addLine(to: CGPoint(
                    x: to.x - head * cos(angle + wing),
                    y: to.y - head * sin(angle + wing)
                ))
                context.stroke(arrow, with: .color(color), lineWidth: width)
            }
        }
        .allowsHitTesting(false)
    }

    private func tag(_ button: MouseButton) -> some View {
        let isSelected = button.index == selectedIndex

        return Text("\(button.index + 1)")
            .font(.caption2.monospacedDigit().weight(.semibold))
            .foregroundColor(isSelected ? .white : .primary)
            .frame(width: 17, height: 17)
            .background {
                Circle()
                    .fill(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
            }
            .overlay {
                Circle()
                    .strokeBorder(isSelected ? Color.white : Color.secondary.opacity(0.7), lineWidth: 1.5)
            }
            .contentShape(Circle())
            .onTapGesture { selectedIndex = button.index }
            .help(button.label)
            .accessibilityIdentifier("buttons.zone.\(button.index)")
            .accessibilityLabel("\(button.label), button \(button.index + 1)")
            .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: - Rows

    private func row(_ button: MouseButton) -> some View {
        let isSelected = button.index == selectedIndex

        return HStack(spacing: 8) {
            Text("\(button.index + 1)")
                .font(.caption2.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 16, alignment: .trailing)

            Text(button.label)
                .font(.callout)
                .lineLimit(1)

            Spacer(minLength: 6)

            Picker("", selection: actionBinding(button)) {
                ForEach(MouseSettings.buttonFunctions) { option in
                    Text(option.label).tag(option.code)
                }
                // Keep the current code selectable even if it is outside the catalog,
                // so opening the window never silently rewrites an unmodelled action.
                if !MouseSettings.buttonFunctions.contains(where: { $0.code == button.function }) {
                    Text("HID \(button.function)").tag(button.function)
                }
            }
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("buttons.action.\(button.index)")
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { selectedIndex = button.index }
    }

    private func actionBinding(_ button: MouseButton) -> Binding<Int> {
        Binding(
            get: { button.function },
            set: { value in
                selectedIndex = button.index
                store.mutate { $0.setButtonFunction(at: button.index, function: value) }
            }
        )
    }
}

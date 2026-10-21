import SwiftUI

/// Step slider drawn by hand, because the native macOS `Slider` paints a hairline
/// under its track — at popover scale that reads as a stray divider under the CPI
/// block rather than as part of the control.
///
/// Only the pieces the popover actually needs are implemented: a fill, a remainder
/// track, a knob, discrete steps, and the accessibility value/adjust actions.
struct BarSlider: View {

    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    private let knobSize: CGFloat = 18
    private let trackHeight: CGFloat = 4

    private var fraction: CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        let raw = (value - range.lowerBound) / span
        return CGFloat(min(max(raw, 0), 1))
    }

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, knobSize)
            let travel = width - knobSize
            let knobCenterX = knobSize / 2 + travel * fraction

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(trackHeight, knobCenterX), height: trackHeight)

                Circle()
                    .fill(Color.white)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
                    .frame(width: knobSize, height: knobSize)
                    .offset(x: knobCenterX - knobSize / 2)
            }
            .frame(height: knobSize)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard travel > 0 else { return }
                        let raw = (drag.location.x - knobSize / 2) / travel
                        value = snapped(range.lowerBound + Double(raw) * (range.upperBound - range.lowerBound))
                    }
            )
        }
        .frame(height: knobSize)
        // The drawing is custom, so hand VoiceOver and XCUITest a real slider to talk
        // to instead of the untyped view the shapes would otherwise expose.
        .accessibilityRepresentation {
            Slider(value: $value, in: range, step: step)
        }
        .accessibilityValue(Text("\(Int(value))"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = snapped(value + step)
            case .decrement: value = snapped(value - step)
            @unknown default: break
            }
        }
    }

    private func snapped(_ raw: Double) -> Double {
        guard step > 0 else { return min(max(raw, range.lowerBound), range.upperBound) }
        let steps = ((raw - range.lowerBound) / step).rounded()
        return min(max(range.lowerBound + steps * step, range.lowerBound), range.upperBound)
    }
}

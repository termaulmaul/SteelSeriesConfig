import SwiftUI

/// Label + explanation on the left, control on the right.
///
/// Same row shape as the reference app's settings rows: title in body weight, a
/// caption underneath doing the explaining (and wrapping, never truncating), control
/// pinned right.
struct SettingsRow<Control: View>: View {

    let title: String
    let description: String
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            control
                .frame(minWidth: 90, alignment: .trailing)
        }
    }
}

/// Slider with a live monospaced readout — used wherever the value matters more
/// than the gesture (CPI, brightness).
struct ValueSlider<Value: BinaryFloatingPoint>: View where Value.Stride: BinaryFloatingPoint {

    let value: Binding<Value>
    let bounds: ClosedRange<Value>
    let step: Value.Stride
    let format: (Value) -> String

    var body: some View {
        HStack(spacing: 12) {
            Slider(value: value, in: bounds, step: step)
            Text(format(value.wrappedValue))
                .font(.callout)
                .monospacedDigit()
                .frame(minWidth: 64, alignment: .trailing)
        }
    }
}

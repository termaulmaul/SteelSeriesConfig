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

/// Right-aligned numeric field with stepper arrows and an optional trailing unit.
///
/// Every adjustable value in the full settings window is typed as well as stepped:
/// the arrows are a convenience, not the only way in. Input is parsed on commit
/// (Return, or focus loss), clamped to `range`, and snapped to the nearest `step` so a
/// typed value can never land on a code the device does not store — typing `1234` CPI
/// gives `1250`, not `1200`.
struct NumericField: View {

    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    var unit: String = ""
    /// Optional override for how the committed value is shown back in the field.
    var display: ((Int) -> String)?

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 76)
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { commit() }
                }
                .onChange(of: value) { _, _ in
                    if !focused { syncText() }
                }
                .onAppear(perform: syncText)

            if !unit.isEmpty {
                Text(unit)
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            Stepper("", onIncrement: { apply(value + step) }, onDecrement: { apply(value - step) })
                .labelsHidden()
        }
    }

    private func apply(_ candidate: Int) {
        let snapped = Self.snap(candidate, to: step, in: range)
        value = snapped
        text = displayText(snapped)
    }

    private func commit() {
        if let parsed = Int(text.filter(\.isNumber)) {
            apply(parsed)
        } else {
            syncText()
        }
    }

    private func syncText() { text = displayText(value) }

    private func displayText(_ number: Int) -> String { display?(number) ?? String(number) }

    /// Clamp to `range`, then snap to the nearest `step` measured from the lower bound.
    static func snap(_ candidate: Int, to step: Int, in range: ClosedRange<Int>) -> Int {
        let clamped = min(max(candidate, range.lowerBound), range.upperBound)
        guard step > 1 else { return clamped }
        let offset = clamped - range.lowerBound
        let snapped = range.lowerBound + (offset + step / 2) / step * step
        return min(max(snapped, range.lowerBound), range.upperBound)
    }
}

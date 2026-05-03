import SwiftUI

/// Reusable single-axis slider with title, formatted value, and double-tap-to-reset.
/// Haptics are deliberately omitted here — Phase 7 wires UISelectionFeedbackGenerator.
struct AdjustmentSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var defaultValue: Double = 0
    var format: SliderValueFormatter = .signedPercent
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var isEditing: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(format.format(value))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isEditing ? .primary : .secondary)
                    .opacity(isEditing ? 1.0 : 0.7)
                    .animation(.easeInOut(duration: 0.15), value: isEditing)
            }

            Slider(value: $value, in: range, onEditingChanged: { editing in
                isEditing = editing
                onEditingChanged(editing)
            })
            .tint(.blue)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            value = defaultValue
            onEditingChanged(true)
            onEditingChanged(false)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(format.format(value))
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) * 0.05
            switch direction {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            @unknown default: break
            }
        }
    }
}

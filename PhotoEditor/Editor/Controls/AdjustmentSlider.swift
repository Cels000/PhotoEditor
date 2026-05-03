import SwiftUI

/// Reusable single-axis slider with title, formatted value, and double-tap-to-reset.
/// Phase 7: Theme tokens, zero-cross + end-stop haptics, Motion.adaptive animation.
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
                    .font(Theme.Typography.subtitle)
                Spacer()
                Text(format.format(value))
                    .font(Theme.Typography.valueBubble)
                    .foregroundStyle(isEditing ? .primary : .secondary)
                    .opacity(isEditing ? 1.0 : 0.7)
                    .animation(Motion.adaptive(Motion.smooth), value: isEditing)
            }

            Slider(value: $value, in: range, onEditingChanged: { editing in
                isEditing = editing
                onEditingChanged(editing)
            })
            .tint(Theme.Colors.accent)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            value = defaultValue
            Haptic.play(.sliderEnd)
            onEditingChanged(true)
            onEditingChanged(false)
        }
        .onChange(of: value) { old, new in
            // Zero-cross: sign flipped or one side equals 0 while other was non-zero
            let crossedZero = (old < 0 && new >= 0) || (old > 0 && new <= 0) || (old != 0 && new == 0 && defaultValue == 0)
            if crossedZero {
                Haptic.play(.sliderZeroCross)
            }
            // End-stop: clamp at bounds
            let clampedLow  = (new == range.lowerBound) && (old != range.lowerBound)
            let clampedHigh = (new == range.upperBound) && (old != range.upperBound)
            if clampedLow || clampedHigh {
                Haptic.play(.sliderEnd)
            }
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

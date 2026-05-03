import SwiftUI

struct EffectsPanelView: View {
    @Bindable var viewModel: EditorViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Grain
                sectionHeader("Grain")
                percentSlider("Grain Size",      \.grain.size,      defaultValue: 0)
                percentSlider("Grain Intensity", \.grain.intensity, defaultValue: 0)

                // Vignette
                sectionHeader("Vignette")
                signedSlider("Vignette Amount", \.vignette.amount, defaultValue: 0)
                percentSlider("Vignette Feather", \.vignette.feather, defaultValue: 0.5)

                // Sharpen
                sectionHeader("Sharpen")
                percentSlider("Sharpen", \.sharpness, defaultValue: 0)

                // Split Toning
                sectionHeader("Split Toning")
                degreesSlider("Highlight Hue",        \.splitToning.highlightHue,        range: 0...360, defaultValue: 0)
                signedSlider("Highlight Saturation", \.splitToning.highlightSaturation, defaultValue: 0)
                degreesSlider("Shadow Hue",           \.splitToning.shadowHue,           range: 0...360, defaultValue: 0)
                signedSlider("Shadow Saturation",    \.splitToning.shadowSaturation,    defaultValue: 0)
                signedSlider("Balance",              \.splitToning.balance,             defaultValue: 0)
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    @ViewBuilder
    private func percentSlider(_ title: String, _ kp: WritableKeyPath<AdjustmentStack, Double>, defaultValue: Double) -> some View {
        AdjustmentSlider(
            title: title,
            value: Binding(
                get: { viewModel.stack[keyPath: kp] },
                set: { viewModel.stack[keyPath: kp] = $0; viewModel.stackDidChange() }
            ),
            range: 0...1,
            defaultValue: defaultValue,
            format: .percent,
            onEditingChanged: { editing in
                if editing { viewModel.beginInteractiveEdit() }
                else       { viewModel.endInteractiveEdit() }
            }
        )
    }

    @ViewBuilder
    private func signedSlider(_ title: String, _ kp: WritableKeyPath<AdjustmentStack, Double>, defaultValue: Double) -> some View {
        AdjustmentSlider(
            title: title,
            value: Binding(
                get: { viewModel.stack[keyPath: kp] },
                set: { viewModel.stack[keyPath: kp] = $0; viewModel.stackDidChange() }
            ),
            range: -1...1,
            defaultValue: defaultValue,
            format: .signedPercent,
            onEditingChanged: { editing in
                if editing { viewModel.beginInteractiveEdit() }
                else       { viewModel.endInteractiveEdit() }
            }
        )
    }

    @ViewBuilder
    private func degreesSlider(_ title: String, _ kp: WritableKeyPath<AdjustmentStack, Double>, range: ClosedRange<Double>, defaultValue: Double) -> some View {
        AdjustmentSlider(
            title: title,
            value: Binding(
                get: { viewModel.stack[keyPath: kp] },
                set: { viewModel.stack[keyPath: kp] = $0; viewModel.stackDidChange() }
            ),
            range: range,
            defaultValue: defaultValue,
            format: .degrees,
            onEditingChanged: { editing in
                if editing { viewModel.beginInteractiveEdit() }
                else       { viewModel.endInteractiveEdit() }
            }
        )
    }
}

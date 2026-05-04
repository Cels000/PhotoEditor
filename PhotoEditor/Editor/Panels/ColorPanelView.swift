import SwiftUI

struct ColorPanelView: View {
    @Bindable var viewModel: EditorViewModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                slider("Saturation",  \.color.saturation)
                slider("Vibrance",    \.color.vibrance)
                slider("Temperature", \.color.temperature)
                slider("Tint",        \.color.tint)
            }
        }
    }

    @ViewBuilder
    private func slider(_ title: String, _ kp: WritableKeyPath<AdjustmentStack, Double>) -> some View {
        AdjustmentSlider(
            title: title,
            value: Binding(
                get: { viewModel.stack[keyPath: kp] },
                set: { viewModel.stack[keyPath: kp] = $0; viewModel.stackDidChange() }
            ),
            range: -1...1,
            defaultValue: 0,
            format: .signedPercent,
            onEditingChanged: { editing in
                if editing { viewModel.beginInteractiveEdit() }
                else       { viewModel.endInteractiveEdit() }
            }
        )
    }
}

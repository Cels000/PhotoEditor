import SwiftUI

struct LightPanelView: View {
    @Bindable var viewModel: EditorViewModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                slider("Exposure",   \.light.exposure)
                slider("Contrast",   \.light.contrast)
                slider("Highlights", \.light.highlights)
                slider("Shadows",    \.light.shadows)
                slider("Whites",     \.light.whites)
                slider("Blacks",     \.light.blacks)
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

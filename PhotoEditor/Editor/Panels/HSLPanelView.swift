import SwiftUI

struct HSLPanelView: View {
    @Bindable var viewModel: EditorViewModel
    @State private var selected: ChannelKey = .red

    enum ChannelKey: String, CaseIterable, Identifiable {
        case red, orange, yellow, green, aqua, blue, purple, magenta
        var id: String { rawValue }
        var displayName: String { rawValue.capitalized }
        var swatch: Color {
            switch self {
            case .red:     return .red
            case .orange:  return .orange
            case .yellow:  return .yellow
            case .green:   return .green
            case .aqua:    return Color(red: 0, green: 0.8, blue: 0.8)
            case .blue:    return .blue
            case .purple:  return .purple
            case .magenta: return Color(red: 1, green: 0, blue: 1)
            }
        }
    }

    private var channelKP: WritableKeyPath<AdjustmentStack, HSLChannel> {
        switch selected {
        case .red:     return \.hsl.red
        case .orange:  return \.hsl.orange
        case .yellow:  return \.hsl.yellow
        case .green:   return \.hsl.green
        case .aqua:    return \.hsl.aqua
        case .blue:    return \.hsl.blue
        case .purple:  return \.hsl.purple
        case .magenta: return \.hsl.magenta
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            channelPicker
            slider("Hue",        sub: \.hue)
            slider("Saturation", sub: \.saturation)
            slider("Luminance",  sub: \.luminance)
        }
    }

    private var channelPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(ChannelKey.allCases) { key in
                    Button { selected = key } label: {
                        Circle()
                            .fill(key.swatch)
                            .frame(width: 28, height: 28)
                            .overlay(
                                Circle().stroke(selected == key ? Color.primary : .clear, lineWidth: 2)
                            )
                    }
                    .accessibilityLabel("\(key.displayName) channel")
                }
            }
        }
    }

    @ViewBuilder
    private func slider(_ title: String, sub: WritableKeyPath<HSLChannel, Double>) -> some View {
        let chKP = channelKP
        AdjustmentSlider(
            title: title,
            value: Binding(
                get: { viewModel.stack[keyPath: chKP][keyPath: sub] },
                set: {
                    viewModel.stack[keyPath: chKP][keyPath: sub] = $0
                    viewModel.stackDidChange()
                }
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

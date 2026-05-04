import SwiftUI

struct CropPanelView: View {
    @Bindable var viewModel: EditorViewModel
    @State private var selectedPreset: CropAspectPreset = .free

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                aspectPicker
                rotationSlider
                rotateButtons
                flipButtons
                mantisButton
            }
        }
    }

    private var aspectPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ASPECT")
                .font(Theme.Typography.label)
                .tracking(1.5)
                .foregroundStyle(Theme.Colors.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(CropAspectPreset.allCases) { preset in
                        Button {
                            applyPreset(preset)
                        } label: {
                            Text(preset.displayName)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(selectedPreset == preset ? Theme.Colors.canvas : Theme.Colors.text)
                                .padding(.horizontal, Theme.Spacing.md).padding(.vertical, Theme.Spacing.xs)
                                .background(selectedPreset == preset ? Theme.Colors.accent : Theme.Colors.panel)
                                .clipShape(Capsule())
                        }
                        .accessibilityLabel("\(preset.displayName) aspect ratio")
                        .accessibilityAddTraits(selectedPreset == preset ? [.isButton, .isSelected] : .isButton)
                    }
                }
            }
        }
    }

    private var rotationSlider: some View {
        AdjustmentSlider(
            title: "Rotate",
            value: Binding(
                get: { viewModel.stack.crop.rotationDegrees },
                set: { viewModel.stack.crop.rotationDegrees = $0; viewModel.stackDidChange() }
            ),
            range: -45...45,
            defaultValue: 0,
            format: .degrees,
            onEditingChanged: { editing in
                if editing { viewModel.beginInteractiveEdit() }
                else       { viewModel.endInteractiveEdit() }
            }
        )
    }

    private var rotateButtons: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.stack.crop.clockwiseRotations = (viewModel.stack.crop.clockwiseRotations + 3) % 4
                viewModel.stackDidChange()
                viewModel.commitDiscreteChange()
            } label: { Label("90° Left", systemImage: "rotate.left") }
            .accessibilityLabel("Rotate 90 degrees left")
            Button {
                viewModel.stack.crop.clockwiseRotations = (viewModel.stack.crop.clockwiseRotations + 1) % 4
                viewModel.stackDidChange()
                viewModel.commitDiscreteChange()
            } label: { Label("90° Right", systemImage: "rotate.right") }
            .accessibilityLabel("Rotate 90 degrees right")
        }
        .buttonStyle(.bordered)
    }

    private var flipButtons: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.stack.crop.flippedHorizontally.toggle()
                viewModel.stackDidChange()
                viewModel.commitDiscreteChange()
            } label: {
                Label("Flip H", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
            }
            .accessibilityLabel("Flip horizontal")
            Button {
                viewModel.stack.crop.flippedVertically.toggle()
                viewModel.stackDidChange()
                viewModel.commitDiscreteChange()
            } label: {
                Label("Flip V", systemImage: "arrow.up.and.down.righttriangle.up.righttriangle.down")
            }
            .accessibilityLabel("Flip vertical")
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private var mantisButton: some View {
        // Hidden entirely when the SPM dep isn't linked — a perpetually-disabled
        // primary CTA reads as broken. Aspect presets + rotate/flip cover crop
        // needs without Mantis.
        if mantisAvailable {
            Button {
                // Wire to a sheet presentation in 03-10. For now, button stub records intent.
            } label: {
                Label("Open Crop Tool", systemImage: "crop")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func applyPreset(_ preset: CropAspectPreset) {
        selectedPreset = preset
        switch preset {
        case .free, .original:
            viewModel.stack.crop.normalizedRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        default:
            guard let ratio = preset.ratio else { return }
            // Center-fit a normalized rect with the requested W/H ratio inside the unit square.
            if ratio >= 1 {
                let h = 1.0 / Double(ratio)
                viewModel.stack.crop.normalizedRect = CGRect(x: 0, y: (1 - h) / 2, width: 1, height: h)
            } else {
                let w = Double(ratio)
                viewModel.stack.crop.normalizedRect = CGRect(x: (1 - w) / 2, y: 0, width: w, height: 1)
            }
        }
        viewModel.stackDidChange()
        viewModel.commitDiscreteChange()
    }
}

// PhotoEditor/Editor/InstancePickerOverlay.swift
//
// v1 instance overlay: tinted full-canvas tap targets per detected instance,
// stacked above the live preview. Tap toggles include/exclude. Pixel-accurate
// per-instance shapes (drawing each instance's actual mask) is deferred to a
// later polish phase — flagged in the design as out-of-scope visual refinement.

import SwiftUI

struct InstancePickerOverlay: View {
    @Bindable var viewModel: EditorViewModel

    private static let instanceTints: [Color] = [.blue, .pink, .green, .orange, .purple, .yellow]

    var body: some View {
        ZStack {
            if let preview = viewModel.previewImage {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFit()
            } else {
                Rectangle().fill(Theme.Colors.canvas)
            }
            ForEach(0..<viewModel.lastDetectedInstanceCount, id: \.self) { index in
                instanceTapTarget(index: index)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 240)
        .clipped()
    }

    @ViewBuilder
    private func instanceTapTarget(index: Int) -> some View {
        let tint = Self.instanceTints[index % Self.instanceTints.count]
        let included = !(viewModel.document.mask?.excludedInstances.contains(index) ?? false)
        Rectangle()
            .fill(tint.opacity(included ? 0.18 : 0.04))
            .overlay(alignment: .topLeading) {
                Text("Subject \(index + 1)")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(6)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .onTapGesture { viewModel.toggleInstanceExcluded(index) }
            .accessibilityLabel("Subject \(index + 1)")
            .accessibilityValue(included ? "included" : "excluded")
            .accessibilityHint("Double tap to toggle")
    }
}

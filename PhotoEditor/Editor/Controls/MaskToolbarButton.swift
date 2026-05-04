// PhotoEditor/Editor/Controls/MaskToolbarButton.swift
//
// Toolbar entry for the AI subject mask. Visualizes idle / loading / active /
// disabled states. Idle tap kicks off Vision compute; active tap opens the
// refinement sheet via the onTapRefine closure (wired in EditorTabView).

import SwiftUI

struct MaskToolbarButton: View {
    @Bindable var viewModel: EditorViewModel
    var onTapRefine: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Image(systemName: iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(foregroundColor)
                if viewModel.maskComputeInFlight {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Theme.Colors.text)
                }
            }
            .frame(width: 22, height: 22)
        }
        .disabled(disabled)
        .accessibilityLabel(accessibilityLabel)
    }

    private var iconName: String {
        viewModel.document.mask != nil ? "person.fill.viewfinder" : "person.viewfinder"
    }

    private var foregroundColor: Color {
        if viewModel.document.mask != nil { return Theme.Colors.text }
        if disabled { return Theme.Colors.secondary }
        return Theme.Colors.text
    }

    private var disabled: Bool {
        viewModel.importedImage == nil || viewModel.maskComputeInFlight
    }

    private var accessibilityLabel: String {
        viewModel.document.mask != nil ? "Refine subject mask" : "Mask subject"
    }

    private func action() {
        if viewModel.document.mask != nil {
            onTapRefine()
        } else {
            Task { await viewModel.enterMaskMode() }
        }
    }
}

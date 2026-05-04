// PhotoEditor/Editor/Panels/MaskScopeHeaderView.swift
//
// Compact segmented picker shown ABOVE the slider-panel content when the
// document has an active mask. Switches which AdjustmentStack the sliders
// read/write via vm.activeScope. When document.mask is nil, this view
// renders nothing (zero height).

import SwiftUI

struct MaskScopeHeaderView: View {
    @Bindable var viewModel: EditorViewModel

    var body: some View {
        if viewModel.document.mask != nil {
            HStack(spacing: 0) {
                ForEach([MaskScope.subject, .full, .background], id: \.self) { scope in
                    Button {
                        guard viewModel.activeScope != scope else { return }
                        Haptic.play(.panelOpen)
                        viewModel.activeScope = scope
                    } label: {
                        Text(label(for: scope).uppercased())
                            .font(Theme.Typography.label)
                            .tracking(1.5)
                            .foregroundStyle(viewModel.activeScope == scope
                                             ? Theme.Colors.text
                                             : Theme.Colors.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.xs)
                    }
                    .accessibilityAddTraits(viewModel.activeScope == scope ? .isSelected : [])
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.xs)
            .background(Theme.Colors.canvas)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.Colors.separator).frame(height: 0.5)
            }
        }
    }

    private func label(for scope: MaskScope) -> String {
        switch scope {
        case .subject:    return "Subject"
        case .full:       return "Full"
        case .background: return "Background"
        }
    }
}

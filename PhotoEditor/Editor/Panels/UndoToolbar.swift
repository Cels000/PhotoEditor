import SwiftUI

/// Top toolbar with Undo / Redo / Reset All.
struct UndoToolbar: View {
    @Bindable var viewModel: EditorViewModel
    @State private var showResetConfirm = false

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Button {
                Haptic.play(.undoRedo)
                viewModel.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 15, weight: .semibold))
            }
            .disabled(!viewModel.canUndo)
            .accessibilityLabel("Undo")

            Button {
                Haptic.play(.undoRedo)
                viewModel.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 15, weight: .semibold))
            }
            .disabled(!viewModel.canRedo)
            .accessibilityLabel("Redo")

            Spacer()

            // Reset is icon-only and lives quietly on the right; Phase 7 review
            // flagged the previous full-width Label as visual clutter that ate
            // canvas space.
            Button(role: .destructive) {
                showResetConfirm = true
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 15, weight: .semibold))
            }
            .disabled(viewModel.importedImage == nil || viewModel.stack == .identity)
            .accessibilityLabel("Reset all edits")
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, 4)
        .alert("Reset all edits?", isPresented: $showResetConfirm) {
            Button("Reset", role: .destructive) {
                Haptic.play(.recipeApply)
                viewModel.resetAdjustments()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Clears every adjustment in one step. Undo will restore them.")
        }
    }
}

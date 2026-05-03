import SwiftUI

/// Top toolbar with Undo / Redo / Reset All.
struct UndoToolbar: View {
    @Bindable var viewModel: EditorViewModel
    @State private var showResetConfirm = false

    var body: some View {
        HStack(spacing: 16) {
            Button {
                Haptic.play(.undoRedo)
                viewModel.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 18, weight: .semibold))
            }
            .disabled(!viewModel.canUndo)
            .accessibilityLabel("Undo")

            Button {
                Haptic.play(.undoRedo)
                viewModel.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 18, weight: .semibold))
            }
            .disabled(!viewModel.canRedo)
            .accessibilityLabel("Redo")

            Spacer()

            Button(role: .destructive) {
                showResetConfirm = true
            } label: {
                Label("Reset All", systemImage: "arrow.counterclockwise")
                    .font(Theme.Typography.subtitle)
            }
            .disabled(viewModel.importedImage == nil)
            .accessibilityLabel("Reset all edits")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .alert("Reset all edits?", isPresented: $showResetConfirm) {
            Button("Reset", role: .destructive) {
                Haptic.play(.recipeApply)
                viewModel.resetAdjustments()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All current adjustments will be cleared. You can undo this.")
        }
    }
}

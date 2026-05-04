import SwiftUI

/// Recipes tab — saved adjustment stacks. Wraps the existing
/// `RecipesSheetView` (which was originally designed as a modal sheet) so it
/// works as a full tab destination. Tapping a recipe applies it and switches
/// to the EDIT tab.
struct RecipesTabView: View {
    let store: RecipeStore?
    var onApply: (RecipeItem) -> Void

    var body: some View {
        Group {
            if let store {
                RecipesSheetView(
                    store: store,
                    onApply: onApply,
                    onDismiss: nil
                )
            } else {
                VStack {
                    ProgressView()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.Colors.canvas.ignoresSafeArea())
            }
        }
        .toolbarBackground(Theme.Colors.canvas, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

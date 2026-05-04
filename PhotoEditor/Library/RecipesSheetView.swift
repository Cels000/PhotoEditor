// RecipesSheetView.swift
// User-facing recipe management surface.
// - Tap row: apply (calls onApply, closes sheet)
// - Context menu / swipe: Rename, Share, Delete (works on built-in presets too —
//   if a user removes one, it's gone unless they bump the seed key)
// - Sections: "My Recipes" (uncategorized) + one per RecipeCategory.
//   All collapsible, all collapsed by default to keep the surface compact.
// - User-recipe section supports reorder; preset sections do not.
// - Visuals tuned to the app's VSCO-style monochrome palette: pure canvas
//   background, square thumbnails, ALL-CAPS tracked-out section labels, no
//   grouped boxing, no system shadows. Driven entirely by Theme.

import SwiftUI
import UIKit

// Identifiable conformance required for sheet(item:) and ForEach.
// RecipeItem has a UUID `id` property; @Model doesn't auto-conform to Identifiable.
extension RecipeItem: Identifiable {}

struct RecipesSheetView: View {
    let store: RecipeStore
    let onApply: (RecipeItem) -> Void
    /// Optional — `nil` when used as a tab destination (no Done button needed).
    let onDismiss: (() -> Void)?

    @State private var renameTarget: RecipeItem?
    @State private var deleteTarget: RecipeItem?
    @State private var shareURL: URL?
    @State private var errorMessage: String?
    /// Section expansion state — keyed by category, with `"user"` for "My Recipes".
    /// All start collapsed so the sheet is compact on open.
    @State private var expandedSections: Set<String> = []

    var body: some View {
        NavigationStack {
            Group {
                if store.items.isEmpty {
                    emptyState
                } else {
                    sectionList
                }
            }
            .background(Theme.Colors.canvas.ignoresSafeArea())
            .navigationTitle("Recipes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.Colors.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                if let onDismiss {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { onDismiss() }
                            .foregroundStyle(Theme.Colors.text)
                    }
                }
            }
            .sheet(item: $renameTarget) { recipe in
                RecipeNamePromptView(
                    title: "Rename Recipe",
                    initialName: recipe.name,
                    onSubmit: { newName in
                        store.rename(recipe, to: newName)
                        renameTarget = nil
                    },
                    onCancel: { renameTarget = nil }
                )
            }
            .alert(
                "Delete Recipe?",
                isPresented: Binding(
                    get: { deleteTarget != nil },
                    set: { if !$0 { deleteTarget = nil } }
                ),
                presenting: deleteTarget
            ) { recipe in
                Button("Delete", role: .destructive) {
                    store.delete(recipe)
                    deleteTarget = nil
                }
                Button("Cancel", role: .cancel) { deleteTarget = nil }
            } message: { recipe in
                Text("\u{201C}\(recipe.name)\u{201D} will be removed permanently.")
            }
            .sheet(isPresented: Binding(
                get: { shareURL != nil },
                set: { if !$0 { shareURL = nil } }
            )) {
                if let url = shareURL {
                    ShareLink(item: url, preview: SharePreview("Recipe", image: Image(systemName: "wand.and.stars"))) {
                        Label("Share Recipe", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .padding()
                }
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            ), presenting: errorMessage) { _ in
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text($0) }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(Theme.Colors.accent)
            Text("No Recipes Yet").font(Theme.Typography.subtitle)
            Text("Tap the Save Recipe button while editing a photo to capture your current look.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Sectioned list

    /// "My Recipes" — items not matched by the built-in name lookup.
    private var userRecipes: [RecipeItem] {
        store.items.filter { BuiltInPresets.category(forName: $0.name) == nil }
    }

    private func recipes(in category: RecipeCategory) -> [RecipeItem] {
        store.items.filter { BuiltInPresets.category(forName: $0.name) == category }
    }

    private var sectionList: some View {
        List {
            if !userRecipes.isEmpty {
                section(
                    key: "user",
                    title: "My Recipes",
                    count: userRecipes.count
                ) {
                    ForEach(userRecipes, id: \.id) { recipe in
                        recipeRow(recipe)
                    }
                    .onMove(perform: moveUserItems)
                    .onDelete(perform: deleteUserItems)
                }
            }
            ForEach(RecipeCategory.allCases) { category in
                let items = recipes(in: category)
                if !items.isEmpty {
                    section(
                        key: category.rawValue,
                        title: category.displayName,
                        count: items.count
                    ) {
                        ForEach(items, id: \.id) { recipe in
                            recipeRow(recipe)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.canvas)
    }

    @ViewBuilder
    private func section<Content: View>(
        key: String,
        title: String,
        count: Int,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        let isExpanded = expandedSections.contains(key)
        Section {
            if isExpanded {
                content()
            }
        } header: {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    if isExpanded { expandedSections.remove(key) }
                    else { expandedSections.insert(key) }
                }
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(title.uppercased())
                        .font(Theme.Typography.label)
                        .tracking(1.5)
                        .foregroundStyle(Theme.Colors.text)
                    Text("\(count)")
                        .font(Theme.Typography.label)
                        .tracking(1.0)
                        .foregroundStyle(Theme.Colors.secondary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.Colors.secondary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .padding(.vertical, Theme.Spacing.sm)
                .padding(.horizontal, Theme.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Colors.canvas)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Theme.Colors.canvas)
            .textCase(nil)
        }
    }

    @ViewBuilder
    private func recipeRow(_ recipe: RecipeItem) -> some View {
        RecipeRow(recipe: recipe)
            .contentShape(Rectangle())
            .onTapGesture {
                onApply(recipe)
                onDismiss?()
            }
            .listRowBackground(Theme.Colors.canvas)
            .listRowSeparatorTint(Theme.Colors.separator)
            .contextMenu {
                Button { renameTarget = recipe } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Button { shareRecipe(recipe) } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                Button(role: .destructive) { deleteTarget = recipe } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) { deleteTarget = recipe } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }

    // MARK: - Mutations (user section only)

    private func moveUserItems(from source: IndexSet, to destination: Int) {
        var users = userRecipes
        users.move(fromOffsets: source, toOffset: destination)
        // Rebuild the full ordering: presets keep their positions, user items follow.
        let presets = store.items.filter { BuiltInPresets.category(forName: $0.name) != nil }
        store.reorder(users + presets)
    }

    private func deleteUserItems(at offsets: IndexSet) {
        let snapshot = userRecipes
        for index in offsets where index < snapshot.count {
            store.delete(snapshot[index])
        }
    }

    private func shareRecipe(_ recipe: RecipeItem) {
        let doc = ExportedRecipe(
            schemaVersion: ExportedRecipe.currentSchemaVersion,
            name: recipe.name,
            stack: recipe.adjustmentStack,
            thumbnailJPEGBase64: recipe.thumbnailData?.base64EncodedString()
        )
        do {
            shareURL = try RecipeFileIO.writeTempFile(doc)
        } catch {
            errorMessage = "Could not export recipe."
        }
    }
}

private struct RecipeRow: View {
    let recipe: RecipeItem

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            thumbnail
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radii.medium, style: .continuous))
            Text(recipe.name)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.text)
            Spacer()
        }
        .padding(.vertical, Theme.Spacing.xs)
        .padding(.horizontal, Theme.Spacing.lg)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = recipe.thumbnailData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage).resizable().scaledToFill()
        } else {
            // No-thumbnail fallback: flat panel — no colored gradient (keeps
            // the chrome purely monochrome per Theme).
            Theme.Colors.panel
        }
    }
}

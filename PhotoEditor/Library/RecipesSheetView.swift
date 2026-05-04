// RecipesSheetView.swift
// User-facing recipe management surface.
// - Tap row: apply (calls onApply, closes sheet)
// - Context menu: Rename, Share, Delete (works on built-in presets too —
//   if a user removes one, it's gone unless they bump the seed key)
// - Sections: "My Recipes" (uncategorized) + one per RecipeCategory.
//   All collapsible, all collapsed by default to keep the sheet compact.
// - User-recipe section supports reorder; preset sections do not.
// RECIPE-02, RECIPE-03, RECIPE-04, presets seed (BuiltInPresets).

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
    /// Section expansion state — keyed by category, with `nil` for "My Recipes".
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
            .navigationTitle("Recipes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let onDismiss {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { onDismiss() }
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
                .font(.system(size: 44, weight: .semibold))
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

    /// "My Recipes" — items with no category tag.
    private var userRecipes: [RecipeItem] {
        store.items.filter { $0.categoryRaw == nil }
    }

    private func recipes(in category: RecipeCategory) -> [RecipeItem] {
        store.items.filter { $0.categoryRaw == category.rawValue }
    }

    private var sectionList: some View {
        List {
            if !userRecipes.isEmpty {
                disclosure(
                    key: "user",
                    title: "My Recipes",
                    iconSystemName: "person.crop.square",
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
                    disclosure(
                        key: category.rawValue,
                        title: category.displayName,
                        iconSystemName: category.iconSystemName,
                        count: items.count
                    ) {
                        ForEach(items, id: \.id) { recipe in
                            recipeRow(recipe)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func disclosure<Content: View>(
        key: String,
        title: String,
        iconSystemName: String,
        count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { expandedSections.contains(key) },
                set: { isOpen in
                    if isOpen { expandedSections.insert(key) }
                    else { expandedSections.remove(key) }
                }
            )
        ) {
            content()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: iconSystemName)
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(width: 22)
                Text(title).font(.body.weight(.semibold))
                Spacer()
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
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
        let presets = store.items.filter { $0.categoryRaw != nil }
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
        HStack(spacing: 12) {
            thumbnail
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.name).font(.body.weight(.medium))
                Text(recipe.updatedAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = recipe.thumbnailData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage).resizable().scaledToFill()
        } else {
            LinearGradient(
                colors: [Theme.Colors.accent.opacity(0.7), Theme.Colors.accent.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

// RecipesSheetView.swift
// User-facing recipe management surface.
// - Tap row: apply (calls onApply, closes sheet)
// - Context menu: Rename, Share, Delete
// - EditMode toggle: reorder (.onMove) and swipe-to-delete
// - Empty state: prompt to save a recipe
// RECIPE-02, RECIPE-03, RECIPE-04.

import SwiftUI
import UIKit

// Identifiable conformance required for sheet(item:) and ForEach.
// RecipeItem has a UUID `id` property; @Model doesn't auto-conform to Identifiable.
extension RecipeItem: Identifiable {}

struct RecipesSheetView: View {
    let store: RecipeStore
    let onApply: (RecipeItem) -> Void
    let onDismiss: () -> Void

    @State private var editMode: EditMode = .inactive
    @State private var renameTarget: RecipeItem?
    @State private var deleteTarget: RecipeItem?
    @State private var shareURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if store.items.isEmpty {
                    emptyState
                } else {
                    recipeList
                }
            }
            .navigationTitle("Recipes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onDismiss() }
                }
                if !store.items.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        EditButton()
                    }
                }
            }
            .environment(\.editMode, $editMode)
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

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.purple)
            Text("No Recipes Yet").font(.headline)
            Text("Tap the Save Recipe button while editing a photo to capture your current look.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var recipeList: some View {
        List {
            ForEach(store.items, id: \.id) { recipe in
                RecipeRow(recipe: recipe)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard editMode == .inactive else { return }
                        onApply(recipe)
                        onDismiss()
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
            }
            .onMove(perform: moveItems)
            .onDelete(perform: deleteItems)
        }
        .listStyle(.plain)
    }

    private func moveItems(from source: IndexSet, to destination: Int) {
        var newOrder = store.items
        newOrder.move(fromOffsets: source, toOffset: destination)
        store.reorder(newOrder)
    }

    private func deleteItems(at offsets: IndexSet) {
        for index in offsets { store.delete(store.items[index]) }
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
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.name).font(.body.weight(.medium))
                Text(recipe.updatedAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = recipe.thumbnailData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage).resizable().scaledToFill()
        } else {
            LinearGradient(
                colors: [.purple.opacity(0.6), .blue.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

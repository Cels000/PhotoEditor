// EditorPresetPickerView.swift
// Replaces FilterStripView in the editor's "Looks" panel with a categorized
// recipe picker. Each row is a category (MY RECIPES, DEFAULT, COLOR FILM,
// B&W FILM, ERA & CAMERA); cells show a LUT-preview thumbnail (when the
// recipe references a built-in LUT) or a flat panel fallback. Tap to apply
// the full recipe stack via viewModel.applyRecipe; long-press a user-saved
// recipe for rename/delete.
//
// Thumbnail rendering reuses FilterThumbnailCache: only the LUT portion of
// each recipe is previewed (the slider/curve/grain bits aren't applied —
// rendering the full pipeline per cell would be too expensive). Means
// recipes that share a LUT (e.g. several use warmFade) share one thumbnail
// regardless of slider differences. Acceptable trade for v1.

import CoreImage
import SwiftUI
import UIKit

struct EditorPresetPickerView: View {

    @Bindable var viewModel: EditorViewModel

    @State private var thumbnails: [String: UIImage] = [:]
    @State private var thumbnailContext = CIContext(options: [.useSoftwareRenderer: false])
    @State private var thumbnailCache = FilterThumbnailCache()
    @State private var photoID: String = ""

    @State private var renameTarget: RecipeItem?
    @State private var deleteTarget: RecipeItem?

    private var store: RecipeStore? { viewModel.recipeStore }

    private var userRecipes: [RecipeItem] {
        store?.items.filter { BuiltInPresets.category(forName: $0.name) == nil } ?? []
    }

    private func recipes(in category: RecipeCategory) -> [RecipeItem] {
        store?.items.filter { BuiltInPresets.category(forName: $0.name) == category } ?? []
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                if !userRecipes.isEmpty {
                    row(title: "MY RECIPES",
                        items: userRecipes,
                        isUserSection: true)
                }
                ForEach(RecipeCategory.allCases) { category in
                    let items = recipes(in: category)
                    if !items.isEmpty {
                        row(title: category.displayName.uppercased(),
                            items: items,
                            isUserSection: false)
                    }
                }
            }
            .padding(.vertical, Theme.Spacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: importedPhotoIdentity) { await regenerateThumbnails() }
        .sheet(item: $renameTarget) { recipe in
            RecipeNamePromptView(
                title: "Rename Recipe",
                initialName: recipe.name,
                onSubmit: { newName in
                    store?.rename(recipe, to: newName)
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
                store?.delete(recipe)
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: { recipe in
            Text("\u{201C}\(recipe.name)\u{201D} will be removed permanently.")
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func row(title: String, items: [RecipeItem], isUserSection: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.Typography.label)
                .tracking(1.5)
                .foregroundStyle(Theme.Colors.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(items, id: \.id) { recipe in
                        cell(recipe, isUserSection: isUserSection)
                    }
                }
            }
        }
    }

    // MARK: - Cell

    @ViewBuilder
    private func cell(_ recipe: RecipeItem, isUserSection: Bool) -> some View {
        let filterID = recipe.adjustmentStack.filter?.filterID
        VStack(spacing: 4) {
            ZStack {
                if let fid = filterID, let img = thumbnails[fid] {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Theme.Colors.panel
                }
            }
            .frame(width: 56, height: 56)
            .clipped()
            Text(recipe.name.uppercased())
                .font(Theme.Typography.label)
                .tracking(1.0)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(Theme.Colors.text)
                .frame(width: 64)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            Haptic.play(.recipeApply)
            viewModel.applyRecipe(recipe)
        }
        .contextMenu {
            if isUserSection {
                Button { renameTarget = recipe } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Button(role: .destructive) { deleteTarget = recipe } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .accessibilityLabel("\(recipe.name) preset")
    }

    // MARK: - Thumbnails

    /// Identity used to invalidate thumbnails when the photo changes.
    private var importedPhotoIdentity: String {
        guard let img = viewModel.importedImage else { return "" }
        return img.previewCIImage.extent.debugDescription
    }

    @MainActor
    private func regenerateThumbnails() async {
        guard let imported = viewModel.importedImage else {
            thumbnails = [:]
            photoID = ""
            return
        }
        let newID = importedPhotoIdentity
        if newID != photoID {
            thumbnailCache.clear()
            thumbnails = [:]
            photoID = newID
        }
        let src = imported.previewCIImage
        let side = FilterThumbnailCache.thumbnailSide
        let scale = side / max(src.extent.width, src.extent.height)
        let small = src.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // Collect unique filterIDs referenced across all current presets so we
        // render each LUT thumbnail only once.
        let allRecipes: [RecipeItem] = (store?.items) ?? []
        let referencedIDs: Set<String> = Set(
            allRecipes.compactMap { $0.adjustmentStack.filter?.filterID }
        )
        for filterID in referencedIDs {
            if let cached = thumbnailCache.image(forPhotoID: photoID, filterID: filterID) {
                thumbnails[filterID] = cached
                continue
            }
            guard let filter = viewModel.filterLibrary.filter(withID: filterID) else { continue }
            let cube = filter.cube()
            if let img = FilterThumbnailCache.renderThumbnail(
                source: small, cube: cube, strength: 1.0, context: thumbnailContext) {
                thumbnailCache.setImage(img, forPhotoID: photoID, filterID: filterID)
                thumbnails[filterID] = img
            }
            await Task.yield()
        }
    }
}

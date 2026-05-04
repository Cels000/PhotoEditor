// EditorPresetPickerView.swift
// Replaces FilterStripView in the editor's "Looks" panel with a categorized
// recipe picker. Each row is a category (MY RECIPES, DEFAULT, COLOR FILM,
// B&W FILM, ERA & CAMERA). Tap a thumbnail to apply the full recipe stack;
// long-press a user-saved recipe for rename/delete.
//
// Thumbnail rendering: each cell runs the recipe's full AdjustmentStack
// through PipelineBuilder against a downsampled (~200px) source image, so
// the preview reflects every slider/curve/split-tone — not just the LUT.
// Cached by recipe.id for the lifetime of the photo; recipes added or
// renamed get fresh renders on next photo import.

import CoreImage
import SwiftUI
import UIKit

struct EditorPresetPickerView: View {

    @Bindable var viewModel: EditorViewModel

    /// Keyed by recipe.id (UUID string). Each entry is the recipe's full
    /// pipeline rendered against the current photo at thumbnail resolution.
    @State private var thumbnails: [String: UIImage] = [:]
    @State private var thumbnailContext = CIContext(options: [.useSoftwareRenderer: false])
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
        VStack(spacing: 4) {
            ZStack {
                if let img = thumbnails[recipe.id.uuidString] {
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
            thumbnails = [:]
            photoID = newID
        }
        // Downsample the source so each per-recipe pipeline render is cheap.
        let src = imported.previewCIImage
        let side = FilterThumbnailCache.thumbnailSide
        let scale = side / max(src.extent.width, src.extent.height)
        let small = src.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // Stable LUT lookup closure for PipelineBuilder.
        let lib = viewModel.filterLibrary
        let cubeResolver: CubeResolver = { id in lib.filter(withID: id)?.cube() }

        let allRecipes: [RecipeItem] = (store?.items) ?? []
        for recipe in allRecipes {
            let key = recipe.id.uuidString
            if thumbnails[key] != nil { continue }
            let stack = recipe.adjustmentStack
            let chain = PipelineBuilder.build(stack: stack, source: small, cubeResolver: cubeResolver)
            if let cg = thumbnailContext.createCGImage(chain, from: chain.extent) {
                thumbnails[key] = UIImage(cgImage: cg)
            }
            await Task.yield()
        }
    }
}

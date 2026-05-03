import CoreImage
import Foundation
import Photos
import SwiftData
import SwiftUI
import UIKit

@MainActor
@Observable
final class EditorViewModel {

    // MARK: - Observable state
    var stack: AdjustmentStack = .identity
    var previewImage: UIImage?
    var importedImage: ImportedImage?
    var isSaving: Bool = false
    var errorMessage: String?
    var successMessage: String?

    /// Set by ContentView once the SwiftData ModelContainer is available.
    /// Optional so previews/tests don't require a container.
    var libraryStore: LibraryStore?

    /// The currently-open library item, if this session was launched from
    /// the library (or has been saved to the library at least once). When
    /// non-nil, saveToLibrary() updates this row instead of inserting a new one.
    private(set) var currentLibraryItem: LibraryItem?

    // MARK: - Filter catalog
    let filterLibrary: FilterLibrary

    // MARK: - Internals
    private let engine: RenderEngine?
    private var renderTask: Task<Void, Never>?
    private static let debounceNanos: UInt64 = 40_000_000   // 40 ms

    // MARK: - Undo / Redo
    private var undoStack = UndoStack()
    private var pendingDragSnapshot: AdjustmentStack?

    var canUndo: Bool { undoStack.canUndo }
    var canRedo: Bool { undoStack.canRedo }

    /// Call when a slider drag begins (or any continuous edit). Captures the
    /// pre-drag snapshot so endInteractiveEdit() can push exactly one entry.
    func beginInteractiveEdit() {
        // Only capture if we're not already tracking a drag (re-entrancy guard).
        if pendingDragSnapshot == nil {
            pendingDragSnapshot = stack
        }
    }

    /// Call when a slider drag ends. Pushes the post-drag stack to the undo
    /// stack iff it differs from the pre-drag snapshot.
    func endInteractiveEdit() {
        defer { pendingDragSnapshot = nil }
        guard let pre = pendingDragSnapshot, pre != stack else { return }
        undoStack.push(stack)
    }

    /// For discrete (non-drag) mutations: filter selection, crop apply, recipe apply.
    /// Caller must have already mutated `stack` before calling this.
    func commitDiscreteChange() {
        undoStack.push(stack)
    }

    func undo() {
        guard let restored = undoStack.undo() else { return }
        stack = restored
        stackDidChange()
    }

    func redo() {
        guard let restored = undoStack.redo() else { return }
        stack = restored
        stackDidChange()
    }

    init(filterLibrary: FilterLibrary = FilterLibrary()) {
        self.filterLibrary = filterLibrary
        do {
            self.engine = try RenderEngine()
        } catch {
            self.engine = nil
            self.errorMessage = "Metal is unavailable on this device. Rendering disabled."
        }
        self.undoStack.seed(.identity)
    }

    // MARK: - Public API used by ContentView

    func importPhoto(data: Data) async {
        do {
            let imported = try ImageImporter.importImage(from: data)
            self.importedImage = imported
            // Reset to identity so the new photo starts unedited.
            self.stack = .identity
            self.currentLibraryItem = nil
            self.undoStack.clear(seed: .identity)
            // Render initial preview synchronously (no debounce on first frame).
            await renderPreviewNow()
        } catch {
            self.errorMessage = "The selected photo could not be loaded."
        }
    }

    /// Called from every slider's binding set closure — debounces the preview render.
    func stackDidChange() {
        renderTask?.cancel()
        let snapshotStack = stack
        guard let engine, let source = importedImage?.previewCIImage else { return }
        let resolver = makeCubeResolver()

        renderTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.debounceNanos)
            guard !Task.isCancelled, let self else { return }
            do {
                let cg = try await engine.renderPreview(stack: snapshotStack, source: source, cubeResolver: resolver)
                guard !Task.isCancelled else { return }
                self.previewImage = UIImage(cgImage: cg)
            } catch {
                // Render failure is non-fatal for live preview; keep last good image.
            }
        }
    }

    /// Selects a filter by ID. Pass nil (or BuiltInLUTs.ID.identity) to clear.
    func selectFilter(id: String?) {
        if let id = id, id != BuiltInLUTs.ID.identity {
            stack.filter = FilterSelection(filterID: id, strength: stack.filter?.strength ?? 1.0)
        } else {
            stack.filter = nil
        }
        stackDidChange()
        commitDiscreteChange()
    }

    func setFilterStrength(_ value: Double) {
        guard var sel = stack.filter else { return }
        sel.strength = max(0.0, min(1.0, value))
        stack.filter = sel
        stackDidChange()
    }

    func resetAdjustments() {
        guard stack != .identity else { return }
        stack = .identity
        undoStack.push(.identity)
        stackDidChange()
        errorMessage = nil
        successMessage = nil
    }

    func saveImage() async {
        guard let engine, let imported = importedImage else {
            errorMessage = "Choose a photo before saving."
            return
        }

        isSaving = true
        errorMessage = nil
        successMessage = nil

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            isSaving = false
            errorMessage = "Photo Library access is required to save edits."
            return
        }

        do {
            let cg = try await engine.renderExport(stack: stack, source: imported.exportCIImage, cubeResolver: self.makeCubeResolver())
            let uiImage = UIImage(cgImage: cg)
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: uiImage)
            }
            successMessage = "Saved to Photos."
        } catch {
            errorMessage = error.localizedDescription
        }

        isSaving = false
    }

    // MARK: - Library

    /// Persists the current edit to the in-app library. If this session was
    /// opened from a library item, updates that row; otherwise inserts a new one.
    /// Generates a 400x400 thumbnail of the current edit on a detached background
    /// task so the main actor never blocks on rendering.
    func saveToLibrary() async {
        guard let store = libraryStore else {
            errorMessage = "Library is not available."
            return
        }
        guard let engine, let imported = importedImage else {
            errorMessage = "Choose a photo before saving to library."
            return
        }

        isSaving = true
        errorMessage = nil
        successMessage = nil

        let snapshotStack = stack
        let assetID = imported.sourceAssetID
        let source = imported.previewCIImage
        let resolver = makeCubeResolver()

        // Render thumbnail off-main. ThumbnailGenerator is non-isolated; engine is an actor.
        let thumb: Data?
        do {
            thumb = try await Task.detached(priority: .background) {
                try await ThumbnailGenerator.makeThumbnail(
                    stack: snapshotStack,
                    source: source,
                    engine: engine,
                    cubeResolver: resolver
                )
            }.value
        } catch {
            isSaving = false
            errorMessage = "Could not generate thumbnail."
            return
        }

        if let existing = currentLibraryItem {
            store.update(existing, stack: snapshotStack, thumbnail: thumb)
        } else {
            let inserted = store.save(stack: snapshotStack, sourceAssetID: assetID, thumbnail: thumb)
            currentLibraryItem = inserted
        }

        successMessage = "Saved to Library."
        isSaving = false
    }

    /// Opens an existing library item: re-loads its source from PHAsset, restores
    /// the stored adjustment stack, resets undo history, and triggers a preview render.
    /// LIB-05: PHAsset deletion produces a user-facing error, never a crash.
    func openLibraryItem(_ item: LibraryItem) async {
        errorMessage = nil
        successMessage = nil

        guard let assetID = item.sourceAssetID else {
            errorMessage = "This photo's source is no longer in your Photos library."
            return
        }

        do {
            let imported = try await ImageImporter.importImage(fromAssetID: assetID)
            self.importedImage = imported
            self.stack = item.adjustmentStack
            self.currentLibraryItem = item
            self.undoStack.clear(seed: self.stack)
            await renderPreviewNow()
        } catch ImageImportError.phAssetUnavailable {
            errorMessage = "This photo's source is no longer in your Photos library."
        } catch {
            errorMessage = "Could not reopen this edit."
        }
    }

    // MARK: - Private helpers

    private func makeCubeResolver() -> CubeResolver {
        let lib = filterLibrary
        return { id in lib.filter(withID: id)?.cube() }
    }

    private func renderPreviewNow() async {
        guard let engine, let source = importedImage?.previewCIImage else { return }
        do {
            let cg = try await engine.renderPreview(stack: stack, source: source, cubeResolver: self.makeCubeResolver())
            self.previewImage = UIImage(cgImage: cg)
        } catch {
            self.errorMessage = "Could not render preview."
        }
    }
}

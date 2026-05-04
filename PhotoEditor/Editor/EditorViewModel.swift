import CoreImage
import Foundation
import ImageIO
import Photos
import SwiftData
import SwiftUI
import UIKit

// MARK: - Export error type

enum ExportPipelineError: Error {
    case notReady
    case engineUnavailable
}

@MainActor
@Observable
final class EditorViewModel {

    // MARK: - Observable state

    /// Top-level edit state. Wraps subject + background AdjustmentStacks and an optional mask.
    var document: EditDocument = .identity

    /// Active sub-segment for slider writes. Ignored when `document.mask == nil`.
    var activeScope: MaskScope = .subject

    /// Backward-compatible computed view of the active stack. Panel views read
    /// and write `viewModel.stack[keyPath:]`; the setter routes per scope and
    /// enforces the crop mirror invariant (subject.crop == background.crop).
    var stack: AdjustmentStack {
        get {
            guard document.mask != nil else { return document.subjectStack }
            switch activeScope {
            case .subject, .full: return document.subjectStack
            case .background:     return document.backgroundStack
            }
        }
        set {
            if document.mask == nil {
                // Single-stack mode: write to subjectStack and mirror to backgroundStack
                // so they stay identical (clean mask-enable later).
                document.subjectStack = newValue
                document.backgroundStack = newValue
                return
            }
            switch activeScope {
            case .subject:
                document.subjectStack = newValue
            case .background:
                document.backgroundStack = newValue
            case .full:
                document.subjectStack = newValue
                document.backgroundStack = newValue
            }
            // Crop mirror invariant: regardless of scope, both crops must equal newValue.crop.
            document.subjectStack.crop = newValue.crop
            document.backgroundStack.crop = newValue.crop
        }
    }

    var previewImage: UIImage?
    var importedImage: ImportedImage?
    var isSaving: Bool = false
    var isExporting: Bool = false
    var shareData: Data?
    var shareFormat: ExportFormat?
    var errorMessage: String?
    var successMessage: String?

    /// Set by ContentView once the SwiftData ModelContainer is available.
    /// Optional so previews/tests don't require a container.
    var libraryStore: LibraryStore?

    /// Set by ContentView once the SwiftData ModelContainer is available.
    /// Optional so previews/tests don't require a container.
    var recipeStore: RecipeStore?

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

    // MARK: - Mask state

    /// In-process Vision compute + cache for foreground masks.
    private let maskStore: SubjectMaskStore = SubjectMaskStore()

    /// The current mask result (combined + per-instance) for the loaded asset.
    /// Read by render path; nil means no mask data available (single-stack render).
    private(set) var currentMaskResult: SubjectMaskResult?

    /// Number of detected foreground instances in the loaded asset. 0 means
    /// the toolbar Mask button is disabled.
    private(set) var lastDetectedInstanceCount: Int = 0

    /// True while a Vision compute is in flight for the current asset.
    private(set) var maskComputeInFlight: Bool = false

    // MARK: - Undo / Redo
    private var undoStack = UndoStack()
    private var pendingDragSnapshot: EditDocument?

    var canUndo: Bool { undoStack.canUndo }
    var canRedo: Bool { undoStack.canRedo }

    /// Call when a slider drag begins (or any continuous edit). Captures the
    /// pre-drag snapshot so endInteractiveEdit() can push exactly one entry.
    func beginInteractiveEdit() {
        // Only capture if we're not already tracking a drag (re-entrancy guard).
        if pendingDragSnapshot == nil {
            pendingDragSnapshot = document
        }
    }

    /// Call when a slider drag ends. Pushes the post-drag stack to the undo
    /// stack iff it differs from the pre-drag snapshot.
    func endInteractiveEdit() {
        defer { pendingDragSnapshot = nil }
        guard let pre = pendingDragSnapshot, pre != document else { return }
        undoStack.push(document)
    }

    /// For discrete (non-drag) mutations: filter selection, crop apply, recipe apply.
    /// Caller must have already mutated `stack` before calling this.
    func commitDiscreteChange() {
        undoStack.push(document)
    }

    func undo() {
        guard let restored = undoStack.undo() else { return }
        document = restored
        stackDidChange()
    }

    func redo() {
        guard let restored = undoStack.redo() else { return }
        document = restored
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

    func importPhoto(data: Data, sourceAssetID: String? = nil) async {
        do {
            let baseImported = try ImageImporter.importImage(from: data)
            // Splice the assetID from the picker into the imported value.
            self.importedImage = ImportedImage(
                sourceData: baseImported.sourceData,
                previewCIImage: baseImported.previewCIImage,
                exportCIImage: baseImported.exportCIImage,
                pixelSize: baseImported.pixelSize,
                sourceAssetID: sourceAssetID
            )
            // Reset to identity so the new photo starts unedited.
            self.document = .identity
            self.currentMaskResult = nil
            self.lastDetectedInstanceCount = 0
            self.activeScope = .subject
            self.currentLibraryItem = nil
            self.undoStack.clear(seed: .identity)
            // Render initial preview synchronously (no debounce on first frame).
            await renderPreviewNow()
            prefetchMaskForCurrentPhoto()
        } catch {
            self.errorMessage = "The selected photo could not be loaded."
        }
    }

    /// Called from every slider's binding set closure — debounces the preview render.
    func stackDidChange() {
        renderTask?.cancel()
        let snapshotDoc = document
        guard let engine, let source = importedImage?.previewCIImage else { return }
        let resolver = makeCubeResolver()
        let maskResult: SubjectMaskResult? = currentMaskResult

        renderTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.debounceNanos)
            guard !Task.isCancelled, let self else { return }
            do {
                let cg = try await engine.renderPreview(
                    document: snapshotDoc,
                    source: source,
                    cubeResolver: resolver,
                    maskResult: maskResult
                )
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
        guard document != .identity else { return }
        document = .identity
        currentMaskResult = nil
        lastDetectedInstanceCount = 0
        activeScope = .subject
        undoStack.push(.identity)
        stackDidChange()
        errorMessage = nil
        successMessage = nil
    }

    // MARK: - Export pipeline

    /// Render full-res, encode to options.format with options.quality, resize to options.size.
    /// Preserves source EXIF (TIFF/Exif), strips GPS, embeds source color profile.
    /// Caller dispatches the returned Data (Save to Photos / Share / Both).
    func export(options: ExportOptions) async throws -> Data {
        guard let engine else { throw ExportPipelineError.engineUnavailable }
        guard let imported = importedImage else { throw ExportPipelineError.notReady }

        isExporting = true
        defer { isExporting = false }

        // Full-res render on the engine actor.
        let cg = try await engine.renderExport(
            document: document,
            source: imported.exportCIImage,
            cubeResolver: makeCubeResolver(),
            maskResult: currentMaskResult
        )

        // Read source metadata + color space from the raw bytes (preserves EXIF dictionaries).
        let (sourceProps, sourceCS) = Self.readSourceMetadata(from: imported.sourceData)
            ?? ([:], imported.exportCIImage.colorSpace)

        // Encode off the main actor (CGImageDestination + Lanczos resize is CPU-heavy).
        let data: Data = try await Task.detached(priority: .userInitiated) {
            try ExportService.encode(
                cgImage: cg,
                sourceProperties: sourceProps,
                colorSpace: sourceCS,
                options: options
            )
        }.value

        return data
    }

    /// Save to Photos. Surfaces success/error via observable strings.
    func saveExport(options: ExportOptions) async {
        errorMessage = nil; successMessage = nil
        do {
            let data = try await export(options: options)
            try await PhotoSaver.save(encodedData: data, format: options.format)
            successMessage = "Saved to Photos."
        } catch PhotoSaver.Error.permissionDenied {
            errorMessage = "Photo Library access is required to save."
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    /// Stage data for the share sheet. ContentView observes shareData/shareFormat
    /// and presents ShareSheetView. Caller clears shareData on dismiss.
    func shareExport(options: ExportOptions) async {
        errorMessage = nil
        do {
            let data = try await export(options: options)
            shareData = data
            shareFormat = options.format
        } catch {
            errorMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private static func readSourceMetadata(from data: Data) -> ([CFString: Any], CGColorSpace?)? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else {
            return nil
        }
        // Try to extract a CGColorSpace via CGImageSourceCreateImageAtIndex (carries colorSpace).
        let cs: CGColorSpace? = CGImageSourceCreateImageAtIndex(src, 0, nil)?.colorSpace
        return (props, cs)
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

        // Snapshot for thumbnail render (uses subjectStack — thumbnails are flat
        // single-stack renders) AND full document save below.
        let snapshotDocument = self.document
        let snapshotStack = snapshotDocument.subjectStack
        let assetID = imported.sourceAssetID
        let source = imported.previewCIImage
        let resolver = makeCubeResolver()

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
            store.update(existing, document: snapshotDocument, thumbnail: thumb)
        } else {
            let inserted = store.save(document: snapshotDocument, sourceAssetID: assetID, thumbnail: thumb)
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
            // Read the full v2 document (or legacy v1 stack lifted to v2 via the
            // editDocument getter's fallback path).
            self.document = item.editDocument
            self.currentMaskResult = nil
            self.lastDetectedInstanceCount = 0
            self.activeScope = .subject
            self.currentLibraryItem = item
            self.undoStack.clear(seed: self.document)
            await renderPreviewNow()
            prefetchMaskForCurrentPhoto()
        } catch ImageImportError.phAssetUnavailable {
            errorMessage = "This photo's source is no longer in your Photos library."
        } catch {
            errorMessage = "Could not reopen this edit."
        }
    }

    // MARK: - Recipes

    /// Replace the current adjustment stack with the recipe's stack.
    /// RECIPE-02: applies the recipe to the current photo; RECIPE-05: missing
    /// filter ID is degraded to nil filter (slot blank) without affecting other
    /// adjustments. Creates exactly ONE undo entry for the entire apply.
    func applyRecipe(_ recipe: RecipeItem) {
        var newStack = recipe.adjustmentStack

        // RECIPE-05: resolve filter ID; if it doesn't exist in the current
        // FilterLibrary, clear the filter slot. All other adjustments stay intact.
        if let sel = newStack.filter, filterLibrary.filter(withID: sel.filterID) == nil {
            newStack.filter = nil
        }

        // Recipes apply to the entire document (both stacks). Save and restore scope
        // so the user's active sub-segment isn't disturbed.
        let savedScope = activeScope
        activeScope = .full
        stack = newStack
        activeScope = savedScope
        commitDiscreteChange()  // single undo entry for the whole apply
        stackDidChange()         // debounced re-render of preview
        successMessage = "Applied \"\(recipe.name)\"."
    }

    /// Persist the current stack as a named Recipe. If a photo is loaded, a
    /// 200x200 JPEG thumbnail is rendered off the main actor and stored on the
    /// RecipeItem. RECIPE-01.
    func saveCurrentAsRecipe(name: String) async {
        guard let store = recipeStore else {
            errorMessage = "Recipes are not available."
            return
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Please enter a name for the recipe."
            return
        }

        // Recipes save just the subjectStack (mask state is not persisted in recipes).
        let snapshotStack = document.subjectStack
        var thumbnailData: Data? = nil

        // If a photo is loaded, render a thumbnail. If not, save without one
        // (UI shows abstract gradient cell — locked decision in CONTEXT.md).
        if let engine, let imported = importedImage {
            let source = imported.previewCIImage
            let resolver = makeCubeResolver()
            thumbnailData = try? await Task.detached(priority: .background) {
                try await ThumbnailGenerator.makeThumbnail(
                    stack: snapshotStack,
                    source: source,
                    engine: engine,
                    cubeResolver: resolver
                )
            }.value
        }

        store.save(name: trimmed, stack: snapshotStack, thumbnail: thumbnailData)
        successMessage = "Saved Recipe \"\(trimmed)\"."
    }

    // MARK: - Mask lifecycle (Task 8)

    /// True when the mask toolbar button should accept taps.
    /// False if no photo is loaded, or if a previous compute returned 0 instances.
    var canApplyMask: Bool {
        importedImage != nil
    }

    /// Triggered by the toolbar tap. Computes (or fetches cached) mask, then enables
    /// the mask in the document with default settings. On 0 instances, surfaces a
    /// "No subject detected" message and leaves the mask disabled.
    func enterMaskMode() async {
        guard let imported = importedImage else {
            errorMessage = "Mask requires an imported photo."
            return
        }
        let assetID: AssetID = imported.sourceAssetID ?? "unattached-\(ObjectIdentifier(self).hashValue)"

        maskComputeInFlight = true
        errorMessage = nil
        defer { maskComputeInFlight = false }

        do {
            let result = try await maskStore.mask(for: assetID, source: imported.previewCIImage)
            currentMaskResult = result
            lastDetectedInstanceCount = result.instanceCount

            if result.instanceCount == 0 {
                // Informational, not an error: surface via toast (successMessage),
                // not via alert (errorMessage). User can re-tap on a different photo.
                successMessage = "No subject detected."
                return
            }

            // Enable mask in document, scope defaults to .subject. Snapshot subject
            // into background so they start identical (clean divergence point).
            document.mask = SubjectMask()
            document.backgroundStack = document.subjectStack
            activeScope = .subject
            commitDiscreteChange()
            stackDidChange()
        } catch {
            errorMessage = "Couldn't compute subject mask. Try again."
        }
    }

    /// Fire-and-forget prefetch on photo import / library open. The next time the
    /// user taps the mask button, the result will already be cached.
    func prefetchMaskForCurrentPhoto() {
        guard let imported = importedImage else { return }
        let assetID: AssetID = imported.sourceAssetID ?? "unattached-\(ObjectIdentifier(self).hashValue)"
        maskStore.prefetch(for: assetID, source: imported.previewCIImage)
    }

    /// Refinement: feather slider (0–1).
    func updateMaskFeather(_ value: Double) {
        guard document.mask != nil else { return }
        document.mask?.feather = max(0, min(1, value))
        stackDidChange()
    }

    /// Refinement: invert toggle.
    func setMaskInvert(_ inverted: Bool) {
        guard document.mask != nil else { return }
        document.mask?.invert = inverted
        stackDidChange()
    }

    /// Refinement: tap-to-toggle a detected instance's inclusion.
    func toggleInstanceExcluded(_ index: Int) {
        guard document.mask != nil else { return }
        if document.mask!.excludedInstances.contains(index) {
            document.mask!.excludedInstances.remove(index)
        } else {
            document.mask!.excludedInstances.insert(index)
        }
        stackDidChange()
    }

    /// Removes the mask from the document. Background stack is reset to match
    /// subject stack, scope reverts to .subject. Single undo entry.
    func removeMask() {
        guard document.mask != nil else { return }
        document.mask = nil
        document.backgroundStack = document.subjectStack
        activeScope = .subject
        commitDiscreteChange()
        stackDidChange()
    }

    // MARK: - Private helpers

    private func makeCubeResolver() -> CubeResolver {
        let lib = filterLibrary
        return { id in lib.filter(withID: id)?.cube() }
    }

    private func renderPreviewNow() async {
        guard let engine, let source = importedImage?.previewCIImage else { return }
        do {
            let cg = try await engine.renderPreview(
                document: document,
                source: source,
                cubeResolver: self.makeCubeResolver(),
                maskResult: currentMaskResult
            )
            self.previewImage = UIImage(cgImage: cg)
        } catch {
            self.errorMessage = "Could not render preview."
        }
    }
}

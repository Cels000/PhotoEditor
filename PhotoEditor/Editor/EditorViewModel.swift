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

    /// Toolbar-controlled visibility for the post-pipeline RGB histogram overlay.
    var isHistogramVisible: Bool = false
    /// Latest committed histogram bitmap. Recomputed only on render commit
    /// (stackDidChange Task tail + renderPreviewNow), never per slider tick.
    /// Held nil while `isHistogramVisible == false` so the overlay view never
    /// pays for stale state.
    var histogramImage: UIImage?
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
    /// Monotonic counter incremented on each `stackDidChange()`. Each render
    /// task captures its generation and only commits its result if it is still
    /// the latest — eliminates stale-frame writes (TOCTOU on Task.isCancelled)
    /// and coalesces queued work behind the engine actor.
    private var renderGeneration: UInt64 = 0

    /// MainActor-owned CIContext used solely for histogram rendering at
    /// preview-commit. Cheap to keep alive, expensive to recreate per call —
    /// do NOT inline-construct in recomputeHistogramIfVisible.
    private let histogramContext: CIContext = CIContext(options: [.useSoftwareRenderer: false])

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

    /// `explicitEXIFOrientation` lets the call site (camera-roll grid via
    /// `PHImageManager.requestImageDataAndOrientation`) pass through Photos'
    /// authoritative orientation. Photos.app may strip or overwrite the
    /// orientation tag in the encoded bytes for edited / rotated assets,
    /// so reading EXIF from the bytes alone leaves portrait photos sideways.
    /// Nil = no override; ImageImporter falls back to its own EXIF read.
    func importPhoto(data: Data,
                     sourceAssetID: String? = nil,
                     explicitEXIFOrientation: Int32? = nil) async {
        do {
            let baseImported = try ImageImporter.importImage(
                from: data,
                explicitEXIFOrientation: explicitEXIFOrientation
            )
            // Splice the assetID from the picker into the imported value.
            self.importedImage = ImportedImage(
                sourceData: baseImported.sourceData,
                previewCIImage: baseImported.previewCIImage,
                exportCIImage: baseImported.exportCIImage,
                pixelSize: baseImported.pixelSize,
                sourceAssetID: sourceAssetID,
                wasRawSource: baseImported.wasRawSource,
                hasHDRContent: baseImported.hasHDRContent
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
        renderGeneration &+= 1
        let myGen = renderGeneration
        let snapshotDoc = document
        guard let engine, let source = importedImage?.previewCIImage else { return }
        let resolver = makeCubeResolver()
        let maskResult: SubjectMaskResult? = currentMaskResult

        renderTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.debounceNanos)
            guard !Task.isCancelled, let self else { return }
            // Coalesce: if a newer scrub has arrived during debounce, skip the render entirely.
            guard myGen == self.renderGeneration else { return }
            do {
                let cg = try await engine.renderPreview(
                    document: snapshotDoc,
                    source: source,
                    cubeResolver: resolver,
                    maskResult: maskResult
                )
                // After the actor-hopped render returns, commit only if we're still
                // the latest scheduled generation. Prevents stale frames from overwriting
                // fresher output when CIContext.createCGImage queues up behind the actor.
                guard myGen == self.renderGeneration else { return }
                self.previewImage = UIImage(cgImage: cg)
                self.recomputeHistogramIfVisible(from: cg)
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

        // HDR HEIC branch: bypass the SDR encoder. The HDR render path keeps
        // working-space EDR values >1.0 alive through to the 10-bit HLG encode,
        // so highlights that ProRAW captured (or that LUTs / curves pushed past
        // SDR clip) actually appear bright on the EDR display. SDR formats and
        // hdr=false fall through to the standard ExportService.encode path.
        if options.hdr && options.format == .heic {
            let resolvedLongEdge = options.size.resolve(
                sourceLongEdge: Int(max(imported.exportCIImage.extent.width,
                                        imported.exportCIImage.extent.height))
            )
            let snapshotDocument = self.document
            let snapshotSource = imported.exportCIImage
            let resolver = makeCubeResolver()
            let snapshotMask = self.currentMaskResult
            return try await engine.renderExportHDRData(
                document: snapshotDocument,
                source: snapshotSource,
                cubeResolver: resolver,
                maskResult: snapshotMask,
                targetLongEdge: resolvedLongEdge,
                quality: options.quality
            )
        }

        // Full-res render on the engine actor.
        let cg = try await engine.renderExport(
            document: document,
            source: imported.exportCIImage,
            cubeResolver: makeCubeResolver(),
            maskResult: currentMaskResult
        )

        // Read source metadata + color space from the raw bytes (preserves EXIF dictionaries).
        let (sourceProps, sourceCSFromBytes) = Self.readSourceMetadata(from: imported.sourceData)
            ?? ([:], imported.exportCIImage.colorSpace)

        // RAW gamut preservation: when the source was a RAW capture, the
        // embedded preview JPEG is often sRGB, but the actual decoded RAW
        // pixels are wide-gamut and the render output is Display P3. Tagging
        // the export as sRGB would throw away exactly the gamut the user
        // shot RAW for. Force Display P3 in that case.
        let sourceCS: CGColorSpace? = imported.wasRawSource
            ? CGColorSpace(name: CGColorSpace.displayP3)
            : sourceCSFromBytes

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
            // If the saved document already has a mask, restore the mask result so
            // the composite renders correctly. Otherwise just prefetch for the
            // common case where the user enables a mask later.
            if self.document.mask != nil {
                await restoreMaskResultForCurrentPhoto()
            } else {
                prefetchMaskForCurrentPhoto()
            }
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
    ///
    /// Scoping: with no mask, writes to both stacks (the `stack` setter mirrors).
    /// With a mask active, writes only to the active scope so the other region's
    /// edits are preserved — applying a recipe must never silently flatten
    /// per-region work the user did before this call.
    func applyRecipe(_ recipe: RecipeItem) {
        var newStack = recipe.adjustmentStack

        // RECIPE-05: resolve filter ID; if it doesn't exist in the current
        // FilterLibrary, clear the filter slot. All other adjustments stay intact.
        if let sel = newStack.filter, filterLibrary.filter(withID: sel.filterID) == nil {
            newStack.filter = nil
        }

        let maskActive = document.mask != nil
        if maskActive {
            // Preserve the other scope's edits; the `stack` setter already routes
            // by `activeScope` and enforces the crop mirror invariant.
            stack = newStack
            let scopeName = activeScope == .background ? "background" : "subject"
            successMessage = "Applied \"\(recipe.name)\" to \(scopeName)."
        } else {
            // Single-stack mode: writing via .full is unnecessary (the setter
            // already mirrors when mask is nil), but keep an explicit pass for
            // symmetry / future-proofing.
            stack = newStack
            successMessage = "Applied \"\(recipe.name)\"."
        }
        commitDiscreteChange()  // single undo entry for the whole apply
        stackDidChange()         // debounced re-render of preview
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
    /// Disabled when no photo is loaded, or when a previous compute on this asset
    /// returned 0 instances (currentMaskResult is non-nil with instanceCount == 0).
    var canApplyMask: Bool {
        guard importedImage != nil else { return false }
        // After a compute that returned 0 instances, leave the button disabled
        // until a new photo is imported (which clears currentMaskResult).
        if let result = currentMaskResult, result.instanceCount == 0 {
            return false
        }
        return true
    }

    /// Triggered by the toolbar tap. Computes (or fetches cached) mask, then enables
    /// the mask in the document with default settings. On 0 instances, surfaces a
    /// "No subject detected" message and leaves the mask disabled.
    func enterMaskMode() async {
        guard let imported = importedImage else {
            errorMessage = "Mask requires an imported photo."
            return
        }
        let assetID: AssetID = imported.sourceAssetID ?? "unattached-\(imported.sessionID.uuidString)"

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
        let assetID: AssetID = imported.sourceAssetID ?? "unattached-\(imported.sessionID.uuidString)"
        maskStore.prefetch(for: assetID, source: imported.previewCIImage)
    }

    /// Compute (or fetch cached) mask result and update currentMaskResult so the
    /// composite render path can use it. Used by openLibraryItem when the saved
    /// document already has a mask attached. Errors are swallowed — if Vision fails
    /// here, the document still loads with single-stack render until the user
    /// re-enables the mask manually.
    private func restoreMaskResultForCurrentPhoto() async {
        guard let imported = importedImage else { return }
        let assetID: AssetID = imported.sourceAssetID ?? "unattached-\(imported.sessionID.uuidString)"
        do {
            let result = try await maskStore.mask(for: assetID, source: imported.previewCIImage)
            // The user may have removed the mask while we were waiting; double-check.
            guard document.mask != nil else { return }
            self.currentMaskResult = result
            self.lastDetectedInstanceCount = result.instanceCount
            stackDidChange()  // re-render with composite
        } catch {
            // Soft failure — single-stack render remains until user re-taps mask.
        }
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
        // Cancel any in-flight debounced render and bump generation so its post-await
        // commit guard rejects it — otherwise a stale frame from the previous photo
        // could land on top of this fresh first-frame render.
        renderTask?.cancel()
        renderGeneration &+= 1
        do {
            let cg = try await engine.renderPreview(
                document: document,
                source: source,
                cubeResolver: self.makeCubeResolver(),
                maskResult: currentMaskResult
            )
            self.previewImage = UIImage(cgImage: cg)
            self.recomputeHistogramIfVisible(from: cg)
        } catch {
            self.errorMessage = "Could not render preview."
        }
    }

    // MARK: - Histogram overlay

    /// Toolbar-driven toggle. When turning ON, computes immediately from the
    /// current preview if available so the user doesn't have to wiggle a slider
    /// to see bars. When turning OFF, drops the bitmap so the view tree reclaims
    /// memory and stops drawing stale data.
    func toggleHistogram() {
        isHistogramVisible.toggle()
        if !isHistogramVisible {
            histogramImage = nil
            return
        }
        if let ui = previewImage, let cg = ui.cgImage {
            recomputeHistogramIfVisible(from: cg)
        }
    }

    /// Render-commit hook. Called from BOTH commit points
    /// (stackDidChange's debounced Task tail + renderPreviewNow), each already
    /// guarded by the `myGen == renderGeneration` invariant — so this only
    /// fires for the latest-generation preview frame, never mid-drag.
    private func recomputeHistogramIfVisible(from cg: CGImage) {
        guard isHistogramVisible else {
            histogramImage = nil
            return
        }
        if let h = HistogramRenderer.render(postPipeline: cg, context: histogramContext) {
            histogramImage = UIImage(cgImage: h)
        }
    }
}

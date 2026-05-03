import CoreImage
import Foundation
import Photos
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

    // MARK: - Filter catalog
    let filterLibrary: FilterLibrary

    // MARK: - Internals
    private let engine: RenderEngine?
    private var renderTask: Task<Void, Never>?
    private static let debounceNanos: UInt64 = 40_000_000   // 40 ms

    init(filterLibrary: FilterLibrary = FilterLibrary()) {
        self.filterLibrary = filterLibrary
        do {
            self.engine = try RenderEngine()
        } catch {
            self.engine = nil
            self.errorMessage = "Metal is unavailable on this device. Rendering disabled."
        }
    }

    // MARK: - Public API used by ContentView

    func importPhoto(data: Data) async {
        do {
            let imported = try ImageImporter.importImage(from: data)
            self.importedImage = imported
            // Reset to identity so the new photo starts unedited.
            self.stack = .identity
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
    }

    func setFilterStrength(_ value: Double) {
        guard var sel = stack.filter else { return }
        sel.strength = max(0.0, min(1.0, value))
        stack.filter = sel
        stackDidChange()
    }

    func resetAdjustments() {
        stack = .identity
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

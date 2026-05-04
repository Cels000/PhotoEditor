import CoreImage
import Foundation
import Observation
import UIKit

/// LUT-thumbnail renderer for the camera bottom carousel.
///
/// Snapshots the first raw camera frame after `start()`, renders every slot's
/// LUT against that frozen source exactly once, and caches the results. New
/// slots added later (e.g., recipe-store updates) are rendered on demand
/// against the same cached source.
///
/// History: an earlier 2 Hz tick re-rendered every slot from the live frame
/// every half-second. That had two problems — (a) the renderer's only public
/// snapshot was the LUT-applied "cooked" frame, so selecting a non-ORIGINAL
/// preset baked that LUT into every thumbnail (stacked LUTs read as
/// "thumbnails disappeared"), and (b) it spent CPU/GPU re-rendering ~20
/// thumbnails twice a second forever, even though the user already sees the
/// selected look applied to the current scene in the live preview above.
/// Both issues vanish if we render once.
@MainActor
@Observable
final class CameraCarouselThumbnailer {

    /// Published map of slotID → rendered thumbnail. Carousel observes this.
    private(set) var thumbnails: [String: CGImage] = [:]

    /// Vestigial — the old design tracked which carousel cells were on-screen.
    /// Now-unused but kept so existing call sites and tests compile.
    private(set) var visibleSlotIDs: Set<String> = []

    private weak var renderer: CameraPreviewRenderer?
    private let cubeResolver: CubeResolver
    private var slots: [CameraSlot] = []
    private var startTask: Task<Void, Never>?
    private let thumbnailContext: CIContext

    /// Frozen pre-LUT source frame, prepared (cropped + downsampled) once and
    /// reused for every slot's LUT application.
    private var sourceFrame: CIImage?

    static let thumbnailEdge: CGFloat = 96

    init(renderer: CameraPreviewRenderer?, cubeResolver: @escaping CubeResolver) {
        self.renderer = renderer
        self.cubeResolver = cubeResolver
        self.thumbnailContext = CIContext(options: [.useSoftwareRenderer: false])
    }

    func setSlots(_ slots: [CameraSlot]) {
        self.slots = slots
        // Render any newly-added slots against the existing cached source.
        // No-op until `sourceFrame` is set (post-`start()` and a real frame).
        renderMissing()
    }

    func setVisibleSlotIDs(_ ids: Set<String>) {
        visibleSlotIDs = ids
    }

    /// Wait for the camera's first raw frame, then render every slot once.
    /// Times out after ~3s — if the camera never produces a frame, callers
    /// fall back to the carousel's grey placeholder.
    func start() {
        startTask?.cancel()
        startTask = Task { [weak self] in
            for _ in 0..<30 {
                guard !Task.isCancelled else { return }
                if let frame = self?.renderer?.latestRawSnapshot() {
                    await self?.captureSourceAndRender(rawFrame: frame)
                    return
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    func stop() {
        startTask?.cancel()
        startTask = nil
    }

    /// Drop the cached source + thumbnails and re-snapshot from the live
    /// camera. Wire to a UI affordance if/when we want a "refresh thumbnails"
    /// gesture; not invoked anywhere yet.
    func refresh() {
        sourceFrame = nil
        thumbnails = [:]
        start()
    }

    /// Pure helper kept for the existing test. Returns the slots whose IDs
    /// are in `visibleSlotIDs`; production rendering does not consult it.
    func slotsToRender(from all: [CameraSlot]) -> [CameraSlot] {
        all.filter { visibleSlotIDs.contains($0.id) }
    }

    // MARK: - Rendering

    private func captureSourceAndRender(rawFrame: CIImage) async {
        sourceFrame = prepareSource(rawFrame: rawFrame)
        renderMissing()
    }

    private func renderMissing() {
        guard let source = sourceFrame else { return }
        guard !slots.isEmpty else { return }

        var produced = thumbnails
        var changed = false
        for slot in slots where produced[slot.id] == nil {
            let cooked = CameraPreviewRenderer.applyLUT(
                filterSelection: slot.filterSelection,
                to: source,
                cubeResolver: cubeResolver
            )
            if let cg = thumbnailContext.createCGImage(cooked, from: cooked.extent) {
                produced[slot.id] = cg
                changed = true
            }
        }
        if changed { thumbnails = produced }
    }

    private func prepareSource(rawFrame: CIImage) -> CIImage {
        let edge = Self.thumbnailEdge
        let extent = rawFrame.extent
        let cropSize = min(extent.width, extent.height)
        let cropOriginX = extent.origin.x + (extent.width - cropSize) / 2
        let cropOriginY = extent.origin.y + (extent.height - cropSize) / 2
        let cropped = rawFrame.cropped(to: CGRect(x: cropOriginX, y: cropOriginY,
                                                  width: cropSize, height: cropSize))
        let scale = edge / cropSize
        return cropped
            .transformed(by: CGAffineTransform(translationX: -cropped.extent.origin.x,
                                               y: -cropped.extent.origin.y))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }
}

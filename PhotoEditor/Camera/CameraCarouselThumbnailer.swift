import CoreImage
import Foundation
import Observation
import UIKit

/// 2 Hz LUT-thumbnail renderer for the camera bottom carousel. Reads the
/// latest cooked frame from the preview renderer's snapshot, center-crops to
/// square, downsamples to 96×96, and applies every slot's LUT.
///
/// Note: an earlier version filtered to only slots whose IDs had been pushed
/// via `setVisibleSlotIDs` from `.onAppear`/`.onDisappear` on the carousel
/// cells. That infra was load-bearing on a fragile timing assumption (the
/// thumbnailer needed to exist before the cells first appeared, which it did
/// not — `.task` runs after the view is on screen), so visibleSlotIDs stayed
/// empty and no thumbnails ever rendered. We now render every slot every
/// tick. With ~16 presets at 96×96 the per-tick cost is trivial; if it
/// becomes a problem on long recipe lists we can re-introduce a
/// scroll-position-driven slice from the carousel side.
@MainActor
@Observable
final class CameraCarouselThumbnailer {

    /// Published map of slotID → rendered thumbnail. Carousel observes this.
    private(set) var thumbnails: [String: CGImage] = [:]

    /// Vestigial — the carousel still calls `setVisibleSlotIDs` on appear/
    /// disappear, but the thumbnailer renders all slots regardless. Kept so
    /// the existing call sites compile; can be removed in a follow-up.
    private(set) var visibleSlotIDs: Set<String> = []

    private weak var renderer: CameraPreviewRenderer?
    private let cubeResolver: CubeResolver
    private var slots: [CameraSlot] = []
    private var tickTask: Task<Void, Never>?
    private let thumbnailContext: CIContext

    static let thumbnailEdge: CGFloat = 96
    static let tickInterval: TimeInterval = 0.5  // 2 Hz

    init(renderer: CameraPreviewRenderer?, cubeResolver: @escaping CubeResolver) {
        self.renderer = renderer
        self.cubeResolver = cubeResolver
        self.thumbnailContext = CIContext(options: [.useSoftwareRenderer: false])
    }

    func setSlots(_ slots: [CameraSlot]) {
        self.slots = slots
    }

    func setVisibleSlotIDs(_ ids: Set<String>) {
        visibleSlotIDs = ids
    }

    func start() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(nanoseconds: UInt64(Self.tickInterval * 1_000_000_000))
            }
        }
    }

    func stop() {
        tickTask?.cancel()
        tickTask = nil
    }

    /// Pure helper kept for the existing test. Returns the slots whose IDs
    /// are in `visibleSlotIDs`; the production tick path no longer uses this.
    func slotsToRender(from all: [CameraSlot]) -> [CameraSlot] {
        all.filter { visibleSlotIDs.contains($0.id) }
    }

    private func tick() async {
        guard let frame = renderer?.latestSnapshot() else { return }
        guard !slots.isEmpty else { return }

        let edge = Self.thumbnailEdge
        let extent = frame.extent
        let cropSize = min(extent.width, extent.height)
        let cropOriginX = extent.origin.x + (extent.width - cropSize) / 2
        let cropOriginY = extent.origin.y + (extent.height - cropSize) / 2
        let cropped = frame.cropped(to: CGRect(x: cropOriginX, y: cropOriginY,
                                               width: cropSize, height: cropSize))
        let scale = edge / cropSize
        let scaled = cropped
            .transformed(by: CGAffineTransform(translationX: -cropped.extent.origin.x,
                                               y: -cropped.extent.origin.y))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        var produced: [String: CGImage] = [:]
        for slot in slots {
            let cooked = CameraPreviewRenderer.applyLUT(
                filterSelection: slot.filterSelection,
                to: scaled,
                cubeResolver: cubeResolver
            )
            if let cg = thumbnailContext.createCGImage(cooked, from: cooked.extent) {
                produced[slot.id] = cg
            }
        }
        thumbnails = produced
    }
}

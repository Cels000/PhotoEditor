import CoreImage
import Foundation
import Observation
import UIKit

/// 2 Hz LUT-thumbnail renderer for the camera bottom carousel. Reads the
/// latest cooked frame from the preview renderer's snapshot, center-crops to
/// square, downsamples to 96×96, and applies each *visible* slot's LUT.
@MainActor
@Observable
final class CameraCarouselThumbnailer {

    /// Published map of slotID → rendered thumbnail. Carousel observes this.
    private(set) var thumbnails: [String: CGImage] = [:]

    /// Set by the carousel as cells scroll on/off screen. The thumbnailer
    /// renders thumbnails only for these IDs.
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

    /// Pure helper — testable independently of the renderer.
    func slotsToRender(from all: [CameraSlot]) -> [CameraSlot] {
        all.filter { visibleSlotIDs.contains($0.id) }
    }

    private func tick() async {
        guard let frame = renderer?.latestSnapshot() else { return }
        let visibleSlots = slotsToRender(from: slots)
        guard !visibleSlots.isEmpty else { return }

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

        var produced: [String: CGImage] = thumbnails  // keep stale ones for off-screen slots
        for slot in visibleSlots {
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

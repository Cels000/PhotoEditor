import AVFoundation
import CoreImage
import CoreMedia
import Foundation
import Metal
import MetalKit
import UIKit
import os.lock

/// Frame-delegate + LUT-applier + Metal display source for the camera viewfinder.
///
/// Threading:
///   - `captureOutput` runs on the AVCapture sample-buffer queue.
///   - `latestSnapshot` is read by the carousel thumbnailer on a different
///     queue; we protect it with `os_unfair_lock`.
///   - The `MTKView` draw loop pulls the latest cooked image directly from
///     the renderer's snapshot when its delegate fires.
final class CameraPreviewRenderer: NSObject {

    /// Closure injected at init time; resolves a filter UUID to its loaded
    /// cube data. Same closure the editor uses (typically `{ id in
    /// filterLibrary.filter(withID: id)?.loadCube() }`).
    let cubeResolver: CubeResolver

    /// The current carousel-selected slot's full adjustment stack, or nil for
    /// ORIGINAL. Live preview applies `PipelineBuilder.buildLive` against this
    /// — full color/tone signature minus the per-pixel-expensive grain and
    /// halation stages, which only land on capture.
    /// Mutated from MainActor (CameraViewModel) — atomic-set is sufficient
    /// since reads on the capture queue tolerate one-frame staleness.
    private var _currentStack: AdjustmentStack?
    private let stackLock = os_unfair_lock_t.allocate(capacity: 1)

    /// The current camera position. Used to mirror the front-camera preview.
    var isFrontCamera: Bool = false

    /// Latest cooked CIImage (LUT applied) for the MTKView display path.
    private var _latestSnapshot: CIImage?
    /// Latest raw CIImage (no LUT) for the carousel thumbnailer — it needs to
    /// apply each slot's LUT to a clean source, otherwise the selected slot's
    /// LUT bakes into every thumbnail (stacked LUTs → crushed/blown thumbs
    /// that look "missing" the moment you pick a non-ORIGINAL preset).
    private var _latestRawSnapshot: CIImage?
    private let snapshotLock = os_unfair_lock_t.allocate(capacity: 1)

    /// Dedicated CIContext — separate from the editor's contexts so per-frame
    /// work doesn't contend with editor renders. Internal so the MTKView
    /// SwiftUI bridge in Task 6 can render directly through it.
    let ciContext: CIContext

    init(cubeResolver: @escaping CubeResolver) {
        self.cubeResolver = cubeResolver
        let device = MTLCreateSystemDefaultDevice()
        let workingSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!
        var options: [CIContextOption: Any] = [
            .workingColorSpace: workingSpace,
            .useSoftwareRenderer: false
        ]
        if let device {
            self.ciContext = CIContext(mtlDevice: device, options: options)
        } else {
            self.ciContext = CIContext(options: options)
        }
        stackLock.initialize(to: os_unfair_lock())
        snapshotLock.initialize(to: os_unfair_lock())
        super.init()
    }

    deinit {
        stackLock.deinitialize(count: 1); stackLock.deallocate()
        snapshotLock.deinitialize(count: 1); snapshotLock.deallocate()
    }

    func setStack(_ stack: AdjustmentStack?) {
        os_unfair_lock_lock(stackLock)
        _currentStack = stack
        os_unfair_lock_unlock(stackLock)
    }

    func currentStack() -> AdjustmentStack? {
        os_unfair_lock_lock(stackLock); defer { os_unfair_lock_unlock(stackLock) }
        return _currentStack
    }

    /// Read by the MTKView for live display. Cooked = LUT applied.
    func latestSnapshot() -> CIImage? {
        os_unfair_lock_lock(snapshotLock); defer { os_unfair_lock_unlock(snapshotLock) }
        return _latestSnapshot
    }

    /// Read by the carousel thumbnailer. Raw = pre-LUT, so the thumbnailer
    /// can apply each slot's own LUT against a clean source frame.
    func latestRawSnapshot() -> CIImage? {
        os_unfair_lock_lock(snapshotLock); defer { os_unfair_lock_unlock(snapshotLock) }
        return _latestRawSnapshot
    }

    /// Full live-preview pipeline (LUT + light + color + HSL + curves +
    /// splitToning + sharpness + softness + vignette). Skips grain and halation
    /// so 30 fps stays achievable. Used by `captureOutput` and the thumbnailer.
    static func applyLive(stack: AdjustmentStack?,
                          to image: CIImage,
                          cubeResolver: @escaping CubeResolver) -> CIImage {
        guard let stack, stack != .identity else { return image }
        return PipelineBuilder.buildLive(stack: stack, source: image,
                                         cubeResolver: cubeResolver)
    }

    /// LUT-only helper kept for tests that exercise identity-passthrough
    /// semantics on the filter slot in isolation.
    static func applyLUT(filterSelection: FilterSelection?,
                         to image: CIImage,
                         cubeResolver: @escaping CubeResolver) -> CIImage {
        guard let sel = filterSelection,
              !sel.filterID.isEmpty,
              sel.strength > 0,
              cubeResolver(sel.filterID) != nil else {
            return image
        }
        return PipelineBuilder.applyLUT(sel, to: image, cubeResolver: cubeResolver)
    }

    func ciImage(from sampleBuffer: CMSampleBuffer) -> CIImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        return CIImage(cvPixelBuffer: pixelBuffer)
    }
}

extension CameraPreviewRenderer: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard var image = ciImage(from: sampleBuffer) else { return }

        // Lock device-orientation portrait so the preview is upright.
        if connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        // Mirror the *preview only* for the front camera — the captured photo
        // is unmirrored at the AVCapturePhoto layer (standard iOS behavior).
        if isFrontCamera {
            image = image.transformed(by: CGAffineTransform(scaleX: -1, y: 1)
                .translatedBy(x: -image.extent.width, y: 0))
        }

        let cooked = Self.applyLive(
            stack: currentStack(),
            to: image,
            cubeResolver: cubeResolver
        )
        os_unfair_lock_lock(snapshotLock)
        _latestSnapshot = cooked
        _latestRawSnapshot = image
        os_unfair_lock_unlock(snapshotLock)
    }
}

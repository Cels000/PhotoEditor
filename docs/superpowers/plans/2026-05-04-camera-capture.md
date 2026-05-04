# Camera Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Spec:** [docs/superpowers/specs/2026-05-04-camera-capture-design.md](../specs/2026-05-04-camera-capture-design.md)

**Goal:** Add a built-in camera that shows a live LUT preview of the currently-selected recipe ("see Portra 400 before pressing the shutter"), with capture saving the original full-res HEIC to Photos plus a Library item with the recipe pre-applied.

**Architecture:** A new `PhotoEditor/Camera/` directory with five units: `CameraSession` (AVCaptureSession wrapper), `CameraPreviewRenderer` (frame delegate + LUT apply), `CameraPreviewView` (MTKView SwiftUI bridge), `CameraCarouselThumbnailer` (2 Hz LUT thumbs), and `CameraView` + `CameraViewModel` (UI + orchestration). Live preview applies LUT-only via the existing `PipelineBuilder.applyLUT`; the captured Library item gets the recipe's *full* stack so the editor can fine-tune it later. Carousel data source = `RecipeStore.items` with a synthetic ORIGINAL slot prepended.

**Tech Stack:** Swift 5, SwiftUI, AVFoundation, CoreImage, Metal/MTKView, SwiftData, Photos, XCTest.

---

## Build & Iteration Notes (read first)

This project has **no local Swift toolchain** — all builds and tests run in CI on macOS Actions. Adapted TDD loop:

- Within a task, write the test *and* the implementation together (you cannot run tests locally).
- Commit at the end of each task with the project's existing commit-message style (lowercase prefix, e.g. `feat(camera): …`, `test(camera): …`).
- **Do NOT push between tasks.** Push at the user's direction (typically after a logical group of tasks completes) so CI runs once instead of N times.
- After the user pushes, the existing CLAUDE.md routine handles `gh run watch` + `ideviceinstaller`. Tasks that need on-device verification say so explicitly and list the exact manual checks.
- New files under `PhotoEditor/Camera/` are auto-picked up by XcodeGen because `project.yml` defines `sources: PhotoEditor` as a group. No `project.yml` edits needed for new files.

## File Structure

**Create (under `PhotoEditor/Camera/`):**
- `CameraSlot.swift` — value type unifying the synthetic ORIGINAL slot and `RecipeItem`-backed slots (so the carousel + view-model speak one type).
- `CameraPermissions.swift` — async helper for `AVCaptureDevice.requestAccess(for: .video)` plus a Settings-deeplink convenience.
- `CameraSession.swift` — `@MainActor` class owning `AVCaptureSession`. Configures inputs, video output, photo output. Public API: `start`/`stop`/`flipCamera`/`setFlashMode`/`setFocusPoint`/`setExposureCompensation`/`capturePhoto() async throws -> Data`.
- `CameraPreviewRenderer.swift` — `NSObject` conforming to `AVCaptureVideoDataOutputSampleBufferDelegate`. Receives frames, applies the selected `FilterSelection?` via `PipelineBuilder.applyLUT`, mirrors for front camera, holds the latest cooked `CIImage` in an atomic snapshot for the thumbnailer, and renders to a `MTKView`.
- `CameraPreviewView.swift` — `UIViewRepresentable` wrapping `MTKView`, wired to a `CameraPreviewRenderer`.
- `CameraCarouselThumbnailer.swift` — `@MainActor @Observable` class. 2 Hz timer reads the latest snapshot, applies each *visible* slot's LUT, publishes `[slotID: CGImage]`.
- `CameraViewModel.swift` — `@MainActor @Observable` orchestrator. Owns the session/renderer/thumbnailer/permissions, persists last-used recipe + flash + grid to `UserDefaults`, and runs the capture-save flow.
- `CameraView.swift` — full-screen SwiftUI modal composing the preview view, top bar, bottom carousel, shutter, and tap-to-focus/exposure overlays.

**Modify:**
- `PhotoEditor/Info.plist` — add `NSCameraUsageDescription`.
- `PhotoEditor/Library/LibraryStore.swift` — add `importFromCamera(assetID:stack:thumbnail:)`.
- `PhotoEditor/StudioTabView.swift` — overlay a floating camera FAB; present `CameraView` via `.fullScreenCover`.

**Tests (under `PhotoEditorTests/`):**
- `CameraSlotTests.swift`
- `LibraryStoreImportFromCameraTests.swift`
- `CameraPreviewRendererLUTTests.swift` (pure-CI logic, no AVCapture)
- `CameraCarouselThumbnailerVisibilityTests.swift`
- `CameraViewModelCaptureFlowTests.swift` (with stubbed dependencies)

Existing test patterns: `XCTest`, `@MainActor` test classes, `@testable import PhotoEditor` (see `PhotoEditorTests/RecipeApplyTests.swift` for a representative example).

---

## Task 1: Camera permission scaffolding

**Files:**
- Create: `PhotoEditor/Camera/CameraPermissions.swift`
- Modify: `PhotoEditor/Info.plist`

- [ ] **Step 1: Add `NSCameraUsageDescription` to Info.plist**

Edit `PhotoEditor/Info.plist`. Inside the top-level `<dict>` (e.g. just after the existing `NSPhotoLibraryUsageDescription` block), add:

```xml
<key>NSCameraUsageDescription</key>
<string>Photo Editor uses your camera so you can shoot through your favorite presets.</string>
```

- [ ] **Step 2: Create the permissions helper**

Create `PhotoEditor/Camera/CameraPermissions.swift`:

```swift
import AVFoundation
import UIKit

/// Thin wrapper around AVCaptureDevice authorization. Lives in Camera/ so the
/// rest of the app doesn't need to import AVFoundation just to gate a button.
enum CameraPermissions {

    static var status: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    /// Requests access if not yet determined; otherwise returns the current
    /// status synchronously. Safe to call from @MainActor — the AVF call is
    /// thread-safe and the completion fires on a background queue.
    @MainActor
    static func request() async -> AVAuthorizationStatus {
        switch status {
        case .notDetermined:
            _ = await AVCaptureDevice.requestAccess(for: .video)
            return status
        default:
            return status
        }
    }

    /// Open iOS Settings → app page so a denied user can grant access.
    @MainActor
    static func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add PhotoEditor/Info.plist PhotoEditor/Camera/CameraPermissions.swift
git commit -m "feat(camera): add NSCameraUsageDescription + CameraPermissions helper"
```

(No unit test — `AVCaptureDevice.authorizationStatus` is a global TCC query that returns whatever the host process state is; not meaningful to mock.)

---

## Task 2: `LibraryStore.importFromCamera` + tests

**Files:**
- Modify: `PhotoEditor/Library/LibraryStore.swift`
- Create: `PhotoEditorTests/LibraryStoreImportFromCameraTests.swift`

- [ ] **Step 1: Write the failing test**

Create `PhotoEditorTests/LibraryStoreImportFromCameraTests.swift`:

```swift
// Coverage for LibraryStore.importFromCamera — the camera-capture entry point.
// A captured photo arrives as (PHAsset.localIdentifier, full recipe stack,
// JPEG thumbnail bytes). The store must persist all three on a fresh
// LibraryItem and surface it via `items` at the front of the list.

import XCTest
import SwiftData
@testable import PhotoEditor

@MainActor
final class LibraryStoreImportFromCameraTests: XCTestCase {

    private func makeStore() throws -> LibraryStore {
        let schema = Schema([LibraryItem.self, RecipeItem.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        return LibraryStore(context: ModelContext(container))
    }

    func testImportFromCameraPersistsAssetIDAndStack() throws {
        let store = try makeStore()

        var stack = AdjustmentStack.identity
        stack.filter = FilterSelection(filterID: "cube.portra-400", strength: 1.0)
        stack.grain.intensity = 0.4

        let thumb = Data([0xFF, 0xD8, 0xFF, 0xD9])  // dummy JPEG marker bytes
        let item = store.importFromCamera(
            assetID: "ASSET-ID-123",
            stack: stack,
            thumbnail: thumb
        )

        XCTAssertEqual(item.sourceAssetID, "ASSET-ID-123")
        XCTAssertEqual(item.thumbnailData, thumb)
        XCTAssertEqual(item.adjustmentStack.filter?.filterID, "cube.portra-400")
        XCTAssertEqual(item.adjustmentStack.grain.intensity, 0.4, accuracy: 1e-9)
        XCTAssertEqual(store.items.first?.id, item.id, "newest-first ordering")
    }

    func testImportFromCameraWithIdentityStack() throws {
        let store = try makeStore()
        let item = store.importFromCamera(
            assetID: "ORIGINAL-ASSET",
            stack: .identity,
            thumbnail: nil
        )
        XCTAssertNil(item.adjustmentStack.filter)
        XCTAssertNil(item.thumbnailData)
        XCTAssertEqual(item.sourceAssetID, "ORIGINAL-ASSET")
    }
}
```

- [ ] **Step 2: Add the method**

In `PhotoEditor/Library/LibraryStore.swift`, append a new method to the `LibraryStore` class (just below the existing `save(stack:sourceAssetID:thumbnail:)`):

```swift
    /// Camera-capture entry point. Inserts a fresh LibraryItem whose stack
    /// reflects the recipe selected in the viewfinder at shutter time. The
    /// thumbnail is the cooked preview frame (JPEG bytes) — passing it in
    /// avoids a re-render via ThumbnailGenerator on first display.
    @discardableResult
    func importFromCamera(assetID: String,
                          stack: AdjustmentStack,
                          thumbnail: Data?) -> LibraryItem {
        save(stack: stack, sourceAssetID: assetID, thumbnail: thumbnail)
    }
```

- [ ] **Step 3: Commit**

```bash
git add PhotoEditor/Library/LibraryStore.swift PhotoEditorTests/LibraryStoreImportFromCameraTests.swift
git commit -m "feat(library): importFromCamera for camera-capture entry point"
```

---

## Task 3: `CameraSlot` value type + tests

**Files:**
- Create: `PhotoEditor/Camera/CameraSlot.swift`
- Create: `PhotoEditorTests/CameraSlotTests.swift`

The carousel needs to treat the synthetic ORIGINAL entry and `RecipeItem`-backed entries uniformly. `CameraSlot` is that abstraction.

- [ ] **Step 1: Write the failing test**

Create `PhotoEditorTests/CameraSlotTests.swift`:

```swift
import XCTest
import SwiftData
@testable import PhotoEditor

@MainActor
final class CameraSlotTests: XCTestCase {

    func testOriginalSlotIsIdentityStack() {
        let slot = CameraSlot.original
        XCTAssertEqual(slot.id, "__original__")
        XCTAssertEqual(slot.displayName, "ORIGINAL")
        XCTAssertNil(slot.stack.filter)
        XCTAssertEqual(slot.filterSelection, nil)
    }

    func testRecipeSlotExposesRecipeStackAndFilter() {
        var stack = AdjustmentStack.identity
        stack.filter = FilterSelection(filterID: "cube.portra-400", strength: 0.85)
        stack.grain.intensity = 0.3

        let recipe = RecipeItem(name: "Portra 400")
        recipe.adjustmentStack = stack

        let slot = CameraSlot.recipe(recipe)
        XCTAssertEqual(slot.id, recipe.id.uuidString)
        XCTAssertEqual(slot.displayName, "Portra 400")
        XCTAssertEqual(slot.stack.filter?.filterID, "cube.portra-400")
        XCTAssertEqual(slot.filterSelection?.filterID, "cube.portra-400")
        XCTAssertEqual(slot.filterSelection?.strength, 0.85, accuracy: 1e-9)
    }

    func testBuildSlotsPrependsOriginal() {
        let r1 = RecipeItem(name: "Portra 400")
        let r2 = RecipeItem(name: "Tri-X 400")
        let slots = CameraSlot.build(from: [r1, r2])
        XCTAssertEqual(slots.count, 3)
        XCTAssertEqual(slots[0].id, "__original__")
        XCTAssertEqual(slots[1].displayName, "Portra 400")
        XCTAssertEqual(slots[2].displayName, "Tri-X 400")
    }
}
```

- [ ] **Step 2: Implement `CameraSlot`**

Create `PhotoEditor/Camera/CameraSlot.swift`:

```swift
import Foundation

/// Carousel slot. Either the synthetic ORIGINAL entry (no LUT, identity
/// stack) or a real RecipeItem from RecipeStore. Wraps both in one value type
/// so the view-model and carousel UI don't branch on type everywhere.
enum CameraSlot: Identifiable, Hashable {
    case original
    case recipe(RecipeItem)

    static let originalID = "__original__"

    var id: String {
        switch self {
        case .original:           return Self.originalID
        case .recipe(let r):      return r.id.uuidString
        }
    }

    var displayName: String {
        switch self {
        case .original:           return "ORIGINAL"
        case .recipe(let r):      return r.name
        }
    }

    /// Full stack baked into the captured Library item. ORIGINAL → identity.
    var stack: AdjustmentStack {
        switch self {
        case .original:           return .identity
        case .recipe(let r):      return r.adjustmentStack
        }
    }

    /// Just the LUT portion — what the live preview applies per frame.
    var filterSelection: FilterSelection? {
        switch self {
        case .original:           return nil
        case .recipe(let r):      return r.adjustmentStack.filter
        }
    }

    /// Build the carousel-order list: ORIGINAL first, then recipes in the
    /// order RecipeStore presents them (sortOrder ascending).
    static func build(from recipes: [RecipeItem]) -> [CameraSlot] {
        [.original] + recipes.map { .recipe($0) }
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add PhotoEditor/Camera/CameraSlot.swift PhotoEditorTests/CameraSlotTests.swift
git commit -m "feat(camera): CameraSlot value type unifies ORIGINAL + recipes"
```

---

## Task 4: `CameraSession` (AVFoundation wrapper)

**Files:**
- Create: `PhotoEditor/Camera/CameraSession.swift`

No unit test — `AVCaptureSession` requires real hardware. Verified on device after Task 12.

- [ ] **Step 1: Implement `CameraSession`**

Create `PhotoEditor/Camera/CameraSession.swift`:

```swift
import AVFoundation
import CoreMedia
import Foundation
import UIKit

enum CameraPosition { case back, front }

enum CameraError: Error {
    case noCameraAvailable
    case noPhotoOutput
    case captureFailed(Error?)
}

/// Wraps AVCaptureSession. Owns inputs (back/front), the video data output
/// for live frames, and the photo output for stills. All session mutations
/// run on a serial sessionQueue per Apple's guidance, while the public API
/// is @MainActor so SwiftUI can call it ergonomically.
@MainActor
final class CameraSession: NSObject {

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.photoeditor.camera.session")
    private(set) var position: CameraPosition = .back

    private var videoInput: AVCaptureDeviceInput?
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()

    /// Set this BEFORE `start()` so the renderer receives sample buffers.
    weak var sampleBufferDelegate: AVCaptureVideoDataOutputSampleBufferDelegate?
    var sampleBufferQueue: DispatchQueue = DispatchQueue(label: "com.photoeditor.camera.preview")

    private var photoContinuation: CheckedContinuation<Data, Error>?

    func start() {
        sessionQueue.async { [weak self] in
            self?.configureIfNeeded()
            if self?.session.isRunning == false { self?.session.startRunning() }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            if self?.session.isRunning == true { self?.session.stopRunning() }
        }
    }

    private func configureIfNeeded() {
        guard videoInput == nil else { return }   // first-time only
        session.beginConfiguration()
        session.sessionPreset = .photo            // 4:3 native
        attachInput(position: position)

        videoOutput.setSampleBufferDelegate(sampleBufferDelegate, queue: sampleBufferQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }

        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
        photoOutput.maxPhotoQualityPrioritization = .quality

        session.commitConfiguration()
    }

    private func attachInput(position: CameraPosition) {
        let avPosition: AVCaptureDevice.Position = position == .back ? .back : .front
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: avPosition),
              let input = try? AVCaptureDeviceInput(device: device) else {
            return
        }
        if let existing = videoInput { session.removeInput(existing) }
        if session.canAddInput(input) {
            session.addInput(input)
            videoInput = input
            self.position = position
        }
    }

    func flipCamera() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let next: CameraPosition = self.position == .back ? .front : .back
            self.session.beginConfiguration()
            self.attachInput(position: next)
            self.session.commitConfiguration()
        }
    }

    func setFlashMode(_ mode: AVCaptureDevice.FlashMode) {
        // Flash is set per-photo via AVCapturePhotoSettings; remember the choice.
        currentFlashMode = mode
    }

    private var currentFlashMode: AVCaptureDevice.FlashMode = .auto

    /// Normalized 0…1 focus point in the *device's* coordinate system (origin
    /// top-left when the device is in portrait — caller is responsible for
    /// the orientation conversion when mapping from a tap location).
    func setFocusPoint(_ point: CGPoint) {
        sessionQueue.async { [weak self] in
            guard let device = self?.videoInput?.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = point
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = point
                    device.exposureMode = .autoExpose
                }
                device.unlockForConfiguration()
            } catch {
                // No-op: focus failures are non-fatal during shooting.
            }
        }
    }

    /// EV in the device's supported range (typically -2…+2).
    func setExposureCompensation(_ ev: Float) {
        sessionQueue.async { [weak self] in
            guard let device = self?.videoInput?.device else { return }
            do {
                try device.lockForConfiguration()
                let clamped = max(device.minExposureTargetBias,
                                  min(device.maxExposureTargetBias, ev))
                device.setExposureTargetBias(clamped, completionHandler: nil)
                device.unlockForConfiguration()
            } catch {}
        }
    }

    var hasFrontCamera: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil
    }

    var hasFlash: Bool {
        videoInput?.device.hasFlash ?? false
    }

    /// Capture a single HEIC photo at full sensor resolution. Resumes the
    /// returned async value from the AVCapturePhotoCaptureDelegate callback.
    func capturePhoto() async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            sessionQueue.async { [weak self] in
                guard let self else {
                    cont.resume(throwing: CameraError.noPhotoOutput)
                    return
                }
                let settings = AVCapturePhotoSettings(format: [
                    AVVideoCodecKey: AVVideoCodecType.hevc
                ])
                if self.photoOutput.supportedFlashModes.contains(self.currentFlashMode) {
                    settings.flashMode = self.currentFlashMode
                }
                settings.photoQualityPrioritization = .quality
                Task { @MainActor in
                    self.photoContinuation = cont
                    self.photoOutput.capturePhoto(with: settings, delegate: self)
                }
            }
        }
    }
}

extension CameraSession: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        Task { @MainActor in
            defer { self.photoContinuation = nil }
            if let error {
                self.photoContinuation?.resume(throwing: CameraError.captureFailed(error))
                return
            }
            guard let data = photo.fileDataRepresentation() else {
                self.photoContinuation?.resume(throwing: CameraError.captureFailed(nil))
                return
            }
            self.photoContinuation?.resume(returning: data)
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add PhotoEditor/Camera/CameraSession.swift
git commit -m "feat(camera): AVCaptureSession wrapper with photo + video output"
```

---

## Task 5: `CameraPreviewRenderer` + LUT-stage tests

**Files:**
- Create: `PhotoEditor/Camera/CameraPreviewRenderer.swift`
- Create: `PhotoEditorTests/CameraPreviewRendererLUTTests.swift`

- [ ] **Step 1: Write the failing test**

The renderer's frame-handling depends on `CMSampleBuffer`s we can't synthesize easily, but the *LUT-application path* is pure CIImage and testable. Test that path through a public helper.

Create `PhotoEditorTests/CameraPreviewRendererLUTTests.swift`:

```swift
import XCTest
import CoreImage
@testable import PhotoEditor

final class CameraPreviewRendererLUTTests: XCTestCase {

    private func solidImage() -> CIImage {
        CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
            .cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
    }

    func testNilFilterSelectionReturnsInputUnchanged() {
        let input = solidImage()
        let out = CameraPreviewRenderer.applyLUT(
            filterSelection: nil,
            to: input,
            cubeResolver: { _ in nil }
        )
        XCTAssertEqual(out.extent, input.extent)
        // Identity passthrough should yield the same CIImage instance.
        XCTAssertTrue(out === input)
    }

    func testMissingCubeFallsThroughToIdentity() {
        let input = solidImage()
        let sel = FilterSelection(filterID: "does-not-exist", strength: 1.0)
        let out = CameraPreviewRenderer.applyLUT(
            filterSelection: sel,
            to: input,
            cubeResolver: { _ in nil }
        )
        XCTAssertTrue(out === input)
    }

    func testZeroStrengthReturnsInputUnchanged() {
        let input = solidImage()
        let sel = FilterSelection(filterID: "anything", strength: 0)
        let out = CameraPreviewRenderer.applyLUT(
            filterSelection: sel,
            to: input,
            cubeResolver: { _ in
                // Identity cube — supplying a non-nil cube ensures the bypass
                // is driven by `strength: 0`, not by missing cube data.
                ColorCubeData.identity()
            }
        )
        XCTAssertTrue(out === input)
    }
}
```

- [ ] **Step 2: Implement `CameraPreviewRenderer`**

Create `PhotoEditor/Camera/CameraPreviewRenderer.swift`:

```swift
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

    /// The current carousel-selected slot's filter, or nil for ORIGINAL.
    /// Mutated from MainActor (CameraViewModel) — atomic-set is sufficient
    /// since reads on the capture queue tolerate one-frame staleness.
    private var _filterSelection: FilterSelection?
    private let filterLock = os_unfair_lock_t.allocate(capacity: 1)

    /// The current camera position. Used to mirror the front-camera preview.
    var isFrontCamera: Bool = false

    /// Latest cooked CIImage (ready for the MTKView and the thumbnailer).
    private var _latestSnapshot: CIImage?
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
        filterLock.initialize(to: os_unfair_lock())
        snapshotLock.initialize(to: os_unfair_lock())
        super.init()
    }

    deinit {
        filterLock.deinitialize(count: 1); filterLock.deallocate()
        snapshotLock.deinitialize(count: 1); snapshotLock.deallocate()
    }

    func setFilterSelection(_ sel: FilterSelection?) {
        os_unfair_lock_lock(filterLock)
        _filterSelection = sel
        os_unfair_lock_unlock(filterLock)
    }

    func currentFilterSelection() -> FilterSelection? {
        os_unfair_lock_lock(filterLock); defer { os_unfair_lock_unlock(filterLock) }
        return _filterSelection
    }

    /// Read by the thumbnailer on its own queue; safe to call from anywhere.
    func latestSnapshot() -> CIImage? {
        os_unfair_lock_lock(snapshotLock); defer { os_unfair_lock_unlock(snapshotLock) }
        return _latestSnapshot
    }

    /// Pure helper — testable in isolation without an AVCapture pipeline.
    /// Public-static so tests can call it directly.
    static func applyLUT(filterSelection: FilterSelection?,
                         to image: CIImage,
                         cubeResolver: CubeResolver) -> CIImage {
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

        let cooked = Self.applyLUT(
            filterSelection: currentFilterSelection(),
            to: image,
            cubeResolver: cubeResolver
        )
        os_unfair_lock_lock(snapshotLock)
        _latestSnapshot = cooked
        os_unfair_lock_unlock(snapshotLock)
    }
}
```

If the test refers to `ColorCubeData(rawData:)` and the existing init differs, update the test only — keep the renderer unchanged.

- [ ] **Step 3: Commit**

```bash
git add PhotoEditor/Camera/CameraPreviewRenderer.swift PhotoEditorTests/CameraPreviewRendererLUTTests.swift
git commit -m "feat(camera): preview renderer applies LUT-only per frame"
```

---

## Task 6: `CameraPreviewView` (MTKView SwiftUI bridge)

**Files:**
- Create: `PhotoEditor/Camera/CameraPreviewView.swift`

No unit test — Metal display verified on device.

- [ ] **Step 1: Implement the bridge**

Create `PhotoEditor/Camera/CameraPreviewView.swift`:

```swift
import CoreImage
import Metal
import MetalKit
import SwiftUI

/// MTKView-backed live preview. Pulls the latest cooked CIImage from the
/// renderer on each draw call and blits it via the renderer's CIContext.
struct CameraPreviewView: UIViewRepresentable {

    let renderer: CameraPreviewRenderer

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm
        view.contentMode = .scaleAspectFit
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 30
        view.delegate = context.coordinator
        context.coordinator.renderer = renderer
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.renderer = renderer
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(renderer: renderer)
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        var renderer: CameraPreviewRenderer
        private let commandQueue: MTLCommandQueue?
        private let outputColorSpace = CGColorSpace(name: CGColorSpace.displayP3)!

        init(renderer: CameraPreviewRenderer) {
            self.renderer = renderer
            self.commandQueue = MTLCreateSystemDefaultDevice()?.makeCommandQueue()
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let commandBuffer = commandQueue?.makeCommandBuffer(),
                  let image = renderer.latestSnapshot() else { return }

            // Aspect-fit the source into the drawable.
            let drawableSize = view.drawableSize
            let scale = min(drawableSize.width / image.extent.width,
                            drawableSize.height / image.extent.height)
            let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let dx = (drawableSize.width - scaled.extent.width) / 2
            let dy = (drawableSize.height - scaled.extent.height) / 2
            let positioned = scaled.transformed(by: CGAffineTransform(translationX: dx, y: dy))

            // Clear background to canvas-black for letterbox bands.
            let bg = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            view.clearColor = bg

            // Render via CIContext fast path.
            renderer.ciContext.render(
                positioned,
                to: drawable.texture,
                commandBuffer: commandBuffer,
                bounds: CGRect(origin: .zero, size: drawableSize),
                colorSpace: outputColorSpace
            )

            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}

```

(`renderer.ciContext` resolves because Task 5 already declared it `internal let`.)

- [ ] **Step 2: Commit**

```bash
git add PhotoEditor/Camera/CameraPreviewView.swift
git commit -m "feat(camera): MTKView SwiftUI bridge for live preview"
```

---

## Task 7: `CameraCarouselThumbnailer` + visibility tests

**Files:**
- Create: `PhotoEditor/Camera/CameraCarouselThumbnailer.swift`
- Create: `PhotoEditorTests/CameraCarouselThumbnailerVisibilityTests.swift`

- [ ] **Step 1: Write the failing test**

Create `PhotoEditorTests/CameraCarouselThumbnailerVisibilityTests.swift`:

```swift
import XCTest
@testable import PhotoEditor

@MainActor
final class CameraCarouselThumbnailerVisibilityTests: XCTestCase {

    func testVisibleSlotIDsFiltersOutOffscreen() {
        let r1 = RecipeItem(name: "A")
        let r2 = RecipeItem(name: "B")
        let r3 = RecipeItem(name: "C")
        let slots: [CameraSlot] = [.original, .recipe(r1), .recipe(r2), .recipe(r3)]

        let thumbnailer = CameraCarouselThumbnailer(
            renderer: nil,
            cubeResolver: { _ in nil }
        )
        thumbnailer.setVisibleSlotIDs([CameraSlot.originalID, r2.id.uuidString])
        let visible = thumbnailer.slotsToRender(from: slots)
        XCTAssertEqual(visible.map { $0.id },
                       [CameraSlot.originalID, r2.id.uuidString])
    }

    func testEmptyVisibilityRendersNothing() {
        let r1 = RecipeItem(name: "A")
        let thumbnailer = CameraCarouselThumbnailer(
            renderer: nil,
            cubeResolver: { _ in nil }
        )
        thumbnailer.setVisibleSlotIDs([])
        let visible = thumbnailer.slotsToRender(from: [.original, .recipe(r1)])
        XCTAssertTrue(visible.isEmpty)
    }
}
```

- [ ] **Step 2: Implement the thumbnailer**

Create `PhotoEditor/Camera/CameraCarouselThumbnailer.swift`:

```swift
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
```

- [ ] **Step 3: Commit**

```bash
git add PhotoEditor/Camera/CameraCarouselThumbnailer.swift PhotoEditorTests/CameraCarouselThumbnailerVisibilityTests.swift
git commit -m "feat(camera): 2 Hz LUT-thumbnail carousel renderer (visible-only)"
```

---

## Task 8: `CameraViewModel` + capture-flow tests

**Files:**
- Create: `PhotoEditor/Camera/CameraViewModel.swift`
- Create: `PhotoEditorTests/CameraViewModelCaptureFlowTests.swift`

- [ ] **Step 1: Write the failing test**

The capture flow has two halves: (a) HEIC bytes → Photos write → asset ID, and (b) asset ID + slot.stack → LibraryStore.importFromCamera. (a) requires Photos which we can't unit-test cleanly; (b) is pure logic — test it by injecting a stub PhotosWriter.

Create `PhotoEditorTests/CameraViewModelCaptureFlowTests.swift`:

```swift
import XCTest
import SwiftData
@testable import PhotoEditor

@MainActor
final class CameraViewModelCaptureFlowTests: XCTestCase {

    private func makeStores() throws -> (LibraryStore, RecipeStore) {
        let schema = Schema([LibraryItem.self, RecipeItem.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        let ctx = ModelContext(container)
        return (LibraryStore(context: ctx), RecipeStore(context: ctx))
    }

    func testCaptureWithRecipeSlotPersistsFullStack() async throws {
        let (libraryStore, recipeStore) = try makeStores()

        var stack = AdjustmentStack.identity
        stack.filter = FilterSelection(filterID: "cube.portra-400", strength: 1.0)
        stack.grain.intensity = 0.5
        let recipe = recipeStore.save(name: "Portra 400", stack: stack, thumbnail: nil)

        let vm = CameraViewModel(
            libraryStore: libraryStore,
            recipeStore: recipeStore,
            cubeResolver: { _ in nil },
            photosWriter: StubPhotosWriter(returning: "ASSET-A"),
            heicProvider: { Data([0x00]) }
        )
        vm.selectSlot(.recipe(recipe))

        try await vm.capture()

        XCTAssertEqual(libraryStore.items.count, 1)
        let item = libraryStore.items[0]
        XCTAssertEqual(item.sourceAssetID, "ASSET-A")
        XCTAssertEqual(item.adjustmentStack.filter?.filterID, "cube.portra-400")
        XCTAssertEqual(item.adjustmentStack.grain.intensity, 0.5, accuracy: 1e-9)
    }

    func testCaptureWithOriginalSlotPersistsIdentityStack() async throws {
        let (libraryStore, recipeStore) = try makeStores()
        let vm = CameraViewModel(
            libraryStore: libraryStore,
            recipeStore: recipeStore,
            cubeResolver: { _ in nil },
            photosWriter: StubPhotosWriter(returning: "ASSET-B"),
            heicProvider: { Data([0x00]) }
        )
        vm.selectSlot(.original)

        try await vm.capture()

        XCTAssertEqual(libraryStore.items.count, 1)
        let item = libraryStore.items[0]
        XCTAssertNil(item.adjustmentStack.filter)
    }

    func testSelectSlotPersistsLastUsedID() throws {
        let r = RecipeItem(name: "x")
        let suite = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let (libraryStore, recipeStore) = try makeStores()
        let vm = CameraViewModel(
            libraryStore: libraryStore,
            recipeStore: recipeStore,
            cubeResolver: { _ in nil },
            photosWriter: StubPhotosWriter(returning: ""),
            heicProvider: { Data() },
            userDefaults: defaults
        )
        vm.selectSlot(.recipe(r))
        XCTAssertEqual(defaults.string(forKey: CameraViewModel.lastSlotKey),
                       r.id.uuidString)

        vm.selectSlot(.original)
        XCTAssertEqual(defaults.string(forKey: CameraViewModel.lastSlotKey),
                       CameraSlot.originalID)
    }
}

private struct StubPhotosWriter: PhotosWriter {
    let returning: String
    func writeHEIC(_ data: Data) async throws -> String { returning }
}
```

- [ ] **Step 2: Implement `CameraViewModel`**

Create `PhotoEditor/Camera/CameraViewModel.swift`:

```swift
import AVFoundation
import CoreImage
import Foundation
import Observation
import Photos
import UIKit

/// Side-effect injection seam so the view-model is unit-testable without
/// hitting the Photos library.
protocol PhotosWriter {
    /// Write a HEIC blob to the user's photo library and return the new
    /// PHAsset.localIdentifier.
    func writeHEIC(_ data: Data) async throws -> String
}

struct DefaultPhotosWriter: PhotosWriter {
    func writeHEIC(_ data: Data) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            var assetID: String?
            PHPhotoLibrary.shared().performChanges {
                let req = PHAssetCreationRequest.forAsset()
                let opts = PHAssetResourceCreationOptions()
                opts.uniformTypeIdentifier = "public.heic"
                req.addResource(with: .photo, data: data, options: opts)
                assetID = req.placeholderForCreatedAsset?.localIdentifier
            } completionHandler: { ok, err in
                if let err { cont.resume(throwing: err); return }
                guard ok, let id = assetID else {
                    cont.resume(throwing: CameraError.captureFailed(nil))
                    return
                }
                cont.resume(returning: id)
            }
        }
    }
}

@MainActor
@Observable
final class CameraViewModel {

    // MARK: - Persistence keys
    static let lastSlotKey = "camera.lastRecipeID"
    static let flashKey    = "camera.flashMode"
    static let gridKey     = "camera.gridEnabled"

    // MARK: - Dependencies
    let libraryStore: LibraryStore
    let recipeStore: RecipeStore
    let cubeResolver: CubeResolver
    let photosWriter: PhotosWriter
    let heicProvider: () async throws -> Data
    private let userDefaults: UserDefaults

    // MARK: - State
    private(set) var slots: [CameraSlot] = []
    private(set) var selectedSlotID: String = CameraSlot.originalID
    var flashMode: AVCaptureDevice.FlashMode = .auto {
        didSet { userDefaults.set(flashMode.rawValue, forKey: Self.flashKey) }
    }
    var gridEnabled: Bool = false {
        didSet { userDefaults.set(gridEnabled, forKey: Self.gridKey) }
    }
    var errorMessage: String?
    var captureInFlight: Bool = false

    // MARK: - Init
    init(libraryStore: LibraryStore,
         recipeStore: RecipeStore,
         cubeResolver: @escaping CubeResolver,
         photosWriter: PhotosWriter = DefaultPhotosWriter(),
         heicProvider: (@escaping () async throws -> Data) = { throw CameraError.noPhotoOutput },
         userDefaults: UserDefaults = .standard) {
        self.libraryStore = libraryStore
        self.recipeStore = recipeStore
        self.cubeResolver = cubeResolver
        self.photosWriter = photosWriter
        self.heicProvider = heicProvider
        self.userDefaults = userDefaults

        self.slots = CameraSlot.build(from: recipeStore.items)
        self.selectedSlotID = userDefaults.string(forKey: Self.lastSlotKey) ?? CameraSlot.originalID
        if let raw = userDefaults.object(forKey: Self.flashKey) as? Int,
           let mode = AVCaptureDevice.FlashMode(rawValue: raw) {
            self.flashMode = mode
        }
        self.gridEnabled = userDefaults.bool(forKey: Self.gridKey)

        // If the persisted slot ID is no longer present (recipe deleted), fall
        // back to ORIGINAL.
        if !slots.contains(where: { $0.id == selectedSlotID }) {
            selectedSlotID = CameraSlot.originalID
        }
    }

    // MARK: - Public API
    var selectedSlot: CameraSlot {
        slots.first(where: { $0.id == selectedSlotID }) ?? .original
    }

    func selectSlot(_ slot: CameraSlot) {
        selectedSlotID = slot.id
        userDefaults.set(slot.id, forKey: Self.lastSlotKey)
    }

    /// Capture flow: get HEIC bytes → write to Photos → import to Library
    /// with the selected slot's full stack.
    func capture() async throws {
        guard !captureInFlight else { return }
        captureInFlight = true
        defer { captureInFlight = false }

        let bytes = try await heicProvider()
        let assetID = try await photosWriter.writeHEIC(bytes)
        let slot = selectedSlot
        // Library insert + thumbnail bytes (nil for now — wired in Task 11
        // when the cooked preview frame is available to the view-model).
        _ = libraryStore.importFromCamera(
            assetID: assetID,
            stack: slot.stack,
            thumbnail: nil
        )
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add PhotoEditor/Camera/CameraViewModel.swift PhotoEditorTests/CameraViewModelCaptureFlowTests.swift
git commit -m "feat(camera): view-model orchestrates capture + persists slot/flash/grid"
```

---

## Task 9: `CameraView` chrome — top bar + shutter

**Files:**
- Create: `PhotoEditor/Camera/CameraView.swift` (initial scaffold)

No unit test — verified on device after Task 12.

- [ ] **Step 1: Scaffold the view with top bar + shutter only**

Create `PhotoEditor/Camera/CameraView.swift`:

```swift
import AVFoundation
import SwiftUI

/// Full-screen camera modal. Composed of preview, top bar, bottom carousel,
/// shutter, and tap-to-focus overlays. This file scaffolds the chrome;
/// preview composition lands in Task 10, carousel UI in Task 11.
struct CameraView: View {

    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: CameraViewModel
    let session: CameraSession

    @State private var permissionStatus: AVAuthorizationStatus = .notDetermined

    var body: some View {
        ZStack {
            Theme.Colors.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer()
                shutterRow
            }
        }
        .task {
            permissionStatus = await CameraPermissions.request()
            if permissionStatus == .authorized {
                session.start()
            }
        }
        .onDisappear { session.stop() }
        .alert("Camera access needed", isPresented: Binding(
            get: { permissionStatus == .denied || permissionStatus == .restricted },
            set: { _ in })) {
            Button("Open Settings") { CameraPermissions.openSettings() }
            Button("Close", role: .cancel) { dismiss() }
        } message: {
            Text("Enable camera access in Settings to shoot through your presets.")
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .medium))
            }
            Spacer()
            if session.hasFlash {
                Button { cycleFlash() } label: {
                    Image(systemName: flashIconName)
                        .font(.system(size: 18, weight: .medium))
                }
            }
            Button { viewModel.gridEnabled.toggle() } label: {
                Image(systemName: viewModel.gridEnabled ? "grid" : "grid")
                    .font(.system(size: 18, weight: .medium))
                    .opacity(viewModel.gridEnabled ? 1.0 : 0.5)
            }
            if session.hasFrontCamera {
                Button { session.flipCamera() } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.system(size: 18, weight: .medium))
                }
            }
        }
        .frame(height: 44)
        .padding(.horizontal, Theme.Spacing.lg)
        .foregroundStyle(Theme.Colors.text)
    }

    private var flashIconName: String {
        switch viewModel.flashMode {
        case .on:   return "bolt.fill"
        case .off:  return "bolt.slash.fill"
        default:    return "bolt.badge.a.fill"
        }
    }

    private func cycleFlash() {
        let next: AVCaptureDevice.FlashMode
        switch viewModel.flashMode {
        case .auto: next = .on
        case .on:   next = .off
        default:    next = .auto
        }
        viewModel.flashMode = next
        session.setFlashMode(next)
    }

    // MARK: - Shutter row

    private var shutterRow: some View {
        ZStack {
            Button {
                Task { await runCapture() }
            } label: {
                Circle()
                    .fill(Color.white)
                    .frame(width: 64, height: 64)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 4)
                            .frame(width: 72, height: 72)
                    )
            }
            .disabled(viewModel.captureInFlight)
            .opacity(viewModel.captureInFlight ? 0.6 : 1.0)
        }
        .frame(height: 96)
        .padding(.bottom, Theme.Spacing.lg)
    }

    private func runCapture() async {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        do { try await viewModel.capture() }
        catch { viewModel.errorMessage = "Couldn't save photo." }
    }
}
```

- [ ] **Step 2: Wire HEIC provider to the session**

Currently `CameraViewModel.heicProvider` defaults to throwing. The real wiring is to pass `{ try await session.capturePhoto() }` from the call site (the view). Add to `CameraView`:

In the `body` `.task { … }` block, after permission grant, do:

```swift
viewModel.bindHEIC(provider: { try await session.capturePhoto() })
viewModel.bindFront(isFront: { session.position == .front })
```

…and add these methods to `CameraViewModel`:

```swift
    private var heicProviderOverride: (() async throws -> Data)?
    private var isFrontProvider: (() -> Bool)?

    func bindHEIC(provider: @escaping () async throws -> Data) {
        heicProviderOverride = provider
    }

    func bindFront(isFront: @escaping () -> Bool) {
        isFrontProvider = isFront
    }
```

…and change `capture()` to use the override when present:

```swift
        let bytes = try await (heicProviderOverride ?? heicProvider)()
```

- [ ] **Step 3: Commit**

```bash
git add PhotoEditor/Camera/CameraView.swift PhotoEditor/Camera/CameraViewModel.swift
git commit -m "feat(camera): CameraView chrome — top bar, flash/grid/flip, shutter"
```

---

## Task 10: `CameraView` preview + tap-to-focus + exposure slider + grid

**Files:**
- Modify: `PhotoEditor/Camera/CameraView.swift`

- [ ] **Step 1: Add preview state to the view**

Replace the body of `CameraView` (everything from `var body: some View {` through the matching `}`) with the version that composes the preview view + overlays. Keep the `topBar`, `shutterRow`, and helpers from Task 9.

```swift
    @State private var renderer: CameraPreviewRenderer?
    @State private var focusPoint: CGPoint?
    @State private var exposureBias: Float = 0
    @State private var showExposureSlider: Bool = false
    @State private var hideSliderTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Theme.Colors.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                if let renderer {
                    previewArea(renderer: renderer)
                        .aspectRatio(3/4, contentMode: .fit)
                }
                Spacer(minLength: 0)
                shutterRow
            }
        }
        .task {
            permissionStatus = await CameraPermissions.request()
            guard permissionStatus == .authorized else { return }
            let r = CameraPreviewRenderer(cubeResolver: viewModel.cubeResolver)
            r.setFilterSelection(viewModel.selectedSlot.filterSelection)
            r.isFrontCamera = (session.position == .front)
            session.sampleBufferDelegate = r
            renderer = r
            viewModel.bindHEIC(provider: { try await session.capturePhoto() })
            viewModel.bindFront(isFront: { session.position == .front })
            session.start()
        }
        .onChange(of: viewModel.selectedSlotID) { _, _ in
            renderer?.setFilterSelection(viewModel.selectedSlot.filterSelection)
        }
        .onDisappear { session.stop() }
        .alert("Camera access needed", isPresented: Binding(
            get: { permissionStatus == .denied || permissionStatus == .restricted },
            set: { _ in })) {
            Button("Open Settings") { CameraPermissions.openSettings() }
            Button("Close", role: .cancel) { dismiss() }
        } message: {
            Text("Enable camera access in Settings to shoot through your presets.")
        }
    }

    @ViewBuilder
    private func previewArea(renderer: CameraPreviewRenderer) -> some View {
        GeometryReader { geo in
            ZStack {
                CameraPreviewView(renderer: renderer)
                if viewModel.gridEnabled {
                    gridOverlay
                }
                if let p = focusPoint {
                    Circle()
                        .stroke(Color.white, lineWidth: 1.5)
                        .frame(width: 64, height: 64)
                        .position(p)
                        .transition(.opacity)
                }
                if showExposureSlider {
                    HStack {
                        Spacer()
                        exposureSlider
                            .frame(width: 32, height: 200)
                            .padding(.trailing, Theme.Spacing.md)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                handleTap(at: location, in: geo.size)
            }
        }
    }

    private var gridOverlay: some View {
        GeometryReader { geo in
            Path { p in
                let w = geo.size.width, h = geo.size.height
                p.move(to: CGPoint(x: w/3, y: 0));    p.addLine(to: CGPoint(x: w/3,   y: h))
                p.move(to: CGPoint(x: 2*w/3, y: 0));  p.addLine(to: CGPoint(x: 2*w/3, y: h))
                p.move(to: CGPoint(x: 0, y: h/3));    p.addLine(to: CGPoint(x: w,     y: h/3))
                p.move(to: CGPoint(x: 0, y: 2*h/3));  p.addLine(to: CGPoint(x: w,     y: 2*h/3))
            }
            .stroke(Color.white.opacity(0.3), lineWidth: 1)
        }
    }

    private var exposureSlider: some View {
        VStack {
            Image(systemName: "sun.max.fill").foregroundStyle(.white)
            Slider(value: Binding(
                get: { Double(exposureBias) },
                set: { newVal in
                    exposureBias = Float(newVal)
                    session.setExposureCompensation(exposureBias)
                    rescheduleSliderHide()
                }),
                in: -2...2)
                .rotationEffect(.degrees(-90))
                .frame(width: 200)
                .tint(.white)
            Text(String(format: "%+.1f", exposureBias))
                .font(.caption2).foregroundStyle(.white)
        }
    }

    private func handleTap(at location: CGPoint, in size: CGSize) {
        focusPoint = location
        let nx = location.x / size.width
        let ny = location.y / size.height
        session.setFocusPoint(CGPoint(x: nx, y: ny))
        showExposureSlider = true
        rescheduleSliderHide()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            withAnimation { focusPoint = nil }
        }
    }

    private func rescheduleSliderHide() {
        hideSliderTask?.cancel()
        hideSliderTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled { withAnimation { showExposureSlider = false } }
        }
    }
```

- [ ] **Step 2: Commit**

```bash
git add PhotoEditor/Camera/CameraView.swift
git commit -m "feat(camera): live preview, tap-to-focus, exposure slider, grid overlay"
```

---

## Task 11: `CameraView` bottom carousel

**Files:**
- Modify: `PhotoEditor/Camera/CameraView.swift`
- Modify: `PhotoEditor/Camera/CameraViewModel.swift`

- [ ] **Step 1: Add a thumbnailer to the view-model**

In `CameraViewModel`, add stored property and lifecycle methods:

```swift
    var thumbnailer: CameraCarouselThumbnailer?

    func attachThumbnailer(renderer: CameraPreviewRenderer) {
        let t = CameraCarouselThumbnailer(renderer: renderer, cubeResolver: cubeResolver)
        t.setSlots(slots)
        thumbnailer = t
        t.start()
    }

    func detachThumbnailer() {
        thumbnailer?.stop()
        thumbnailer = nil
    }
```

- [ ] **Step 2: Add carousel UI**

In `CameraView.swift`, replace `shutterRow` with a `bottomDeck` that includes both the carousel and the shutter. Add this property and view:

```swift
    private var bottomDeck: some View {
        VStack(spacing: Theme.Spacing.sm) {
            carousel
            Text(viewModel.selectedSlot.displayName.uppercased())
                .font(Theme.Typography.label)
                .tracking(2)
                .foregroundStyle(Theme.Colors.text)
                .frame(height: 16)
            shutterRow
        }
    }

    @ViewBuilder
    private var carousel: some View {
        let edge: CGFloat = 72
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.slots) { slot in
                        carouselCell(for: slot, edge: edge)
                            .id(slot.id)
                            .onAppear { addVisible(slot.id) }
                            .onDisappear { removeVisible(slot.id) }
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .frame(height: edge + 8)
            .onAppear {
                proxy.scrollTo(viewModel.selectedSlotID, anchor: .center)
            }
        }
    }

    private func carouselCell(for slot: CameraSlot, edge: CGFloat) -> some View {
        let isSelected = slot.id == viewModel.selectedSlotID
        let cg = viewModel.thumbnailer?.thumbnails[slot.id]
        return Button {
            viewModel.selectSlot(slot)
        } label: {
            ZStack {
                if let cg {
                    Image(cg, scale: 1, label: Text(slot.displayName))
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: edge, height: edge)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Theme.Colors.secondary.opacity(0.2))
                        .frame(width: edge, height: edge)
                }
            }
            .overlay(
                Rectangle()
                    .stroke(Color.white,
                            lineWidth: isSelected ? 2 : 0)
            )
            .scaleEffect(isSelected ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
    }

    private func addVisible(_ id: String) {
        var s = viewModel.thumbnailer?.visibleSlotIDs ?? []
        s.insert(id)
        viewModel.thumbnailer?.setVisibleSlotIDs(s)
    }

    private func removeVisible(_ id: String) {
        var s = viewModel.thumbnailer?.visibleSlotIDs ?? []
        s.remove(id)
        viewModel.thumbnailer?.setVisibleSlotIDs(s)
    }
```

- [ ] **Step 3: Wire `bottomDeck` into the body**

In the `body`, replace the `shutterRow` reference (the bottom-most child of the outer `VStack`) with `bottomDeck`.

- [ ] **Step 4: Attach/detach the thumbnailer in lifecycle**

In the `body`'s `.task { … }`, after `renderer = r`, add:

```swift
            viewModel.attachThumbnailer(renderer: r)
```

And in `.onDisappear { session.stop() }`, change to:

```swift
        .onDisappear {
            session.stop()
            viewModel.detachThumbnailer()
        }
```

- [ ] **Step 5: Commit**

```bash
git add PhotoEditor/Camera/CameraView.swift PhotoEditor/Camera/CameraViewModel.swift
git commit -m "feat(camera): bottom carousel — live LUT thumbnails, snap-to-center"
```

---

## Task 12: Studio FAB + wire-up

**Files:**
- Modify: `PhotoEditor/StudioTabView.swift`

- [ ] **Step 1: Add FAB overlay + presentation state**

Open `PhotoEditor/StudioTabView.swift`. Add to the struct:

```swift
    @State private var showCamera: Bool = false
```

Replace the `body` with:

```swift
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                // Title — large, restrained, VSCO-style.
                HStack {
                    Text("STUDIO")
                        .font(Theme.Typography.label)
                        .tracking(2)
                        .foregroundStyle(Theme.Colors.secondary)
                    Spacer()
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.sm)

                Picker("", selection: $segment) {
                    Text("CAMERA ROLL").tag(StudioSegment.cameraRoll)
                    Text("EDITS").tag(StudioSegment.edits)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.sm)

                Group {
                    switch segment {
                    case .cameraRoll:
                        CameraRollGridView(viewModel: viewModel, onPhotoOpened: onPhotoOpened)
                    case .edits:
                        editsGrid
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Theme.Colors.canvas.ignoresSafeArea())
            .toolbarBackground(Theme.Colors.canvas, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)

            cameraFAB
                .padding(.trailing, 16)
                .padding(.bottom, 16)
        }
        .fullScreenCover(isPresented: $showCamera) {
            if let libraryStore, let recipeStore = viewModel.recipeStore {
                let cameraVM = CameraViewModel(
                    libraryStore: libraryStore,
                    recipeStore: recipeStore,
                    cubeResolver: { id in
                        viewModel.filterLibrary.filter(withID: id)?.cube()
                    }
                )
                let session = CameraSession()
                CameraView(viewModel: cameraVM, session: session)
            }
        }
    }

    private var cameraFAB: some View {
        Button { showCamera = true } label: {
            Image(systemName: "camera.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.Colors.background)
                .frame(width: 56, height: 56)
                .background(Theme.Colors.text)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        }
        .accessibilityLabel("Open Camera")
    }
```

(`Filter.cube()` is the existing memoized resolver — see [EditorPresetPickerView.swift:179](../../../PhotoEditor/Editor/EditorPresetPickerView.swift) for the same pattern in the editor.)

- [ ] **Step 2: Commit**

```bash
git add PhotoEditor/StudioTabView.swift
git commit -m "feat(studio): floating camera FAB launches CameraView modal"
```

---

## Task 13: On-device acceptance

After Tasks 1–12 are committed, push and install:

- [ ] **Step 1: Push**

```bash
git push
```

- [ ] **Step 2: Trigger install via the documented routine**

Follow the post-push routine in [CLAUDE.md](../../../CLAUDE.md): fetch the new run id with `gh run list --repo Cels000/PhotoEditor --limit 1 --json databaseId --jq '.[0].databaseId'`, then run the documented `gh run watch && gh run download && ideviceinstaller -i …` chain.

- [ ] **Step 3: Manual verification on device**

Run through the success criteria from the spec:

1. **Cold launch → Studio → FAB → camera opens** with last-used preset (or ORIGINAL on first run).
2. **Live preview** holds ≥24 fps on the Camera Roll subject. Swipe between presets — viewfinder color changes immediately.
3. **Carousel thumbnails** reflect the live scene within ~1s. Off-screen thumbs don't animate.
4. **Tap-to-focus**: reticle appears at touch, exposure slider slides in from the right, fades after 3s.
5. **Flash chip** cycles auto → on → off; flash fires accordingly. (Skip in well-lit conditions.)
6. **Grid toggle** shows/hides the rule-of-thirds overlay.
7. **Front/back flip** swaps cameras; selfies are mirrored in preview but **unmirrored** in the saved file.
8. **Shutter** triggers haptic + brief flash. Photo arrives in the iOS camera roll *and* in the app's `EDITS` segment with the recipe's full look applied.
9. **Open the captured Library item** in the editor — preset is already selected, sliders are set per the recipe, all editable.
10. **Permission denial path**: Settings → Privacy → Camera → revoke for PhotoEditor, reopen, tap FAB; alert with "Open Settings" appears.

- [ ] **Step 4: If any criterion fails**

File a follow-up task in this plan rather than mutating an existing task. The spec's success criteria are the gate — don't claim done until all 10 pass.

---

## Self-review notes (for the planner)

Coverage check vs. spec:
- ✅ All 7 locked decisions appear in tasks (1–12).
- ✅ Spec's 5 success criteria mapped to Task 13 manual verification.
- ✅ All five new units (`CameraSession`, `CameraPreviewRenderer`, `CameraCarouselThumbnailer`, `CameraView`, `CameraViewModel`) created.
- ✅ Two integration points (`StudioTabView`, `LibraryStore`) modified.
- ✅ `Info.plist` privacy key added.
- ✅ Out-of-scope items (burst/video/RAW/landscape/timer) deliberately omitted.

Type consistency:
- `LibraryStore.importFromCamera(assetID:stack:thumbnail:)` — matches spec.
- `CameraViewModel.lastSlotKey = "camera.lastRecipeID"` — matches spec persistence key.
- `CameraSlot.originalID = "__original__"` — defined once, used everywhere.
- `CameraPreviewRenderer.applyLUT(filterSelection:to:cubeResolver:)` — same signature in tests and view-model.

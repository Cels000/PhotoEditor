# Camera Capture — Design Spec

**Date:** 2026-05-04
**Feature:** Built-in camera with live preset preview ("Capture")
**Status:** Approved for planning

## Goal

Add a first-class camera inside PhotoEditor that shows a live LUT preview of the
currently-selected preset. Killer-feature parity with VSCO / Dehancer: open the
camera, see the world through Portra 400 before the shutter fires.

## Decisions (locked during brainstorm)

| # | Decision | Choice |
|---|---|---|
| 1 | Live preview pipeline scope | LUT-only (single stage) per frame; full pipeline applied later in editor |
| 2 | What gets saved | Original full-res HEIC to Photos + Library item with recipe pre-applied |
| 3 | Recipe selection in viewfinder | Bottom carousel of live LUT thumbnails |
| 4 | Entry point | Floating shutter FAB on the Studio tab |
| 5 | Capture aspect ratio | 4:3 full-sensor (no crop) |
| 6 | In-camera controls | Standard kit: shutter, carousel, flip, close, tap-to-focus, exposure compensation, flash auto/on/off, 3×3 grid |
| 7 | Carousel state | Sticky last-used preset + always-available ORIGINAL slot at index 0 |

## Architecture

New `PhotoEditor/Camera/` directory. Five units:

### `CameraSession` (`@MainActor` class)
Owns `AVCaptureSession`. Configures inputs (back/front device),
`AVCaptureVideoDataOutput` for live frames, `AVCapturePhotoOutput` for stills.

API:
- `start()` / `stop()`
- `flipCamera()`
- `setFlashMode(.auto | .on | .off)`
- `setFocusPoint(CGPoint)` — normalized 0…1
- `setExposureCompensation(Float)` — -2…+2 EV
- `capturePhoto() async throws -> Data` — returns HEIC bytes

### `CameraPreviewRenderer` (`NSObject`, `AVCaptureVideoDataOutputSampleBufferDelegate`)
Receives `CMSampleBuffer`s on a dedicated serial queue
(`com.photoeditor.camera.preview`). Converts to `CIImage(cvPixelBuffer:)`
zero-copy. Applies the currently-selected LUT via the existing
`PipelineBuilder.applyLUT` only — bypasses all other 9 stages. Renders directly
to `MTKView` via `CIContext.render(_:to:commandBuffer:bounds:colorSpace:)` (no
`CGImage` round-trip).

Holds an atomic snapshot of the latest `CIImage` for the carousel thumbnailer to
read without locking the render path. Mirrors horizontally for front-camera
preview only — captured photo is unmirrored (standard iOS behavior).

Owns its own `CIContext` (separate from the editor's two contexts) so per-frame
work doesn't contend with editor renders.

### `CameraCarouselThumbnailer`
Subscribes to the renderer's latest-frame snapshot at 2 Hz.

For each *visible* preset slot in the carousel viewport:
1. Center-crop the latest `CIImage` to square.
2. Downsample to 96×96.
3. Apply that slot's LUT (skip for ORIGINAL slot).
4. Render to `CGImage`.
5. Publish `[FilterID: CGImage]` map.

Off-screen slots: not rendered. Re-render kicks in when scrolled into view.

### `CameraView` (SwiftUI)
Full-screen modal (`.fullScreenCover`). Composes:
- `MTKViewRepresentable` for live preview
- Top control bar (close, flash, grid, flip)
- Bottom carousel + selected-name label + shutter button
- Tap-to-focus reticle overlay + exposure compensation slider

### `CameraViewModel` (`@Observable`, `@MainActor`)
Wires the above. Persists last-used `filterID`, flash mode, and grid-enabled
flag to `UserDefaults`. On capture:
1. Take HEIC bytes from `CameraSession.capturePhoto()`.
2. Write to Photos via `PHPhotoLibrary.shared().performChanges { … }` using
   `PHAssetCreationRequest.forAsset().addResource(with: .photo, data:, options:)`.
3. Fetch the new `PHAsset.localIdentifier` from the change block.
4. Call `LibraryStore.importFromCamera(assetID:stack:thumbnail:)` to create a
   `LibraryItem` whose `AdjustmentStack` is the *full* stack of the selected
   recipe (the entire recipe, not just its LUT). For the ORIGINAL slot the
   stack is `AdjustmentStack.identity`.
5. Use the cooked preview frame (already in memory) as the Library item
   thumbnail — faster than re-rendering.

## Data Flow

### Live preview (target ~30 fps)
1. `AVCaptureVideoDataOutput` delivers `CMSampleBuffer` on the preview queue.
2. `CameraPreviewRenderer` builds `CIImage(cvPixelBuffer:)` zero-copy.
3. Resolve LUT via the existing `cubeResolver` closure (the editor's). If the
   selected slot is ORIGINAL, skip the LUT stage entirely.
4. Apply only `PipelineBuilder.applyLUT` to the frame.
5. Render to `MTKView` via Metal-backed `CIContext.render(...)`.
6. Mirror horizontally if front camera.

### Carousel thumbnails (2 Hz, visible only)
1. Timer publishes a 2 Hz tick.
2. Thumbnailer reads the latest `CIImage` snapshot from the renderer.
3. Center-crop → 96×96 downsample → apply LUT → `CGImage`.
4. Publish `[slotID: CGImage]`.

### Capture
1. User taps shutter → `CameraSession.capturePhoto()` requests HEIC at full
   sensor resolution (4:3) with current flash mode.
2. `AVCapturePhotoCaptureDelegate` returns `Data` on a background queue.
3. Save unprocessed HEIC to Photos.
4. Create Library item with the pre-applied recipe (filter + strength 1.0).
5. Brief shutter flash + `.medium` haptic + checkmark toast (existing
   `ToastOverlay`). Camera stays open for the next shot.

### State persistence
`UserDefaults` keys (no SwiftData schema changes):
- `camera.lastRecipeID` — `String?`, nil for ORIGINAL slot (otherwise
  `RecipeItem.id.uuidString`)
- `camera.flashMode` — `Int` (0=auto, 1=on, 2=off)
- `camera.gridEnabled` — `Bool`

## UI Layout

Portrait-only for v1.

```
┌─────────────────────────────┐
│ ✕    ⚡auto   ⌗      ⟲     │  top bar
├─────────────────────────────┤
│                             │
│      [4:3 live preview]     │
│      tap to focus           │
│      drag exposure ⊙        │
│                             │
├─────────────────────────────┤
│ [ORIG][P400][P800][...]     │  carousel
│  Portra 400                 │  selected name
│         ⬤ shutter          │
└─────────────────────────────┘
```

### Top bar (44pt, safe-area-respecting)
- `✕` close (left) — dismisses modal
- `⚡` flash — cycles auto → on → off; icon color reflects state
- `⌗` grid — toggles 3×3 rule-of-thirds overlay
- `⟲` flip front/back (right)

### Preview
- 4:3 `MTKView` filling available width
- Single tap → focus reticle animates at touch point; AE/AF lock briefly
- After tap-to-focus, vertical sun-icon slider appears on right edge for 3s for
  exposure compensation (-2…+2 EV); auto-hides
- Optional 3×3 grid overlay (1px white @ 30% opacity)

### Carousel
- Horizontal `ScrollView` of 96×96 thumbnails, 8pt spacing
- `.scrollTargetBehavior(.viewAligned)` for snap
- Selected slot: 2pt white ring + 1.05 scale
- Selected preset's display name shown below in tracked uppercase (matches
  app's VSCO-monochrome theme)
- Carousel slot = a `RecipeItem` from `RecipeStore` (built-in presets *and*
  user-imported `.photorecipe` recipes — the same source the editor's
  `EditorPresetPickerView` reads). A synthetic ORIGINAL slot is prepended at
  index 0; it carries `AdjustmentStack.identity` (no LUT, no adjustments).
  Order: ORIGINAL, then `RecipeStore.items` flattened across categories in
  `sortOrder` ascending (no category headers in the carousel).
- Live preview applies only the recipe's `adjustmentStack.filter` portion (the
  LUT) — every other adjustment (light, color, grain, vignette, etc.) is
  ignored at viewfinder time but baked into the captured Library item's stack
  in full.
- Thumbnails refresh at 2 Hz, visible-only

### Shutter
- 72pt round button, white fill, white ring outline, centered below carousel
- Tap → screen flash + `.medium` haptic + checkmark toast
- No burst / multi-shot in v1

### Animations
- Modal presents via `.fullScreenCover` + fade
- Front/back flip: 0.3s flip transform on preview (masks AVCapture reconfigure
  latency)

### Theme
All chrome uses `Theme.Colors.text` / `.background`. No color accents.

## Permissions & Error Handling

### Camera permission
Add `NSCameraUsageDescription` to `Info.plist`:

> "Photo Editor uses your camera so you can shoot through your favorite presets."

On first FAB tap, request via `AVCaptureDevice.requestAccess(for: .video)`.

If denied: alert with `Settings →` deeplink
(`UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)`).

### Photos write permission
Already granted via existing `NSPhotoLibraryAddUsageDescription` and the
full-access flow in `PhotoLibraryAccess`. In limited mode, `addResource` still
works — the new asset is automatically scoped to the app's selection.

### Session lifecycle
- `CameraSession.start()` in `CameraView.task { }`
- `stop()` in `.onDisappear`
- `UIApplication.didEnterBackgroundNotification` → stop session, dim preview
- Foreground → restart
- Audio session: `.ambient` + `.mixWithOthers` so background music isn't ducked

### Device fallbacks
- No front camera (rare): hide flip button
- `device.hasFlash == false`: hide flash chip
- LUT load failure for the selected preset: silently fall through to ORIGINAL
  on the live frame; log via existing logger; no modal interrupt during shooting

### Backpressure
- `AVCaptureVideoDataOutput.alwaysDiscardsLateVideoFrames = true` → OS handles
  frame drops
- Carousel thumbnailer is independently throttled — main preview can drop to
  15 fps while thumbs continue at 2 fps off the latest frame

### Capture failure
`AVCapturePhotoCaptureDelegate` error path → red toast "Couldn't save photo"
via existing `ToastOverlay`. Session stays running.

### Orientation
Camera modal is portrait-locked for v1. Override
`UIViewController.supportedInterfaceOrientations` on the hosting controller.
Landscape capture deferred to a follow-up. Rest of app keeps existing
multi-orientation support.

### Memory
No retained frame history — each `CMSampleBuffer` is processed and dropped.
The camera's `CIContext` is allocated when `CameraView` appears and freed when
it disappears.

## Integration Points

### `Studio/StudioTabView.swift`
Add a floating circular camera button (FAB) anchored bottom-right above the
camera-roll grid (16pt safe-area inset), 56pt diameter, white fill on theme
background. Tap → present `CameraView` via `.fullScreenCover`.

### `Library/LibraryStore.swift`
Add a new method:

```swift
func importFromCamera(
    assetID: String,
    stack: AdjustmentStack,
    thumbnail: Data?
) -> LibraryItem
```

Creates a `LibraryItem` referencing the `PHAsset` by `localIdentifier`, with the
supplied `AdjustmentStack` (full recipe stack from the selected carousel slot,
or `.identity` for ORIGINAL). Persists the supplied JPEG thumbnail bytes to
skip the `ThumbnailGenerator` round-trip on first display.

### `Filters/FilterLibrary.swift`
Reuse the existing `cubeResolver` closure that the editor uses; no API changes.

### `RenderEngine/PipelineBuilder.swift`
No changes required — `applyLUT` is already a stateless static function callable
from the camera renderer.

### `Info.plist`
Add `NSCameraUsageDescription`. No other changes.

## Out of Scope (v1)

- Burst / multi-shot
- Video capture
- Manual ISO / shutter speed / RAW
- Landscape capture (portrait only)
- Level / horizon line
- Self-timer
- 1:1 / 16:9 aspect modes (always 4:3; user crops in editor)
- Carousel category headers (flat list in carousel; full picker still
  categorized in editor)
- Live full-pipeline preview (LUT-only; remaining 9 stages applied at
  edit/export time)

## Success Criteria

1. From cold app launch, user can: tap Studio → tap FAB → see live preview with
   their last-used preset applied → tap shutter → see photo arrive in Library
   with that preset's recipe attached.
2. Live preview holds ≥24 fps on iPhone 12+ with any built-in LUT applied.
3. Carousel thumbnails reflect the live scene (visible refresh) within 1s of
   pointing the camera at a new subject.
4. Captured Library item, when opened in the editor, shows the same look as
   was visible in the viewfinder, plus full editability (user can dial back
   strength, swap filter, adjust light/color/etc).
5. Permission denied path lands the user in iOS Settings with a clear message.
6. No regressions in editor render performance (camera uses its own
   `CIContext`).

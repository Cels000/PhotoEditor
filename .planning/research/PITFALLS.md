# Pitfalls Research

**Domain:** Premium iOS photo editor (SwiftUI, Core Image, LUTs, non-destructive library)
**Researched:** 2026-05-03
**Confidence:** HIGH (color/render/LUT), HIGH (performance), MEDIUM (persistence/SwiftData), HIGH (UX/export)

---

## Critical Pitfalls

### Pitfall 1: LUT Applied in Wrong Color Space (Gamma-Encoded Input)

**What goes wrong:**
`CIColorCube` expects its input to arrive in **linear light** (gamma-decoded). Core Image's working color space is linear sRGB by default, so a CIImage flowing through a standard Core Image graph is already linear when it hits the cube filter. Problems arise when:
- You construct a `CIImage` directly from a `UIImage` without preserving color space — UIKit images are gamma-encoded sRGB, and `CIImage(image:)` may not correctly tag the color space for Core Image to linearize before passing to the cube.
- You use `CIColorCube` (no color-space parameter) instead of `CIColorCubeWithColorSpace` — the former assumes the input is already in working space, which may not be true if the image entered the pipeline from UIKit.
- You source LUT data from DaVinci Resolve or Lightroom presets that were authored expecting sRGB-gamma input; applying them in linear space produces over-brightened shadows and crushed highlights.

**Why it happens:**
Developers conflate "sRGB" (which implies the gamma transfer function) with Core Image's linear-sRGB working space. The distinction is subtle — same primaries, different gamma — and Apple's documentation on `CIColorCubeWithColorSpace` describes the `colorSpace` parameter as the space "input data will be matched to before kernel processing," which reads as if you're setting the LUT's working space, but it actually describes the input remapping step.

**How to avoid:**
- Always use `CIColorCubeWithColorSpace` and pass the color space of the LUT's design intent (typically `CGColorSpace(name: CGColorSpace.sRGB)` for film-look LUTs from Lightroom/Resolve).
- Build a test LUT that maps pure red → red, pure green → green, pure blue → blue, and a mid-gray → mid-gray. If mid-gray shifts in luminance, the color space is wrong.
- Document each LUT's design color space alongside the `.cube` file at authoring time.

**Warning signs:**
- Skies look unnaturally bright or highlights are blown when a filter is applied, but the same LUT in Lightroom looks correct.
- Neutral gray test patches shift in luminance when filter strength > 0%.
- Log output from `cicontext.render` shows unexpected intermediate conversions.

**Phase to address:** LUT Pipeline phase (the phase that replaces current `CIPhotoEffect*` filters with `CIColorCube`).

---

### Pitfall 2: CIColorCube Accepted Dimensions — Silent Wrong Output for 32-Cube LUTs

**What goes wrong:**
`CIColorCube` accepts only these cube sizes: **2, 4, 8, 16, 32, 64** (the `inputCubeDimension` parameter). The `Data` payload must be exactly `size³ × 4 × 4` bytes (four 32-bit floats: R, G, B, A per voxel). A 33³ cube silently fails or produces garbage. Many free `.cube` LUT packs ship as 33×33×33 (the standard Adobe/DaVinci Resolve default), which is NOT a power-of-2 and is NOT a valid `CIColorCube` dimension.

Additionally, the alpha component must be set to `1.0` for every voxel — `.cube` files contain only RGB triplets, so naively copying them without appending alpha produces a cube with wrong byte length or invisible output.

**Why it happens:**
`.cube` file parsing tutorials online parse the RGB rows correctly but omit the alpha padding. The 33-cube mismatch is unknown until you test with a real-world LUT library.

**How to avoid:**
- When parsing a `.cube` file: (1) skip header lines until you see only three space-separated floats, (2) parse exactly `size³` RGB triplets, (3) append `1.0` alpha to every voxel.
- If the LUT is 33³, resample/interpolate to 32³ or 64³ before creating the `Data` buffer (trilinear interpolation is sufficient).
- Validate: `assert(data.count == dimension * dimension * dimension * 4 * MemoryLayout<Float>.size)` before passing to the filter.
- Test with a known-good identity LUT first; output should be pixel-identical to input.

**Warning signs:**
- Filter renders as solid gray or solid black.
- Filter renders input unchanged (identity LUT behavior when LUT data is misaligned).
- App crashes with `EXC_BAD_ACCESS` inside `CIColorCube` rendering.
- Cube dimension printed as 33 in the `.cube` header.

**Phase to address:** LUT Pipeline phase. Write a `.cube` parser unit test before integrating a single production LUT.

---

### Pitfall 3: EXIF Orientation Lost When Entering Core Image via UIImage

**What goes wrong:**
`UIImage` stores orientation metadata in `imageOrientation`. `CIImage(image:)` does NOT apply this orientation transform — the resulting `CIImage` has the pixel data in its raw (possibly rotated) layout, with the orientation encoded only in `CIImage.properties[kCGImagePropertyOrientation]` as metadata, not applied geometrically. When you render this `CIImage` back to a `UIImage(cgImage:)`, the orientation is lost; the output image appears rotated.

The existing `PhotoEditorViewModel` already exhibits this: `sourceCIImage = CIImage(image: downsampled)` followed by forced `orientation: .up` in the render path. This works only because `downsample()` bakes the orientation via `UIGraphicsImageRenderer` before creating the `CIImage`. If the downsample path is ever bypassed (e.g., for full-res export from the original PHAsset), raw EXIF orientation will silently corrupt the output.

**Why it happens:**
UIKit automatically handles orientation; Core Image does not. The "it looks fine in the preview" path hides the bug because UIKit display re-applies orientation. It surfaces on export.

**How to avoid:**
- After creating a `CIImage` from any source, call `ciImage.oriented(forExifOrientation: exifValue)` immediately to bake the orientation geometrically.
- For PHAsset sources: read `kCGImagePropertyOrientation` from `imageProperties` and apply via `oriented(forExifOrientation:)`.
- Note: `CIImage.oriented(forExifOrientation:)` takes a TIFF/EXIF integer (1–8), NOT a `UIImage.Orientation` enum value. Write a mapping helper once and test all 8 cases.

**Warning signs:**
- Portrait photos export as landscape.
- Photos taken in non-standard camera orientations (held upside down, sideways) export rotated.
- Looks correct in app preview but wrong when opened in Photos app.

**Phase to address:** LUT Pipeline / Core rendering foundation phase. Fix before implementing any export path.

---

### Pitfall 4: sRGB ↔ P3 Color Gamut Drift on Wide-Gamut Displays

**What goes wrong:**
iPhones from XS onward use Display P3 screens. If your `CIContext` is created without a `workingColorSpace` / `outputColorSpace` override, Core Image will use device defaults that may produce P3-gamut output. When you then convert this to a `UIImage` and display it in a SwiftUI `Image`, the display may render colors slightly differently than what your LUT intended if the LUT was authored in sRGB. Conversely, if you embed a P3 ICC profile in an exported HEIC but the user views it on an sRGB device, saturated reds and greens will clip.

More acute: a `CGColorSpace` created with `CGColorSpaceCreateDeviceRGB()` has no ICC profile metadata, meaning the OS can't map it correctly across display types. Many tutorials use this as the "easy" way to create a color space.

**How to avoid:**
- Create your `CIContext` explicitly: `CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!, .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])`.
- Never use `CGColorSpaceCreateDeviceRGB()` — always use a named profile (`CGColorSpace.sRGB`, `CGColorSpace.displayP3`).
- When exporting, embed the correct ICC profile in the output (ImageIO does this automatically when you specify `kCGImageDestinationEmbedThumbnail` and a named color space).
- Design all LUTs targeting sRGB for broadest compatibility; note this on the LUT spec sheet.

**Warning signs:**
- Saturated colors look different between the in-app canvas and the Photos app after export.
- Orange or skin tones shift subtly between preview and saved image.
- Instruments Color Diagnostics reports untagged color data.

**Phase to address:** LUT Pipeline / Core rendering foundation. Establish `CIContext` configuration in the first phase that touches it; changing it later is a cascade.

---

### Pitfall 5: CIContext Created Without Metal Device (Software Rendering)

**What goes wrong:**
`CIContext()` with no arguments can fall back to a CPU-based software renderer in some configurations. `CIContext(options:)` without `.useSoftwareRenderer: false` is similarly risky. Software rendering is 5–20× slower than GPU rendering on Metal, making slider interaction feel sluggish on any image above ~1MP.

The existing `PhotoEditorViewModel` uses `private let context = CIContext()` — this is the at-risk pattern.

**How to avoid:**
```swift
let device = MTLCreateSystemDefaultDevice()!
let context = CIContext(mtlDevice: device, options: [
    .workingColorSpace: CGColorSpace(name: CGColorSpace.linearSRGB)!,
    .outputColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    .useSoftwareRenderer: false
])
```
Create this once at app launch, hold it for the lifetime of the editor session.

**Warning signs:**
- Render time > 50ms for a 2048px image on device.
- Instruments shows heavy CPU activity (not GPU) during filter application.
- Preview feels fine in Simulator but slow on real device (Simulator uses a different render path).

**Phase to address:** Core rendering foundation — first phase. This is a one-line fix that pays dividends everywhere.

---

### Pitfall 6: Rendering Full-Resolution Image on Every Slider Tick

**What goes wrong:**
The existing debounce is 30ms — which means if a user drags a slider for 500ms they trigger ~16 renders. At 2048px with multiple CIFilter stages, each render may take 50–200ms. Tasks queue faster than they complete, and the render thread stays pegged until the user stops.

With the planned adjustment stack (LUT + exposure + contrast + highlights + shadows + whites + blacks + saturation + temperature + tint + vibrance + HSL × 8 + curves + split-toning + grain + vignette + sharpen), each render traverses a deep filter graph.

**How to avoid:**
- Keep a separate **preview resolution**: downsample to 1080px long edge for interactive preview. Only render the full 2048px (or original PHAsset resolution) on export.
- The 30ms debounce remains appropriate for the preview render; increase to 150ms or use `Task.sleep` + cancellation for the live drag path, firing immediately on gesture end.
- Use `@GestureState` with a `DragGesture` to separate "dragging" from "committed" state — only schedule a render on committed change.
- Profile with Xcode's GPU Frame Capture before shipping any slider.

**Warning signs:**
- UIImage updates visible "stutter" during drag (frame drops).
- Memory pressure increases while dragging (queued renders accumulate large images).
- Device gets warm during a 30-second adjustment session.

**Phase to address:** Core rendering foundation. Set the preview/export dual-path architecture before adding the second adjustment slider.

---

### Pitfall 7: CIImage Retained in Closure Capturing Filter Graph

**What goes wrong:**
If you capture a `CIImage` in a `Task` or `DispatchQueue` closure without `[weak self]` or without an explicit release point, the `CIImage` — which itself is a lazy promise referencing potentially many upstream filter stages — stays in memory until the closure deallocates. With a deep filter graph (10+ stages), each stage retains its input, creating a chain of large backing buffers.

The existing code uses `[weak self]` correctly in `scheduleRender()`. The risk surfaces when adding `@escaping` closures for export, async image saving, or histogram computation.

**How to avoid:**
- Always use `[weak self]` in render closures.
- After rendering to `CGImage`, immediately nil the `CIImage` local if you no longer need it — Swift's ARC will then drop the entire filter graph.
- Don't store `CIImage` in `@Published` or `@State` properties — store only the rendered `UIImage`.
- The `sourceCIImage` stored on the ViewModel is unavoidable; it is the source. Keep it at preview resolution (2048px), not full PHAsset resolution.

**Warning signs:**
- Memory footprint grows monotonically during editing without plateauing.
- Instruments Allocations shows `CIImage` instances increasing.
- App receives memory warning after a long edit session.

**Phase to address:** Core rendering foundation. Establish the pattern in the first render loop; retrofit is error-prone.

---

### Pitfall 8: SwiftUI Re-Renders on Every `@Published` Change Causing UI Jank

**What goes wrong:**
Every `@Published` adjustment property (brightness, contrast, saturation, etc.) triggers a SwiftUI diff + potential view body re-evaluation. With 20+ adjustment properties on the ViewModel, a slider drag publishes changes at ~60 Hz, causing the entire view hierarchy to diff 60 times per second even for properties that don't affect layout.

The fix is NOT to remove `@Published` — it IS needed for the rendered image. The problem is that non-image-affecting state (slider visual position) is conflated with image-affecting state (the value used in the render).

**How to avoid:**
- Separate display state from render state: use a `@GestureState` or local `@State` to drive the slider's visual position, and only commit to the ViewModel's `@Published` on gesture end (or with the existing debounce).
- For the canvas `Image`, wrap it in its own isolated subview that takes only `UIImage?` as input — SwiftUI will only re-render that view when the image itself changes, not on every adjustment property change.
- Use `equatable()` modifier on views that should not re-render unless their specific input changes.

**Warning signs:**
- `instruments` → SwiftUI → View body evaluations shows > 10 evaluations per second for static UI elements while dragging a slider.
- UI elements outside the canvas flicker or redraw during slider drag.
- Scrolling the filter strip stutters while an adjustment is active.

**Phase to address:** UI scaffolding phase, before adding more than 3 adjustments. Adding 15 more `@Published` properties on top of a poorly structured view hierarchy compounds the problem non-linearly.

---

### Pitfall 9: Gesture Conflicts Between Canvas Pan/Zoom and Adjustment Sliders

**What goes wrong:**
If the main canvas supports pinch-to-zoom or drag-to-compare, its gesture recognizers conflict with SwiftUI's built-in scroll gestures in the adjustment panel, especially on smaller iPhones where the panel overlaps the canvas. A `DragGesture` on the canvas intercepts vertical swipes meant for the bottom sheet. A `MagnificationGesture` on the canvas can conflict with the adjustment panel dismiss gesture.

**How to avoid:**
- Use `simultaneousGesture` for gestures that should coexist, and `highPriorityGesture` for gestures that should always win.
- iOS 17's `UIGestureRecognizerRepresentable` enables explicit `shouldRecognizeSimultaneouslyWith` coordination if SwiftUI gestures prove insufficient.
- For the before/after compare feature (press-and-hold): use `LongPressGesture` sequenced with the press, not `DragGesture`, to avoid eating short taps.
- Provide clear visual affordances — a crop handle grab area should be distinct from the canvas pan area.

**Warning signs:**
- Tapping a filter in the strip accidentally zooms the canvas.
- Bottom sheet refuses to dismiss when finger starts on the canvas.
- Before/after triggers unexpectedly during normal navigation.

**Phase to address:** Editor canvas / gesture system phase. Design the gesture hierarchy before implementing crop, compare, and zoom — retrofit is extremely difficult.

---

### Pitfall 10: `extent.integral` Pixel Drift in Rotation

**What goes wrong:**
The existing rotate path calls `output.extent.integral` to snap the extent to integer pixel boundaries. For 90°-step rotations this is correct. For **free rotate** (straighten tool), each call to `extent.integral` rounds independently — so if a rotation produces an extent of `(−0.4, −0.7, 2048.8, 1536.3)`, `integral` snaps to `(−1, −1, 2050, 1537)` adding extra pixels. Chaining multiple free-rotate operations accumulates this drift, progressively cropping or expanding the image by 1–2px per operation.

**How to avoid:**
- For free rotate: do NOT use `extent.integral` on intermediate steps. Apply the full cumulative rotation transform in one shot from the original `sourceCIImage` extent.
- Maintain a single `cumulativeRotationAngle: Double` on the model; the render function applies `sourceCIImage.transformed(by: rotationTransform(angle: cumulativeAngle))` from scratch each time.
- Only apply `extent.integral` (or better, explicit crop to the inscribed rectangle) at the final crop step for export.
- For the straight-crop-after-rotate case: compute the largest inscribed axis-aligned rectangle analytically rather than relying on extent rounding.

**Warning signs:**
- After 5–6 free-rotate operations, the image appears to have gained or lost a pixel border.
- A 0° rotation produces a slightly different image than the original (1px difference visible when diff-ed).
- Export images have inconsistent dimensions for the same aspect ratio setting.

**Phase to address:** Crop/Straighten phase. Do not use the existing `extent.integral` pattern as the foundation for a free-rotate feature.

---

### Pitfall 11: Rotation Applied After Color Adjustments (Transform Order Regression)

**What goes wrong:**
In the existing pipeline, rotation is applied AFTER color adjustments. This is correct for 90°-step rotations (order doesn't matter for orthogonal transforms when working on a full-image extent). For **arbitrary angle** free-rotate with a subsequent crop, the order matters: if you apply color → crop-to-canvas → then rotate, you lose color information outside the crop rect. The correct order is: rotate → crop → color.

Additionally, if a LUT is applied before a crop, the cropped region's color is affected by the LUT's behavior at the image edges — film-grain and vignette filters in particular have extent-dependent behavior.

**How to avoid:**
- Define an explicit filter application order and document it:
  1. Geometry (rotate, crop, flip) — applied to source pixels
  2. Color grade (LUT, tone curve, exposure, HSL)
  3. Spatial effects (grain, sharpen)
  4. Canvas effects (vignette)
- Build this order as an immutable pipeline spec early; changing it after shipping causes visible behavior changes in saved Recipes.

**Warning signs:**
- Vignette center appears offset after rotating the image.
- Grain looks denser at image edges (clue: grain is being computed on the pre-crop extent).
- Applying the same Recipe after rotating produces different results.

**Phase to address:** Core rendering foundation / filter order spec. Decide and document before adding the second filter type.

---

### Pitfall 12: SwiftData Schema Migration Failures When Adjustment Stack Evolves

**What goes wrong:**
SwiftData migrations are fragile. Known failure modes in iOS 17–18:
- Adding a non-optional property without a default value crashes at store open, not at migration.
- Transformable array types (`[AdjustmentEntry]`) change their backing representation between iOS minor versions (iOS 18.4 vs 18.5 changed Binary Data → Transformable, breaking existing stores).
- Deleting a property works in lightweight migration; renaming requires a `MigrationStage` with explicit `originalName`; if you forget, data is silently dropped.
- SwiftData does NOT generate a `VersionedSchema` by default — you must opt in. Existing stores without a version are treated as "version 0" and may not migrate correctly.

For this app, the adjustment stack is stored as a serialized structure (likely `[String: Double]` or a typed array). As filters are added (curves, HSL, split toning), this schema will evolve.

**How to avoid:**
- Start with `VersionedSchema` from day one, even if there is only one version. The overhead is minimal; the rescue cost is enormous.
- Store adjustment stacks as `Data` (JSON-encoded) rather than as individual model properties — JSON fields are forward-compatible without schema migrations.
- Never use a non-optional property without a `defaultValue` in the model definition.
- Write a migration test that opens a copy of a known-old store and verifies the model loads correctly.

**Warning signs:**
- App crashes on launch after an Xcode schema change (not a code change).
- Previously saved edits disappear after app update.
- `NSPersistentStoreCoordinator` logs "The model used to open the store is incompatible".

**Phase to address:** Library / Persistence phase. Set up `VersionedSchema` before writing the first `@Model` class.

---

### Pitfall 13: Recipes Becoming Invalid When Filter Library Changes

**What goes wrong:**
A Recipe stores a filter name (e.g., `"Kodak400"`) and an adjustment stack. If you later rename, remove, or restructure a LUT filter, all Recipes that reference it become silently broken — they either apply no filter or crash the filter lookup. This is a variant of the "URL orphan" problem familiar from Core Data.

**How to avoid:**
- Assign each LUT filter a **stable UUID** or numeric ID at authoring time. Store this ID in the Recipe, not the human-readable name. The display name can change; the ID must not.
- Version the filter catalog separately from the app. On load, validate each Recipe against the current catalog; surface "Filter no longer available" gracefully.
- When a filter is removed, mark it deprecated (keep the LUT file, just hide from the picker) rather than deleting it — this preserves existing Recipes.

**Warning signs:**
- Applying a saved Recipe shows "Original" (no filter) silently.
- Crashes or unexpected behavior when opening a Recipe created in a previous build.

**Phase to address:** Recipes phase. Define the stable ID scheme before saving the first Recipe.

---

### Pitfall 14: Library Thumbnails Orphaned from Source Images

**What goes wrong:**
If you store thumbnails as files and source references as PHAsset `localIdentifier` strings, three scenarios orphan them:
1. User deletes the original from Photos — `localIdentifier` becomes invalid; thumbnail shows stale image.
2. User revokes Photos permission — source can't be re-loaded; thumbnail shows but re-edit is impossible.
3. App migrates from one persistence scheme to another (e.g., SwiftData store replaced) — thumbnail files survive but model records don't.

**How to avoid:**
- Always validate `PHAsset.fetchAssets(withLocalIdentifiers:)` on library load; mark items with missing assets as "source unavailable" rather than crashing.
- For the non-destructive model: store the **rendered export** at full res in the app's Documents container (not Photos), and the PHAsset ID for re-edit. If the PHAsset is gone, the user can still view/share the rendered version.
- On app first launch after an update, run a migration pass that verifies all thumbnail file paths exist.

**Warning signs:**
- Library items show broken image placeholders after the user deletes an original from Photos.
- App crashes on `PHImageManager.requestImage(for:)` when asset is unavailable.

**Phase to address:** Library / Persistence phase.

---

### Pitfall 15: UIImage Held at Full PHAsset Resolution in Memory

**What goes wrong:**
`PHImageManager.requestImageDataAndOrientation` returns the full-resolution HEIC/RAW — for a 48MP iPhone 15 Pro RAW, this is ~140MB decoded. If you hold this as a `UIImage` on the ViewModel for re-edit, you've pinned 140MB for the session. With the existing 2048px downsample on import, this is avoided for the current `UIImage`-from-picker path — but if you add a "re-edit from library" flow using PHAsset, this risk re-emerges.

**How to avoid:**
- For re-edit: load from the stored app-container copy (the rendered JPEG/HEIC saved on first export), not from the PHAsset.
- If you must load from PHAsset (e.g., for full-res re-edit): use `PHImageRequestOptions` with `deliveryMode: .opportunistic` and a `targetSize` matching your preview pipeline, then request full-res only at export time.
- Set `isNetworkAccessAllowed = false` on `PHImageRequestOptions` for sync/iCloud-backed assets unless you explicitly want to wait for downloads.

**Warning signs:**
- Memory usage spikes to > 300MB on re-open of a library item.
- `os_signpost` intervals for `PHImageManager.requestImage` show > 2 seconds.
- Memory warning received immediately on entering the editor from the library.

**Phase to address:** Library / Persistence phase, when "re-open and continue editing" is implemented.

---

### Pitfall 16: HEIC Export Stripping ICC Profile / Color Space

**What goes wrong:**
When saving an image to Photos via `PHAssetChangeRequest.creationRequestForAsset(from:)`, UIKit handles the encoding. If the `UIImage` was created from a `CGImage` without an embedded color space, the HEIC will be saved without an ICC profile — or worse, with an incorrect device profile. Downstream apps will then display colors incorrectly.

Additionally, `PHAssetChangeRequest` does not preserve custom EXIF or IPTC metadata you may have carried from the source. EXIF timestamp, GPS, and camera data from the original asset are silently dropped.

**How to avoid:**
- Use `ImageIO` + `CGImageDestination` for export rather than UIKit's `UIImage.jpegData / heicData`:
  ```swift
  let destination = CGImageDestinationCreateWithURL(outputURL, kUTTypeHEIC, 1, nil)!
  let properties: [CFString: Any] = [
      kCGImageDestinationLossyCompressionQuality: quality,
      kCGImagePropertyColorModel: kCGImagePropertyColorModelRGB,
      // include kCGImagePropertyExifDictionary from source
  ]
  CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
  CGImageDestinationFinalize(destination)
  ```
- To write the result to Photos: write to a temp URL with `CGImageDestination`, then use `PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL:)` to preserve the file's embedded metadata.
- To preserve EXIF from source: load it with `CGImageSourceCopyPropertiesAtIndex` before editing and re-attach to the output properties dictionary.

**Warning signs:**
- Exported photos display differently in third-party apps vs. Photos app.
- Exported HEIC files have no embedded color profile when inspected with `exiftool`.
- GPS / timestamp data missing from saved photos.

**Phase to address:** Export phase.

---

### Pitfall 17: PHPhotoLibrary addOnly vs readWrite — Wrong Entitlement for Re-Edit Flow

**What goes wrong:**
The existing app requests `.addOnly` Photos permission, which is correct for the current save-to-Photos flow. If you add a "re-edit from library" feature that reads PHAssets directly from the user's Photos library (not via `PhotosPicker`), you must request `.readWrite` permission. Requesting `.readWrite` triggers a more invasive permission dialog (full library access) that users increasingly deny.

Critically: if your `Info.plist` has only `NSPhotoLibraryAddUsageDescription` but not `NSPhotoLibraryUsageDescription`, requesting `.readWrite` will crash at runtime on iOS 17 with a missing key exception — no crash log, just a silent abort.

**How to avoid:**
- For the in-app library feature: store your own copies in the app container and load from there, avoiding PHAsset read access entirely. This sidesteps the permission escalation.
- If PHAsset read is needed: add both `NSPhotoLibraryAddUsageDescription` AND `NSPhotoLibraryUsageDescription` to `Info.plist` before submitting to TestFlight.
- Use `PhotosPicker` (SwiftUI) for the import flow — it uses the system picker which requires no read permission from your app.

**Warning signs:**
- App crashes with "This app has crashed because it attempted to access privacy-sensitive data without a usage description" when requesting `.readWrite`.
- Users report the permission dialog asking for "full photo library access" when they expected something narrower.

**Phase to address:** Library / Persistence phase.

---

### Pitfall 18: Histogram Computation Causing UI Jank

**What goes wrong:**
A histogram requires reading every pixel of the preview image. If computed synchronously on the main thread, it blocks UI for 50–200ms for a 2048px image. If computed too frequently (e.g., on every slider change), even an async histogram creates a queue of pending computations that cause the histogram display to lag and jump.

Core Image's `CIAreaHistogram` filter can compute histograms GPU-side efficiently, but the result must be read back from the GPU, which introduces a CPU-GPU sync stall if done naively.

**How to avoid:**
- Use `CIAreaHistogram` with a downsampled input (512px long edge is sufficient for display purposes).
- Debounce histogram updates to 200ms after the last slider change — users do not need a live histogram during a drag.
- Read the histogram output asynchronously; do not block the render pipeline on histogram completion.
- Display the histogram as a Canvas draw, not as an `Image(uiImage:)` — avoids UIKit image conversion overhead.

**Warning signs:**
- Slider drag feels "sticky" when histogram panel is visible.
- `os_signpost` shows main thread blocked > 16ms during histogram update.
- Memory usage spikes during histogram display (large intermediate bitmap).

**Phase to address:** Pro Adjustments phase, when histogram is implemented.

---

### Pitfall 19: Layout Shift When Adjustment Panel Opens/Closes

**What goes wrong:**
If the adjustment panel expands from the bottom and the canvas image resizes to accommodate it, the canvas image jumps in position — breaking spatial continuity and feeling "cheap." This is especially noticeable when toggling between adjustments that have different panel heights (e.g., a single exposure slider vs. the full HSL grid).

**How to avoid:**
- Keep the canvas image region a fixed size, independent of panel height. The panel overlaps the canvas rather than pushing it.
- Use `matchedGeometryEffect` or a fixed `.frame` on the canvas container to prevent size negotiation.
- For panel height transitions: animate with `withAnimation(.spring(dampingFraction: 0.7))` and ensure the canvas does not participate in the animation (clip it with `.clipped(antialiased: false)`).

**Warning signs:**
- The image visibly moves when tapping an adjustment category.
- Layout looks correct in Simulator (fast animation masks the jump) but is obvious on a real device.

**Phase to address:** UI scaffolding phase, before adding multiple adjustment panels with varying heights.

---

### Pitfall 20: Custom Slider VoiceOver Not Announcing Value

**What goes wrong:**
SwiftUI's built-in `Slider` announces its value to VoiceOver. Custom sliders (common in photo editors for design reasons — drag handles, gradient tracks, visual feedback) are silent to VoiceOver unless you explicitly add `.accessibilityValue()` and `.accessibilityAdjustableAction()`. A custom slider without these modifiers is completely inaccessible.

**How to avoid:**
- Add to every custom slider:
  ```swift
  .accessibilityLabel("Exposure")
  .accessibilityValue("\(Int(value * 100)) percent")
  .accessibilityAdjustableAction { direction in
      switch direction {
      case .increment: value = min(1, value + 0.05)
      case .decrement: value = max(-1, value - 0.05)
      @unknown default: break
      }
  }
  ```
- Use `.accessibilityRepresentation { Slider(value: $value) }` as a simpler alternative if design permits.
- Test with VoiceOver enabled on a real device before shipping each adjustment.

**Warning signs:**
- VoiceOver focus lands on the slider but says only "adjustable" with no value.
- VoiceOver skips the slider entirely.
- `.accessibilityRepresentation` does not trigger VoiceOver focus correctly (known iOS 17 bug for certain custom views).

**Phase to address:** UI scaffolding phase. Accessibility retrofit is significantly more expensive than building it in.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| `CIContext()` with no Metal device | Simple initialization | 5–20× slower renders, slider lag | Never — one line to fix |
| `CIImage(image:)` without orientation bake | Simpler import code | Silent orientation bugs on export | Never if exporting |
| Store adjustment stack as individual `@Published` Doubles | Easy slider binding | 20+ properties triggering re-renders, migration complexity | Only if < 5 adjustments |
| Filter identified by display name string | Simple data model | Recipes break on rename | Never — use stable UUID |
| Sync PHAsset full-res load on main thread | Simple code path | App freeze 1–5s on large photos | Never |
| `UIImage.jpegData()` for export | One line | Color profile stripped, no EXIF | Only for sharing previews, not for library save |
| Hard-code LUT cube size as 33 | Works with common LUT tools | Silent `CIColorCube` failure | Never — validate at parse |
| No `VersionedSchema` in SwiftData | Less boilerplate | First schema change corrupts production data | Never in a shipped build |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| `CIColorCube` | Pass 33³ LUT data directly | Validate and resample to 32³ or 64³ |
| `CIColorCubeWithColorSpace` | Omit `colorSpace` parameter | Always specify LUT design color space |
| `PHPhotoLibrary.performChanges` | Check only `.authorized` | Also check `.limited`; both allow writes |
| `PHAssetChangeRequest.creationRequestForAsset(from:)` | Assumes metadata is preserved | Use file URL path with `CGImageDestination` for metadata control |
| `CIImage(image:)` | Assumes orientation is baked | Call `.oriented(forExifOrientation:)` explicitly |
| SwiftData `@Model` arrays | Use `[Double]` directly | Wrap in a `Codable` struct and store as `Data` to survive schema changes |
| `CGColorSpaceCreateDeviceRGB()` | Treats it as equivalent to sRGB | Use `CGColorSpace(name: CGColorSpace.sRGB)!` for tagged profiles |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Rendering 2048px on every slider tick | Frame drops, device warmth | Separate 1080px preview path; full-res on export only | Immediately with 3+ filter stages |
| `CIContext()` software renderer | Slow renders even for small images | Create with `MTLCreateSystemDefaultDevice` | Always — 5–20× slower |
| Deep filter graph rebuilt each frame | Render time grows with each new adjustment added | Cache filter objects; only update `inputImage` and changed parameters | After 5+ adjustments |
| Histogram computed on full-res CIImage | UI lag when histogram visible | Downsample to 512px before histogram | Immediately |
| PHAsset full-res load for re-edit | Memory spike + app freeze | Load from app container copy; PHAsset only at export | Every time |
| Unthrottled `@Published` triggering SwiftUI diffs | Sluggish non-canvas UI elements during drag | Isolate canvas view; separate display state from render state | After 10+ properties |

---

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Slider updates image with visible lag | Feels unresponsive vs. VSCO | 1080px live preview, full-res deferred |
| Histogram jumps on every tick | Distracting, suggests instability | 200ms debounce on histogram |
| Canvas jumps when panel opens | Cheap, breaks premium feel | Fixed canvas size, panel overlaps canvas |
| No haptic on filter selection | Flat feel | `UISelectionFeedbackGenerator` on filter tap |
| No haptic on slider zero-crossing | Can't feel "0" without looking | `UIImpactFeedbackGenerator.impactOccurred(intensity:)` at zero |
| Custom slider silent to VoiceOver | Excludes accessibility users | `accessibilityAdjustableAction` + value announcement |
| Dynamic Type XL breaks layout | Text truncates or overlaps | Test at Accessibility Extra Extra Extra Large before shipping |
| Before/after triggered accidentally | Frustrating during normal editing | `LongPressGesture` with minimum 0.4s, not `DragGesture` |
| Missing "saving..." indicator on export | User taps Save twice, gets duplicate | `isSaving` state drives disabled + progress overlay |
| Recipe apply doesn't animate | Abrupt, feels like a glitch | Crossfade the canvas image on Recipe apply |

---

## "Looks Done But Isn't" Checklist

- [ ] **LUT pipeline:** Renders correctly — verify with a known identity LUT that produces pixel-identical output to the original.
- [ ] **Orientation:** Verify a portrait photo taken upright, one taken upside down, and one taken in landscape all export with correct orientation.
- [ ] **Color profile:** Verify exported HEIC has an embedded ICC profile when inspected with `exiftool -ColorSpaceData <file>`.
- [ ] **Recipe stability:** Rename a LUT filter's display name and verify an existing Recipe still applies correctly.
- [ ] **Schema migration:** Add a new adjustment field, increment `VersionedSchema`, and verify old library data loads without crash.
- [ ] **PHAsset permission:** Test with `.limited` Photos access (not just `.authorized`) — save and library display must both work.
- [ ] **CIContext type:** Verify via Instruments GPU Timeline that rendering uses the GPU, not CPU software renderer.
- [ ] **VoiceOver sliders:** Test all custom sliders with VoiceOver on a real device — each must announce its label and current value.
- [ ] **Memory at 10 library items:** Open, edit, and close 10 items in sequence; memory must not grow monotonically.
- [ ] **Rotation + crop roundtrip:** Rotate 45°, crop, export, then re-open in editor — dimensions and framing must match export.

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| LUT in wrong color space (shipped) | HIGH | Audit all shipped LUTs; re-author or add correction matrix; force-update via catalog version; saved Recipes may need re-applying |
| SwiftData migration failure | HIGH | Backup store, write migration stage, test on a copy, ship hotfix; worst case: wipe and rebuild from thumbnail cache |
| CIContext software renderer | LOW | One-line fix in ViewModel init; no data consequences |
| Orientation bug found post-launch | MEDIUM | Fix pipeline; existing saved images in Photos app are already wrong — cannot retroactively fix those |
| Recipes invalidated by filter rename | MEDIUM | Restore old filter ID → name mapping; publish catalog update; notify users with stale Recipes |
| Color profile stripped on export | MEDIUM | Fix export path; previously exported images are affected — inform users, offer re-export |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| LUT in wrong color space | LUT Pipeline | Identity LUT test + neutral gray color check |
| LUT cube dimension mismatch | LUT Pipeline | Unit test: parse known 33-cube file, assert resampled to 32-cube |
| EXIF orientation lost | Core Rendering Foundation | Export 8 orientation variants, check all are correct in Photos |
| sRGB ↔ P3 gamut drift | Core Rendering Foundation | Export saturated red/green patch, compare in Photos vs in-app |
| CIContext software renderer | Core Rendering Foundation | Instruments GPU Frame Capture during slider drag |
| Full-res render on every tick | Core Rendering Foundation | Frame rate remains > 55 FPS during slider drag on oldest target device |
| CIImage retained in closures | Core Rendering Foundation | Instruments Allocations shows stable `CIImage` count during editing |
| SwiftUI excess re-renders | UI Scaffolding | Instruments SwiftUI view body evaluations ≤ 1/frame for non-canvas views |
| Gesture conflicts | Editor Canvas / Gestures | Manual test: simultaneous drag + pinch on canvas with panel open |
| extent.integral drift in free-rotate | Crop / Straighten | Apply 1° then -1° free-rotate; diff output against original — must match |
| Transform order regression | Core Rendering Foundation | Vignette center test after rotation: must remain at image center |
| SwiftData schema migration | Library / Persistence | Open v1 store with v2 schema; verify no crash, no data loss |
| Recipe filter ID instability | Recipes | Rename filter display name; saved Recipe must still apply correctly |
| Thumbnail orphan | Library / Persistence | Delete source asset from Photos; library item shows "source unavailable" gracefully |
| PHAsset memory spike | Library / Persistence | Memory profiler stays < 200MB after opening 5 library items |
| HEIC color profile stripped | Export | `exiftool` check on exported HEIC confirms embedded ICC profile |
| addOnly vs readWrite crash | Library / Persistence | Confirm `Info.plist` has both keys before adding any PHAsset read call |
| Histogram jank | Pro Adjustments | Frame rate stays > 55 FPS with histogram visible during drag |
| Layout shift on panel open | UI Scaffolding | Visual inspection: canvas must not move when tapping adjustment category |
| VoiceOver silence on custom sliders | UI Scaffolding | VoiceOver announces label + value for every custom slider |

---

## Sources

- Apple Developer Documentation: `CIColorCubeWithColorSpace`, `CIImage.oriented(forExifOrientation:)`, `PHPhotoLibrary`, `SwiftData MigrationStage` — https://developer.apple.com/documentation/coreimage
- Color Management in Core Image series (JuniperPhoton, 2024): https://juniperphoton.substack.com/p/color-management-across-apple-frameworks-cf7
- CIColorCube data format deep-dive: https://chibicode.org/?p=57
- CIImage orientation handling: https://chibicode.org/?p=208
- UIImage orientation on iOS: https://harshil.net/blog/image-orientation/
- CIImage orientation fix examples: https://github.com/FlexMonkey/CIImage-UIImage-Orientation-Fix
- SwiftData migration gotchas: https://atomicrobot.com/blog/an-unauthorized-guide-to-swiftdata-migrations/
- WWDC23: Migrate to SwiftData: https://developer.apple.com/videos/play/wwdc2023/10189/
- WWDC24: Custom visual effects with SwiftUI (gesture improvements): https://developer.apple.com/videos/play/wwdc2024/10151/
- SwiftUI excess re-render prevention (NonReactiveState): https://tomaskafka.medium.com/improving-swiftui-performance-managing-view-state-without-unnecessary-redraws-1ea1399967fb
- SwiftUI gesture conflicts: https://fatbobman.com/en/posts/swiftuigesture/
- PHImageManager memory management: https://copyprogramming.com/howto/phimagemanager-class
- SwiftUI VoiceOver gotchas: https://www.deque.com/blog/swiftui-accessibility-goodies-gotchas-part-2/
- CIColorCube LUT loading forum thread: https://developer.apple.com/forums/thread/696743
- ColorCube library (PNG LUT → CIColorCube): https://github.com/muukii/ColorCube
- PHPhotoLibrary permission handling: https://swiftsenpai.com/development/photo-library-permission/

---
*Pitfalls research for: Premium iOS photo editor (SwiftUI + Core Image + LUTs)*
*Researched: 2026-05-03*

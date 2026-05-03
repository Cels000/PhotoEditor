# Stack Research

**Domain:** Premium SwiftUI iOS photo editor (VSCO Pro-style, local-only, no backend)
**Researched:** 2026-05-03
**Confidence:** HIGH (Core Image, export, persistence) / MEDIUM (curves UI, histogram, crop package)

---

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| SwiftUI | iOS 17+ | All UI surfaces | Already in use; iOS 17 adds `@Observable`, improved animation APIs, `onChange(of:initial:)` — no reason to revert to UIKit |
| Core Image | iOS 17+ | Filter graph, LUTs, all adjustments | GPU-accelerated, composable filter DAG; every adjustment needed (exposure, curves, HSL, grain, vignette, sharpen) has a built-in CI filter; Metal-backed context gives GPU acceleration for free |
| Metal (indirect) | iOS 17+ | CIContext render backend | Use Metal-backed `CIContext` for GPU execution; never write raw Metal shaders for this scope — CI already uses Metal internally |
| Accelerate / vImage | iOS 17+ | Histogram calculation for UI | `vImageHistogramCalculation_ARGB8888` produces per-channel RGBA histograms efficiently on CPU; only used for UI display, not in render path |
| SwiftData | iOS 17+ | Persistence for library + Recipes | Native Swift, zero boilerplate, SwiftUI `@Query` live-updates for free; iOS 17+ is our floor so no compatibility concern; sufficient for this data model (no NSCompoundPredicate needed) |
| PhotosUI / Photos | iOS 17+ | Import (`PhotosPicker`) + export (`PHPhotoLibrary`) | Already used; `PhotosPickerItem` async load with `Transferable` is the correct modern API |
| ImageIO | iOS 17+ | Full-resolution export to JPEG/HEIC/PNG | `CGImageDestination` with `kCGImageDestinationLossyCompressionQuality` gives format-agnostic quality control; the only correct path for HEIC |

### Supporting Libraries (SPM)

| Library | SPM URL | Version | Purpose | When to Use |
|---------|---------|---------|---------|-------------|
| Mantis | https://github.com/guoyingtao/Mantis.git | 2.31.1 | Crop + free rotate + straighten UI | Use for the crop/straighten tool; provides angle ruler, aspect ratio presets, and Apple Photos-style perspective correction out of the box |
| SwiftCube | https://github.com/ronan18/SwiftCube | 1.0.1 | `.cube` file parsing → `CIFilter` | Use to parse bundled `.cube` LUT files into `CIColorCubeWithColorSpace` filters; saves writing a custom parser |

### No SPM Package Needed (Build Custom)

| Component | Build Approach | Rationale |
|-----------|---------------|-----------|
| Tone curves UI | SwiftUI `Canvas` + `DragGesture` | No maintained SPM package matches the exact Lightroom-style interactive 5-point cubic spline; building in Canvas is ~150 LOC |
| Histogram display | SwiftUI `Canvas` rendering vImage output | Same reason — render the `[UInt]` arrays from vImage directly into Canvas bars; trivial |
| HSL panel | Native SwiftUI `Slider` grid | Pure data, no custom drawing needed |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| Xcode 16+ | Build / profile | Required for iOS 17+ SDK; use Instruments → Core Image profiler to measure filter graph cost |
| cifilter.io | CI filter reference | Browser-based filter explorer with live parameter tweaking; indispensable during filter chain design |
| Resolve / DaVinci Free | LUT creation | Author 33-point `.cube` files here, then resample to 64-point for iOS (see LUT section) |

---

## Architecture: Rendering Pipeline

### Two-Context Strategy

Create **two separate `CIContext` instances** — never share them:

```swift
// Preview context — Metal-backed, low-overhead
let previewContext = CIContext(options: [
    .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
    .outputColorSpace:  CGColorSpace(name: CGColorSpace.displayP3)!,
    .useSoftwareRenderer: false
])

// Export context — same config, but used only on background Task
let exportContext = CIContext(options: [
    .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
    .outputColorSpace:  CGColorSpace(name: CGColorSpace.displayP3)!,
    .useSoftwareRenderer: false
])
```

`CIContext` is heavyweight — create once at app launch, reuse forever.

### Live Preview Pipeline

```
Source CIImage (downsampled to ≤1024px long-edge for preview)
  → LUT filter (CIColorCubeWithColorSpace, strength via CIColorMatrix blend)
  → Exposure (CIExposureAdjust)
  → Color controls (CIColorControls: saturation, contrast)
  → Color temp/tint (CITemperatureAndTint)
  → Highlights/Shadows (CIHighlightShadowAdjust)
  → Vibrance (CIVibrance)
  → Tone curve (CIToneCurve × 4: composite + R + G + B)
  → HSL (CIHueAdjust per-channel via channel-masked CIColorMatrix)
  → Vignette (CIVignette)
  → Grain (CIRandomGenerator → CIColorMatrix → blend)
  → Sharpen (CIUnsharpMask)
  → Output CIImage → createCGImage → UIImage → SwiftUI Image
```

- Keep source `CIImage` at **≤1024px** long-edge for preview. Never decode at full resolution for live preview.
- Import pipeline: `PhotosPickerItem` → `Data` → `CIImage(data:options:[.applyOrientationProperty: true])`. Store the original `Data` reference for full-res export. Do NOT use `UIImage` as an intermediate (loses color space metadata).
- Debounce slider changes with a 30ms coalescing task (same pattern already in `scheduleRender()`).
- `createCGImage(_:from:format:colorSpace:)` — pass `kCIFormatRGBAh` (16-bit float) for preview to preserve P3 headroom. Fall back to `kCIFormatRGBA8` only if memory pressure forces it.

### Full-Resolution Export Pipeline

```
Original Data → CIImage(data:options:[.applyOrientationProperty: true])
  → Same filter graph (re-applied at full resolution)
  → exportContext.createCGImage(...)
  → CGImageDestination → JPEG / HEIC / PNG with quality param
```

- Run entirely in a detached `Task` off the main actor.
- Apply the same `EditState` struct that drove the preview — no separate code path.
- Never export the downsampled preview image. Always re-render from source `Data`.

---

## LUT Handling

### Valid CIColorCube Dimensions

Apple only accepts: **4, 16, 64, 256**. The commonly-distributed 33-point `.cube` files (DaVinci Resolve default) will **crash or produce garbage**. Must resample to 64.

**Decision: Use 64-point cubes.**

- 33-point: common in the wild but not a valid iOS dimension. Must be resampled.
- 64-point: valid, good quality (~1MB data blob per LUT), acceptable memory (~1MB × 30 LUTs = 30MB, loaded lazily).
- 256-point: valid but 64MB per LUT — never use for mobile.

### .cube File Strategy

- **Ship LUTs as bundled `.cube` files** in the app bundle (not PNG strips). `.cube` is the industry standard format; tools like DaVinci Resolve, Lightroom, and Photoshop all export `.cube` natively.
- Use **SwiftCube 1.0.1** to parse `.cube` → `CIColorCubeWithColorSpace` filter. It handles the float-triplet parsing and wraps the correct `CIFilter`.
- Set `inputColorSpace` to `CGColorSpace(name: CGColorSpace.sRGB)!` when creating `CIColorCubeWithColorSpace`. Most LUTs are authored in sRGB; using device RGB drops color accuracy.
- **Filter strength** (0–100%): blend original and LUT-filtered image using `CIColorMatrix` or a custom `CIBlendWithMask`. A simple linear interpolation via `CIFilter(name: "CISourceOverCompositing")` is insufficient — use `CIColorMatrix` on the LUT output with alpha scaled by strength, composited over the original.

### LUT Authoring Workflow

1. Author in DaVinci Resolve Free as 33-point `.cube`.
2. Resample to 64-point using a desktop Python script (`colour-science` library: `colour.io.write_LUT` with `LUT3D` resampled to 64-point).
3. Bundle the 64-point `.cube` in `App/Resources/LUTs/`.
4. Parse lazily at first use; cache the `Data` blob in a dictionary keyed by filter name.

---

## Persistence: SwiftData

**Decision: SwiftData (iOS 17+).**

### Model Structure

```swift
@Model final class LibraryItem {
    var id: UUID
    var sourceAssetIdentifier: String   // PHAsset localIdentifier for re-fetch
    var sourceBookmarkData: Data?        // Security-scoped bookmark for imported files
    var editState: Data                  // JSON-encoded EditState struct
    var thumbnailData: Data             // Pre-rendered JPEG thumbnail ~200px
    var createdAt: Date
    var updatedAt: Date
}

@Model final class Recipe {
    var id: UUID
    var name: String
    var editState: Data                 // JSON-encoded EditState (no source image)
    var sortOrder: Int
    var createdAt: Date
}
```

- **Do not store raw pixel data in SwiftData.** Store source references + edit parameters only.
- `EditState` is a plain `Codable` struct encoding all slider values, LUT name, curve points, crop rect, etc. Serialize to JSON `Data` for the model property.
- SwiftData `@Query` in SwiftUI views provides live-updating library grid automatically.
- Complex predicates are not needed here — library items are sorted by date, recipes by `sortOrder`. The current SwiftData predicate limitations do not affect this schema.
- Recipe sharing: encode `EditState` as JSON, wrap in a custom `.photorecipe` UTType file, share via `UIActivityViewController`.

### Why Not Core Data

Core Data is not wrong here, but the overhead (`.xcdatamodeld` files, `NSManagedObjectContext`, `NSFetchedResultsController` boilerplate) is unjustified for a schema with two entity types. SwiftData + `@Query` is idiomatic for SwiftUI and eliminates ~200 lines of plumbing. The complex predicate gaps in SwiftData don't apply to this simple schema.

### Why Not Files-Only

A flat file approach (JSON sidecar per photo) makes the library grid difficult to query (sort, filter, paginate). SwiftData handles this and provides automatic change propagation to SwiftUI.

---

## Export: ImageIO

```swift
func export(cgImage: CGImage, format: ExportFormat, quality: Double) throws -> Data {
    let mutableData = NSMutableData()
    let utType: CFString = switch format {
        case .jpeg: kUTTypeJPEG
        case .heic: UTType.heic.identifier as CFString
        case .png:  kUTTypePNG
    }
    guard let dest = CGImageDestinationCreateWithData(mutableData, utType, 1, nil) else {
        throw ExportError.destinationCreationFailed
    }
    let options: [CFString: Any] = [
        kCGImageDestinationLossyCompressionQuality: quality,   // 0.0–1.0; ignored for PNG
        kCGImagePropertyColorModel: kCGImagePropertyColorModelRGB
    ]
    CGImageDestinationAddImage(dest, cgImage, options as CFDictionary)
    guard CGImageDestinationFinalize(dest) else {
        throw ExportError.finalizeFailed
    }
    return mutableData as Data
}
```

- **HEIC requires iOS 11+** — fine for our iOS 17 floor.
- **PNG quality param is ignored** — always lossless; don't show the quality slider for PNG.
- For JPEG, quality 0.85 is a good default (matches Apple Photos JPEG export).
- Color space: ensure the `CGImage` passed in carries the Display P3 color profile. Pass `CGColorSpace(name: CGColorSpace.displayP3)` to `createCGImage` in the export context.
- Resize before export: compute target size from user's preset (full / web / story / custom long-edge), apply `CGAffineTransform` on the `CIImage` before final render.

---

## Crop + Free Rotate UI

**Decision: Mantis 2.31.1 via SPM.**

- Provides angle ruler, free rotate, straighten, aspect ratio presets, flip — matches the feature set exactly.
- Has a `ImageCropperView` SwiftUI wrapper; no UIKit bridging required.
- iOS 12+ minimum — fine for iOS 17 target.
- Actively maintained (last release recent per GitHub).
- The crop result is a `UIImage`; convert to `CIImage` for integration with the filter graph.

**What NOT to use:**
- `TOCropViewController` — UIKit only, requires `UIViewControllerRepresentable` wrapping, no free-rotate ruler.
- SwiftyCrop — simpler feature set, no straighten ruler, designed more for avatar cropping than photo editing.
- Custom implementation — building the rubber-band crop overlay + angle ruler + grid from scratch is 500+ LOC with subtle gesture math; not worth it for this scope.

---

## Tone Curves UI

**Decision: Custom SwiftUI `Canvas` component.**

- `CIToneCurve` accepts 5 control points (`inputPoint0`…`inputPoint4`) as `CIVector(x:y:)`, each normalized 0–1. The filter uses a cubic spline through these points.
- UI: draw a `Path` cubic spline through the 5 draggable control points on a `Canvas`. Use `DragGesture` attached to each point's hitbox. Match Lightroom's approach: composite channel (white), then R, G, B tabs.
- Map the UI's 5 drag positions directly to `inputPoint0`…`inputPoint4` — no intermediate representation needed.
- For per-channel curves: apply `CIToneCurve` four times in the filter graph (composite + R, G, B separately), each with its own 5-point state.

**What NOT to use:**
- No SPM package covers this specific use case with the right visual style. Third-party curve editors are either UIKit or designed for animation timing (not photo tone curves).

---

## Histogram UI

**Decision: `vImage` for calculation, SwiftUI `Canvas` for display.**

```swift
// Calculate on background Task, publish result to SwiftUI
func calculateHistogram(from ciImage: CIImage) async -> HistogramData {
    // Render CIImage to a small CVPixelBuffer (max 512px)
    // Convert to vImage_Buffer
    // Call vImageHistogramCalculation_ARGB8888
    // Return [UInt] arrays for R, G, B, Luminance
}
```

- Run histogram calculation on a background queue, debounced to ~100ms after render settles.
- Display as `Canvas` overlay bars — 256 buckets, RGBA channels as colored semi-transparent fills.
- `CIAreaHistogram` (CI built-in) is an alternative but requires an extra CI render pass and produces a 1×256 image that needs further decoding; vImage on a small downsampled buffer is simpler and faster for a UI histogram.

---

## Color Management

**Decision: Extended Linear sRGB working space, Display P3 output.**

- **CIContext working color space:** `CGColorSpace.extendedLinearSRGB` — allows values outside 0–1 during intermediate filter operations (important for exposure, highlights). This is Apple's own recommendation for photo editing contexts.
- **Output color space:** `CGColorSpace.displayP3` — iPhone 8+ all have P3 displays; rendering to sRGB and letting the display upconvert loses color accuracy.
- **Import:** Load `CIImage` with `.applyOrientationProperty: true` and do NOT strip the embedded ICC profile. P3-captured iPhone photos will carry the Display P3 profile; CI respects it if the working space is extended.
- **Export:** Pass `CGColorSpace.displayP3` to `CGImageDestinationAddImageAndMetadata` options so the exported file carries the correct ICC profile.
- **EDR (Extended Dynamic Range):** Not in scope for v1. Editing EDR (HDR) content requires `EDR` pixel formats (`kCIFormatRGBAh` + `headroom` metadata) and a separate UI consideration for HDR preview. Defer to v2 if ever needed.
- **Do NOT use `CGColorSpaceCreateDeviceRGB`** for the CIContext — this is untagged, bypasses color management, and produces inconsistent results across devices.

---

## Accessibility

**Sliders:**
- Native SwiftUI `Slider` has VoiceOver adjustable action built in (swipe up/down increments).
- Add `.accessibilityLabel("Exposure")` and `.accessibilityValue("\(value, format: .number.precision(.fractionLength(1)))")` to each slider for meaningful announcements.
- Group label + slider with `.accessibilityElement(children: .combine)` if the label and slider are siblings — prevents VoiceOver from announcing them separately.

**Filter strip:**
- Each filter button: `.accessibilityLabel("\(filterName) filter")` + `.accessibilityAddTraits(.isSelected)` when active.

**Adjustment panels:**
- Respect `@Environment(\.accessibilityReduceMotion)` — disable the before/after transition animation when true.
- Use `@ScaledMetric` for icon sizes; slider track and thumb size scale with Dynamic Type automatically.

**Curves editor:**
- Custom canvas control: add `.accessibilityElement(children: .ignore)`, `.accessibilityLabel("Tone curve")`, `.accessibilityValue("Shadows \(p0.y), Midtones \(p2.y), Highlights \(p4.y)")`, and `.accessibilityAdjustableAction` with coarse increment/decrement on the selected point.

---

## Alternatives Considered

| Recommended | Alternative | Why Not |
|-------------|-------------|---------|
| Core Image filter graph | MetalPetal | MetalPetal is more powerful but requires understanding Metal concepts, has more SPM build overhead, and all needed filters exist in CI. Only use MetalPetal if CI profiling shows a bottleneck that CI can't solve (unlikely for photo editing). |
| Core Image filter graph | GPUImage 3 | Unmaintained since ~2019; superseded by Core Image + Metal. Do not use. |
| SwiftData | Core Data | Core Data is fine but verbose; SwiftData's limitations (no NSCompoundPredicate) don't affect this two-entity schema. |
| SwiftData | Files-only JSON | Harder to query for library grid; sorting/pagination requires manual management. |
| Mantis | TOCropViewController | UIKit-only, no free-rotate ruler, older API surface. |
| Mantis | Custom crop UI | Hundreds of lines of gesture math for something a maintained library solves. |
| CGImageDestination | UIImage.jpegData / UIImage.pngData | `UIImage.jpegData` does not support HEIC; quality parameter is JPEG-only; no format abstraction. Use only for thumbnails, never for export. |
| vImage histogram | CIAreaHistogram | CI route requires an extra GPU render pass and pixel readback to decode the 1×256 output image. vImage on a small downsampled buffer is more direct and doesn't block the GPU context. |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `CIPhotoEffect*` filters (current code) | Generic, non-film-look, not parameterizable for strength — they are the Apple default that makes apps look template-y | `CIColorCubeWithColorSpace` with custom `.cube` LUTs |
| 33-point `.cube` files directly | Not a valid `CIColorCube` dimension on iOS; crashes at runtime | Resample to 64-point before bundling |
| 256-point LUTs | 64MB per LUT × 30 filters = ~2GB memory; kills the app | 64-point (1MB each, 30MB total, manageable) |
| `UIImage` as the CI pipeline intermediate | Loses ICC color profile; triggers unnecessary CPU decompression; introduces sRGB assumption | Keep everything as `CIImage` through the filter graph; convert to `UIImage` / `CGImage` only at display/export time |
| `UIGraphicsImageRenderer` for export | Always writes sRGB JPEG, no HEIC support, no quality param, strips color profiles | `CGImageDestination` via ImageIO |
| `CIContext()` (default init) | Creates a CPU-only software renderer; 10–100× slower than Metal | `CIContext(options: [.useSoftwareRenderer: false])` with Metal backend |
| Shared/singleton `CIContext` across preview + export | Export render on background task can race with preview render on main actor | Two separate contexts: one for preview, one for export |
| `CGColorSpaceCreateDeviceRGB` for context | Untagged color space; bypasses ICC profile handling; colors shift between devices | `CGColorSpace(name: CGColorSpace.extendedLinearSRGB)` for working space |
| GPUImage 3 | Unmaintained; last commit ~2019 | Core Image |
| CocoaLUT (CocoaPods-only) | CocoaPods only, no SPM, archived/unmaintained | SwiftCube (SPM, maintained) |

---

## Version Compatibility

| Package | iOS Min | Swift Min | Notes |
|---------|---------|-----------|-------|
| Mantis 2.31.1 | iOS 12 | Swift 5 | Well within our iOS 17 floor |
| SwiftCube 1.0.1 | iOS 13 | Swift 5 | Well within our iOS 17 floor |
| SwiftData | iOS 17 | Swift 5.9 | Matches our deployment target exactly |
| CIToneCurve | iOS 9 | — | Built-in CI filter, no version concern |
| CIColorCubeWithColorSpace | iOS 10 | — | Built-in CI filter, no version concern |
| CGImageDestination HEIC | iOS 11 | — | Well within iOS 17 floor |

---

## Sources

- Apple Developer Docs — `CIColorCube` valid dimensions (4, 16, 64, 256): https://developer.apple.com/documentation/coreimage/cicolorcube
- Apple Developer Docs — `CIColorCubeWithColorSpace`: https://developer.apple.com/documentation/coreimage/cicolorcubewithcolorspace
- Apple Developer Docs — `CIToneCurve` (5-point cubic spline, `inputPoint0`–`inputPoint4`): https://developer.apple.com/documentation/coreimage/citonecurve
- Apple Developer Docs — `CIContext`: https://developer.apple.com/documentation/coreimage/cicontext
- Apple WWDC20 — "Optimize the Core Image pipeline for your video app": https://developer.apple.com/videos/play/wwdc2020/10008/
- Apple Developer Docs — `CGImageDestinationCreateWithData` / `kCGImageDestinationLossyCompressionQuality`: https://developer.apple.com/documentation/imageio/cgimagedestinaion
- Apple Developer Docs — `CIContext.writeHEIFRepresentation`: https://developer.apple.com/documentation/coreimage/cicontext/2902266-writeheifrepresentation
- SwiftData WWDC24 — new `#Expression` macro, iOS 18 improvements: https://developer.apple.com/videos/play/wwdc2024/10137/
- Michael Tsai blog — SwiftData iOS 17 predicate bugs: https://mjtsai.com/blog/2024/06/04/swiftdata-issues-in-macos-14-and-ios-17/
- GitHub — Mantis 2.31.1 (crop library): https://github.com/guoyingtao/Mantis
- GitHub — SwiftCube 1.0.1 (.cube LUT parser): https://github.com/ronan18/SwiftCube
- Apple Developer Docs — vImage histogram: https://developer.apple.com/documentation/accelerate/specifying-histograms-with-vimage
- JuniperPhoton Substack — Color management across Apple frameworks: https://juniperphoton.substack.com/p/color-management-across-apple-frameworks-cf7
- Apple Accessibility WWDC24 — SwiftUI accessibility improvements: https://developer.apple.com/videos/play/wwdc2024/10073/
- LUT Cubes and Shaders (optional.is, 2025): https://optional.is/required/2025/08/27/lut-cubes-and-shaders/
- cvs-health iOS accessibility techniques — adjustable action patterns: https://github.com/cvs-health/ios-swiftui-accessibility-techniques

---
*Stack research for: Premium SwiftUI iOS photo editor (VSCO Pro-style)*
*Researched: 2026-05-03*

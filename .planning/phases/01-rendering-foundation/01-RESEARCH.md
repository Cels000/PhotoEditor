# Phase 1: Rendering Foundation - Research

**Researched:** 2026-05-03
**Domain:** Core Image pipeline replacement — Metal CIContext, RenderEngine actor, AdjustmentStack model, PipelineBuilder, correct import path
**Confidence:** HIGH (all decisions locked in prior research; this document translates them into a concrete file plan)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **CIContext:** Two contexts — `previewContext` and `exportContext`. Both Metal-backed via `MTLCreateSystemDefaultDevice()` + `CIContext(mtlDevice:)`. Created once at app launch.
- **RenderEngine:** Swift `actor` with cancellable preview tasks. Debounce: 30–40 ms.
- **Preview downsampling:** 1080px long edge (per PITFALLS guidance).
- **AdjustmentStack:** flat `Codable` struct with `schemaVersion: Int` field. Persisted to SwiftData later as JSON `Data` blob.
- **PipelineBuilder:** Pure function. No state. Deterministic ordering: LUT → light → color → HSL → curves → split toning → effects → crop. Phase 1 only needs LUT-placeholder + light scaffolding; the full filter chain fills in over later phases — but the API surface accepts the full stack today.
- **Import path:** `Data → CIImage(data:options: [.applyOrientationProperty: true])`. No UIImage intermediate. Original PHAsset reference retained for future re-load (Phase 4).
- **Color management:** Working space `extendedLinearSRGB` (CGColorSpace.extendedLinearSRGB), output color space inferred from source.
- **Existing pipeline removal:** The current `PhotoEditorViewModel`'s `CIPhotoEffect*` filter switch + scheduleRender flow is fully removed in this phase. The 10 built-in filters disappear; the filter strip will be empty until Phase 2 lands the LUT pipeline.
- **No SwiftData yet:** Persistence lives in Phase 4. AdjustmentStack is in-memory only for Phase 1.

### Claude's Discretion
All implementation choices defer to the architecture and stack research already produced. No alternative approaches to explore — the research corpus is the spec.

### Deferred Ideas (OUT OF SCOPE)
- LUT loader, .cube parser → Phase 2
- Full adjustment panels (HSL, curves, etc.) → Phase 3
- SwiftData library persistence → Phase 4
- CGImageDestination export with format/quality controls → Phase 5
- Recipe save/share → Phase 6
- Haptics, animations, accessibility audit → Phase 7
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| RENDER-01 | App imports a photo from the iOS photo library preserving original orientation and color profile (sRGB/Display P3 round-trip without drift) | Import path: `Data → CIImage(data:options:[.applyOrientationProperty: true])`. No UIImage intermediate. Orientation baked via `.oriented(forExifOrientation:)` immediately after creation. |
| RENDER-02 | All edits apply non-destructively — the source image is never mutated; every edit is reversible | AdjustmentStack is a value type (struct). Source CIImage is read-only. PipelineBuilder is pure — same inputs always produce same output, source data never mutated. |
| RENDER-03 | Live preview stays responsive (visibly smooth) while a slider is being dragged, by rendering at a downsampled resolution (≤1080px long edge) | Separate preview CIImage downsampled to 1080px long edge. Debounced render at 40ms. RenderEngine actor serializes renders. |
| RENDER-04 | Full-resolution rendering only runs on export (or thumbnail generation), never per-slider-tick | Two-path architecture: preview path uses 1080px source; export path loads full-res from stored Data. No full-res call inside stackDidChange(). |
| RENDER-05 | All rendering uses a Metal-backed CIContext; software rendering never engages | Both contexts created via `CIContext(mtlDevice: MTLCreateSystemDefaultDevice()!, options: [...])`. `.useSoftwareRenderer: false` set explicitly. |
| RENDER-06 | Edit state is captured in a Codable adjustment-stack model, versioned with a schema integer for forward-compatibility | AdjustmentStack struct: `Codable`, `Equatable`, `schemaVersion: Int = 1`. All sub-structs Codable. Static `.identity` default. |
</phase_requirements>

---

## Summary

Phase 1 replaces the existing `PhotoEditorViewModel`'s render pipeline — specifically the `CIPhotoEffect*` filter switch, the untagged `CIContext()` software renderer, and the UIImage-based import path — with the premium foundation the rest of the app builds on. The prior project-level research (STACK.md, ARCHITECTURE.md, PITFALLS.md) has already locked every architectural decision; this phase research translates those decisions into a concrete file-by-file implementation plan.

The three highest-risk items for this phase are: (1) correctly wiring the three existing slider bindings (`brightness`, `contrast`, `saturation`) through the new `AdjustmentStack` without breaking the ContentView UI shell, (2) ensuring the import path bakes EXIF orientation correctly from day one (the current `downsample()` function bakes orientation via `UIGraphicsImageRenderer` as a side effect — the new path uses `CIImage(data:options:)` which does NOT bake it geometrically unless `oriented(forExifOrientation:)` is called explicitly), and (3) verifying Metal context activation at runtime (cannot be verified on Linux — requires on-device Instruments run).

The existing `ContentView.swift` keeps its entire visual shell unchanged: the layout, the photo picker, the three sliders, the filter strip container, the save button. Only the data bindings and ViewModel internals change.

**Primary recommendation:** Build in strict dependency order — AdjustmentStack → PipelineBuilder → RenderEngine → EditorViewModel (replacement) → ContentView rewiring — because each layer depends on the one before it.

---

## File-by-File Plan

### Files to CREATE

| File | Location | Purpose |
|------|----------|---------|
| `RenderEngine/RenderEngine.swift` | `PhotoEditor/RenderEngine/` | Swift actor owning both CIContexts; `renderPreview` and `renderExport` methods |
| `RenderEngine/PipelineBuilder.swift` | `PhotoEditor/RenderEngine/` | Pure enum namespace; `build(stack:source:) -> CIImage`; Phase 1 implements light scaffold only |
| `Editor/AdjustmentStack.swift` | `PhotoEditor/Editor/` | Full Codable struct hierarchy (all sub-structs including those not yet wired); `schemaVersion`; `.identity` |
| `Editor/EditorViewModel.swift` | `PhotoEditor/Editor/` | `@MainActor @Observable` class replacing `PhotoEditorViewModel`; owns `AdjustmentStack`, debounced render |
| `Editor/ImageImporter.swift` | `PhotoEditor/Editor/` | `importImage(from data: Data) async throws -> ImportedImage`; returns preview CIImage + source Data + orientation |

### Files to MODIFY

| File | What Changes | What Stays |
|------|-------------|------------|
| `PhotoEditor/ContentView.swift` | Replace `@StateObject var viewModel: PhotoEditorViewModel` with `@State var viewModel: EditorViewModel`. Rewire `$viewModel.brightness` → `$viewModel.stack.light.exposure`, `$viewModel.contrast` → `$viewModel.stack.light.contrast`, `$viewModel.saturation` → `$viewModel.stack.color.saturation`. The `loadSelectedPhoto()` function calls `viewModel.importPhoto(data:)` instead of `viewModel.loadImage(_:)`. The filter strip `ForEach` loops over an empty array (no items until Phase 2). | Entire visual layout: `editorPreview`, `actionBar`, `adjustments`, `saveSection` view builders. `AdjustmentSlider` component. Both button styles. The `Binding<Bool>(present:)` extension. Alert modifiers. |
| `PhotoEditor/PhotoEditorViewModel.swift` | **Deleted entirely.** Its `downsample()` helper is the only reusable piece — extract it to `ImageImporter.swift` first. | Nothing — file is removed. |
| `PhotoEditor/PhotoEditorApp.swift` | No changes needed unless dependency injection root is added (defer to later phases). | Entire file. |

### Files to DELETE

| File | Reason |
|------|--------|
| `PhotoEditor/PhotoEditorViewModel.swift` | Replaced by `EditorViewModel.swift`. The `CIPhotoEffect*` filter enum, `CIContext()` software renderer, and UIImage-based import path are all wrong by design. |

### Directory structure after Phase 1

```
PhotoEditor/
├── PhotoEditorApp.swift          (unchanged)
├── ContentView.swift             (rewired bindings only)
├── Info.plist                    (unchanged)
├── Assets.xcassets/              (unchanged)
├── Editor/
│   ├── AdjustmentStack.swift     (NEW)
│   ├── EditorViewModel.swift     (NEW — replaces PhotoEditorViewModel)
│   └── ImageImporter.swift       (NEW)
└── RenderEngine/
    ├── RenderEngine.swift        (NEW)
    └── PipelineBuilder.swift     (NEW)
```

---

## Concrete API Surface (Signatures)

These are the exact signatures the planner should target. Implementations are not specified here — only the public API surface that other files depend on.

### AdjustmentStack.swift

```swift
// All sub-structs: Codable, Equatable, all fields have default values

struct LightAdjustments: Codable, Equatable {
    var exposure: Double = 0      // EV, -3...+3 → CIExposureAdjust.inputEV
    var contrast: Double = 0      // -1...+1 → CIColorControls.contrast (mapped: 0 = 1.0, +1 = 2.0)
    var highlights: Double = 0    // -1...+1 → CIHighlightShadowAdjust.inputHighlightAmount
    var shadows: Double = 0       // -1...+1 → CIHighlightShadowAdjust.inputShadowAmount
    var whites: Double = 0        // -1...+1 (Phase 3 wires fully)
    var blacks: Double = 0        // -1...+1 (Phase 3 wires fully)
}

struct ColorAdjustments: Codable, Equatable {
    var saturation: Double = 0    // -1...+1 → CIColorControls.saturation (mapped: 0=1.0)
    var vibrance: Double = 0      // -1...+1 → CIVibrance
    var temperature: Double = 0   // -1...+1 (Phase 3 wires)
    var tint: Double = 0          // -1...+1 (Phase 3 wires)
}

// HSL, curves, split toning, grain, vignette, crop sub-structs present but default-valued
// (see ARCHITECTURE.md for full sketch — those signatures are authoritative)

struct AdjustmentStack: Codable, Equatable {
    var schemaVersion: Int = 1
    var filter: FilterSelection? = nil   // Phase 2
    var light = LightAdjustments()
    var color = ColorAdjustments()
    var hsl = HSLAdjustments()
    var curves = ToneCurves()
    var splitToning = SplitToning()
    var grain = GrainSettings()
    var vignette = VignetteSettings()
    var crop = CropSettings()
    var sharpness: Double = 0

    static let identity = AdjustmentStack()
}
```

### RenderEngine.swift

```swift
actor RenderEngine {
    // Both contexts Metal-backed, created in init, never re-created
    private let previewContext: CIContext
    private let exportContext: CIContext

    init()  // creates MTLDevice + both CIContexts with extendedLinearSRGB working space

    // Preview path: source is already downsampled to ≤1080px long edge by caller
    func renderPreview(stack: AdjustmentStack, source: CIImage) throws -> CGImage

    // Export path: source is full-res; called only from save flow
    func renderExport(stack: AdjustmentStack, source: CIImage) throws -> CGImage
}

enum RenderError: Error {
    case noMetalDevice
    case outputEmpty
}
```

### PipelineBuilder.swift

```swift
// nonisolated pure namespace — no stored state, no side effects
enum PipelineBuilder {
    // Phase 1: implements light + color scaffold; all other stages are identity pass-throughs
    static func build(stack: AdjustmentStack, source: CIImage) -> CIImage

    // Individual stage functions (internal, but exposed for unit testing):
    static func applyLight(_ light: LightAdjustments, to image: CIImage) -> CIImage
    static func applyColor(_ color: ColorAdjustments, to image: CIImage) -> CIImage
    // applyLUT, applyHSL, applyCurves, etc. — stub returns image unchanged in Phase 1
}
```

### ImageImporter.swift

```swift
struct ImportedImage {
    let sourceData: Data         // original bytes, retained for full-res export
    let previewCIImage: CIImage  // oriented, downsampled to ≤1080px long edge
    let exportCIImage: CIImage   // oriented, full-res (loaded lazily from sourceData)
}

enum ImageImporter {
    // Loads data, creates CIImage with .applyOrientationProperty, downsample for preview.
    // Throws if data cannot be decoded as an image.
    static func importImage(from data: Data) throws -> ImportedImage

    // Internal: downsample while preserving orientation (replaces old UIGraphicsImageRenderer path)
    static func downsample(_ image: CIImage, maxLongEdge: CGFloat) -> CIImage
}
```

### EditorViewModel.swift

```swift
@MainActor
@Observable
final class EditorViewModel {
    var stack: AdjustmentStack = .identity
    var previewImage: UIImage?        // drives ContentView editorPreview
    var importedImage: ImportedImage? // nil until photo chosen
    var isSaving: Bool = false
    var errorMessage: String?
    var successMessage: String?

    private let engine: RenderEngine
    private var renderTask: Task<Void, Never>?

    init(engine: RenderEngine = RenderEngine())

    func importPhoto(data: Data) async        // called from ContentView.loadSelectedPhoto()
    func stackDidChange()                     // called from slider .onChange; debounces render
    func saveImage() async                    // full-res export + PHPhotoLibrary save
    func resetAdjustments()                   // sets stack = .identity, triggers render
}
```

---

## ContentView Rewiring Details

The ContentView changes are purely mechanical — no layout changes, no new views.

**1. ViewModel type change:**
```swift
// BEFORE
@StateObject private var viewModel = PhotoEditorViewModel()

// AFTER  
@State private var viewModel = EditorViewModel()
// Note: @Observable requires @State, not @StateObject
```

**2. Photo load:**
```swift
// BEFORE (in loadSelectedPhoto)
if let data = try await selectedItem.loadTransferable(type: Data.self),
   let image = UIImage(data: data) {
    viewModel.loadImage(image)
}

// AFTER
if let data = try await selectedItem.loadTransferable(type: Data.self) {
    await viewModel.importPhoto(data: data)
}
```

**3. Slider bindings — the three existing sliders map to AdjustmentStack fields:**

| Old binding | New binding | Notes |
|-------------|-------------|-------|
| `$viewModel.brightness` (-1...1) | `$viewModel.stack.light.exposure` | Range stays -1...1 (maps to EV) |
| `$viewModel.contrast` (0.5...2) | `$viewModel.stack.light.contrast` | Slider range changes to -1...1; 0 = neutral |
| `$viewModel.saturation` (0...2) | `$viewModel.stack.color.saturation` | Slider range changes to -1...1; 0 = neutral |

The `AdjustmentSlider` component's `range:` parameter in ContentView must be updated alongside each binding. The visual appearance is unchanged.

**4. Filter strip — temporarily empty:**
```swift
// BEFORE
ForEach(PhotoEditorViewModel.FilterPreset.allCases) { ... }

// AFTER — empty until Phase 2
// ForEach([String]()) { _ in EmptyView() }
// Or: keep the section header "Filters" but show placeholder text "Coming in Phase 2"
```

**5. `editorPreview` display property:**
```swift
// BEFORE: viewModel.editedImage ?? viewModel.sourceImage
// AFTER:  viewModel.previewImage
// (EditorViewModel.previewImage is always non-nil once a photo is loaded;
//  it shows the render result or the source preview image if no edits applied)
```

**6. Rotate buttons — temporarily stub or remove:**
The old `rotateLeft()` / `rotateRight()` mutated `rotationAngle: Double`. Phase 1 does not implement crop/rotate (deferred to Phase 3). Options: (a) keep the buttons but disable them, or (b) remove them from ContentView. Recommended: disable with `.disabled(true)` and add a TODO comment. Do not remove — Phase 3 will re-enable them against `AdjustmentStack.crop.clockwiseRotations`.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Metal GPU acceleration for CIContext | Custom Metal shaders | `CIContext(mtlDevice:)` | CI already uses Metal internally; raw Metal shaders are not needed for this scope |
| Orientation correction | Custom CGAffineTransform rotation logic | `CIImage.oriented(forExifOrientation:)` | Built-in, handles all 8 EXIF orientations correctly; custom transforms get edge cases wrong |
| Image downsampling | UIGraphicsImageRenderer (old path) | `CIImage.transformed(by:)` with a scale transform on the CIImage directly, then render | Pure CI path, no UIKit round-trip, preserves color space |
| Debounce | Custom timer / DispatchQueue.asyncAfter | `Task { try? await Task.sleep(for:) }` + `renderTask?.cancel()` | Structured concurrency; automatic cancellation on re-trigger |

---

## Common Pitfalls (Phase-Specific)

### Pitfall A: `CIImage(data:options:)` does not bake orientation geometrically

**What goes wrong:** `CIImage(data: data, options: [.applyOrientationProperty: true])` stores orientation as metadata in `CIImage.properties` but does NOT geometrically transform the pixel data. The image will appear correctly in some display paths (Core Image respects the property during render in some configurations) but will be wrong on export via `createCGImage`. The current `downsample()` function accidentally avoids this by routing through `UIGraphicsImageRenderer` which calls `UIImage.draw(in:)` which bakes orientation as a side effect.

**How to avoid:** After creating the CIImage from data, immediately call:
```swift
// Extract EXIF orientation from the image properties
let exifOrientation = ciImage.properties[kCGImagePropertyOrientation as String] as? Int32 ?? 1
let oriented = ciImage.oriented(forExifOrientation: exifOrientation)
```
The `oriented` image is geometrically correct and orientation-unambiguous throughout the rest of the pipeline.

**Warning sign:** Portrait photos appear landscape in the export but correct in the preview (preview uses UIKit display which re-applies orientation; export does not).

### Pitfall B: `@Observable` requires `@State` not `@StateObject`

**What goes wrong:** The old `PhotoEditorViewModel` uses `ObservableObject` + `@StateObject`. The new `EditorViewModel` uses `@Observable` (Swift 5.9 / iOS 17). If ContentView uses `@StateObject` with an `@Observable` class, SwiftUI silently ignores the observation and the view never updates.

**How to avoid:** Use `@State private var viewModel = EditorViewModel()` in ContentView. This is the correct pairing for `@Observable`.

### Pitfall C: `CIContext` created inside `RenderEngine.init()` may silently fall back to software

**What goes wrong:** If `MTLCreateSystemDefaultDevice()` returns `nil` (Simulator without Metal, very old devices), the `CIContext(mtlDevice: device!)` force-unwrap crashes. If `MTLCreateSystemDefaultDevice()` returns a value but `.useSoftwareRenderer` is not explicitly set to `false`, the context may use a CPU path for some operations.

**How to avoid:**
```swift
guard let device = MTLCreateSystemDefaultDevice() else {
    throw RenderError.noMetalDevice
}
let context = CIContext(mtlDevice: device, options: [
    .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
    .outputColorSpace: CGColorSpace(name: CGColorSpace.displayP3)!,
    .useSoftwareRenderer: false
])
```
Surface `RenderError.noMetalDevice` to the user as a graceful error, not a crash. (All supported iOS 17 devices have Metal, so this is a defensive measure only.)

### Pitfall D: Slider range mismatch causes wrong values in PipelineBuilder

**What goes wrong:** The old sliders use non-centered ranges: `contrast` is `0.5...2.0` where `1.0` is neutral, `saturation` is `0...2` where `1.0` is neutral. The new `AdjustmentStack` uses centered ranges where `0` is always neutral. If the old slider ranges are kept in ContentView without updating, the PipelineBuilder receives e.g. `contrast = 1.0` meaning "max contrast" when the user hasn't touched the slider, because the slider hasn't moved from the old neutral `1.0` but the model interprets `1.0` as a large positive contrast adjustment.

**How to avoid:** Update ContentView slider ranges when rewiring:
- Exposure: `-1...1` (was `-1...1` for brightness — range is compatible, just rename)
- Contrast: `-1...1` with default `0` (was `0.5...2` with default `1` — range must change)
- Saturation: `-1...1` with default `0` (was `0...2` with default `1` — range must change)

PipelineBuilder maps these centered values to the CIFilter parameter ranges internally.

### Pitfall E: `previewImage: UIImage?` nil when no edits → preview disappears

**What goes wrong:** The old code had `editedImage = nil` when no edits were applied, and ContentView displayed `viewModel.editedImage ?? viewModel.sourceImage`. If `EditorViewModel.previewImage` is nil when the stack is identity, the preview goes blank.

**How to avoid:** `EditorViewModel.previewImage` should always reflect the current render result — even when the stack is identity (in which case `PipelineBuilder.build` returns the source image unchanged). Initialize `previewImage` from the source image on import. Never set it to nil after a photo is loaded.

---

## Architecture Patterns (Phase 1)

### Import → Preview Pipeline

```
ContentView.loadSelectedPhoto()
  → selectedItem.loadTransferable(type: Data.self)
  → EditorViewModel.importPhoto(data: Data)
    → ImageImporter.importImage(from: data)
      → CIImage(data:options:[.applyOrientationProperty: true])
      → .oriented(forExifOrientation: exifOrientation)  ← CRITICAL
      → downsample to ≤1080px long edge for previewCIImage
      → returns ImportedImage(sourceData:, previewCIImage:, exportCIImage:)
    → self.importedImage = result
    → stackDidChange()  → initial render
```

### Slider Change → Debounced Render

```
ContentView AdjustmentSlider.onChange
  → viewModel.stack.light.exposure = newValue   (direct struct mutation via @Observable)
  → EditorViewModel body observes stack change
  → stackDidChange()
    → renderTask?.cancel()
    → renderTask = Task {
        try? await Task.sleep(for: .milliseconds(40))
        guard !Task.isCancelled
        let cg = try await engine.renderPreview(stack: currentStack, source: previewCIImage)
        previewImage = UIImage(cgImage: cg)
      }
```

### Save (Export) Path

```
ContentView saveSection button
  → Task { await viewModel.saveImage() }
    → isSaving = true
    → PHPhotoLibrary.requestAuthorization(for: .addOnly)
    → engine.renderExport(stack: stack, source: exportCIImage)  [full-res, actor background]
    → UIImage(cgImage: result)
    → PHPhotoLibrary.performChanges { PHAssetChangeRequest.creationRequestForAsset(from:) }
    → isSaving = false
```

---

## PipelineBuilder Phase 1 Implementation Notes

Phase 1 implements only the light and color scaffolding. All other stages return the image unchanged.

**Stage 2 (light) — filters to use:**
- `CIExposureAdjust` with `inputEV = stack.light.exposure`
- `CIColorControls` with `contrast = 1.0 + stack.light.contrast` (maps 0→1.0, -1→0.0, +1→2.0) and `brightness = 0` (Phase 1 does not wire brightness separately from exposure)
- `CIHighlightShadowAdjust` with `inputHighlightAmount` mapped from `stack.light.highlights` and `inputShadowAmount` from `stack.light.shadows`

**Stage 3 (color) — filters to use:**
- `CIColorControls` with `saturation = 1.0 + stack.color.saturation` (maps 0→1.0, -1→0.0, +1→2.0)
- `CIVibrance` with `inputAmount = stack.color.vibrance`

**All other stages (Phase 1 stubs):**
```swift
static func applyLUT(_ filter: FilterSelection?, to image: CIImage) -> CIImage {
    return image  // Phase 2
}
static func applyHSL(_ hsl: HSLAdjustments, to image: CIImage) -> CIImage {
    return image  // Phase 3
}
// etc.
```

---

## Validation Architecture

> Dev environment is Linux — no Xcode, no simulator, no xcodebuild. All grep/file checks can run on Linux. Runtime checks (Metal activation, color correctness, orientation) require the user to run on Mac/device.

### File-Creation Gates (verifiable on Linux)

These grep checks confirm the new files exist and contain the required type declarations. Run them after the implementation tasks to gate the wave.

| Gate | Command | Pass condition |
|------|---------|---------------|
| RenderEngine actor declared | `grep -r "actor RenderEngine" PhotoEditor/` | Match found |
| AdjustmentStack struct declared | `grep -r "struct AdjustmentStack" PhotoEditor/` | Match found |
| schemaVersion field present | `grep -r "schemaVersion" PhotoEditor/` | Match found in AdjustmentStack.swift |
| PipelineBuilder declared | `grep -r "enum PipelineBuilder" PhotoEditor/` | Match found |
| build function signature present | `grep -r "func build(stack:" PhotoEditor/` | Match found in PipelineBuilder.swift |
| ImageImporter declared | `grep -r "enum ImageImporter\|struct ImageImporter" PhotoEditor/` | Match found |
| ImportedImage struct declared | `grep -r "struct ImportedImage" PhotoEditor/` | Match found |
| EditorViewModel uses @Observable | `grep -r "@Observable" PhotoEditor/Editor/EditorViewModel.swift` | Match found |
| RenderEngine/PipelineBuilder directory exists | `ls PhotoEditor/RenderEngine/` | Lists RenderEngine.swift and PipelineBuilder.swift |
| Editor directory exists | `ls PhotoEditor/Editor/` | Lists AdjustmentStack.swift, EditorViewModel.swift, ImageImporter.swift |

### Removal Gates (verifiable on Linux)

These grep checks confirm the old pipeline is fully gone. Any match is a FAIL.

| Gate | Command | Pass condition |
|------|---------|---------------|
| CIPhotoEffect removed | `grep -r "CIPhotoEffect" PhotoEditor/` | No matches |
| CISepiaTone (old filter) removed | `grep -r "CISepiaTone" PhotoEditor/` | No matches |
| FilterPreset enum removed | `grep -r "enum FilterPreset" PhotoEditor/` | No matches |
| Old CIContext() removed | `grep -r "CIContext()" PhotoEditor/` | No matches (new code uses `CIContext(mtlDevice:)`) |
| PhotoEditorViewModel deleted | `ls PhotoEditor/PhotoEditorViewModel.swift 2>&1` | "No such file" |
| UIImage intermediate in import removed | `grep -r "UIImage(data:" PhotoEditor/Editor/ImageImporter.swift` | No matches |
| ObservableObject removed | `grep -r "ObservableObject" PhotoEditor/` | No matches |

### API Surface Presence Checks (verifiable on Linux)

These verify the exact function signatures exist, ensuring downstream phases can call them.

| Check | Command | Pass condition |
|-------|---------|---------------|
| renderPreview signature | `grep -n "func renderPreview" PhotoEditor/RenderEngine/RenderEngine.swift` | Match with `stack: AdjustmentStack` and `source: CIImage` parameters |
| renderExport signature | `grep -n "func renderExport" PhotoEditor/RenderEngine/RenderEngine.swift` | Match |
| oriented(forExifOrientation:) called in import | `grep -r "oriented(forExifOrientation" PhotoEditor/` | Match in ImageImporter.swift |
| applyOrientationProperty used | `grep -r "applyOrientationProperty" PhotoEditor/` | Match in ImageImporter.swift |
| MTLCreateSystemDefaultDevice used | `grep -r "MTLCreateSystemDefaultDevice" PhotoEditor/` | Match in RenderEngine.swift |
| useSoftwareRenderer set false | `grep -r "useSoftwareRenderer" PhotoEditor/` | Match showing `.useSoftwareRenderer: false` |
| extendedLinearSRGB working space | `grep -r "extendedLinearSRGB" PhotoEditor/` | Match in RenderEngine.swift |
| AdjustmentStack.identity exists | `grep -r "static let identity" PhotoEditor/Editor/AdjustmentStack.swift` | Match |
| stackDidChange debounce present | `grep -n "Task.sleep" PhotoEditor/Editor/EditorViewModel.swift` | Match |
| renderTask cancel present | `grep -n "renderTask?.cancel" PhotoEditor/Editor/EditorViewModel.swift` | Match |

### ContentView Rewiring Checks (verifiable on Linux)

| Check | Command | Pass condition |
|-------|---------|---------------|
| @State viewModel (not @StateObject) | `grep -n "@StateObject" PhotoEditor/ContentView.swift` | No matches |
| @State var viewModel = EditorViewModel | `grep -n "EditorViewModel" PhotoEditor/ContentView.swift` | Match |
| Old brightness binding gone | `grep -n "viewModel.brightness" PhotoEditor/ContentView.swift` | No matches |
| New exposure binding present | `grep -n "stack.light.exposure\|stack\.light\." PhotoEditor/ContentView.swift` | Match |
| Old saturation binding gone | `grep -n "viewModel.saturation" PhotoEditor/ContentView.swift` | No matches |

### Manual UAT Items (user runs on Mac/device)

These cannot be automated on Linux and require the user to build and run on a physical device.

**Orientation correctness (RENDER-01):**
1. Take or use a portrait photo taken upright (EXIF orientation 6 — rotated 90° CW from sensor).
2. Import into the app.
3. Verify preview shows portrait (not landscape).
4. Save to Photos. Open saved photo in iOS Photos app. Verify it is still portrait with no rotation.
5. Repeat with a photo taken in landscape-left and landscape-right orientations.

**Color profile correctness (RENDER-01):**
1. Import a photo known to have Display P3 color profile (any iPhone 8+ photo with saturated colors).
2. Make no edits. Save to Photos.
3. Use `exiftool -ColorSpaceData <saved-file>` or the Photos app's "Get Info" to verify the saved file has a color profile embedded (not "uncalibrated" or empty).
4. Compare saturated colors between the in-app preview and the Photos app display — they should match.

**Metal context active (RENDER-05):**
1. On Mac with Xcode, open Instruments → Metal System Trace.
2. Launch the app, import a photo, drag an exposure slider for 5 seconds.
3. Verify GPU workload trace shows activity during slider drag (not purely CPU).
4. Alternatively: in Xcode's GPU Frame Capture, capture a frame during a slider drag and confirm a CIContext GPU command encoder is active.

**Non-destructive editing (RENDER-02):**
1. Import a photo.
2. Drag exposure to maximum (+1 EV).
3. Reset adjustments.
4. Verify the photo looks identical to the original (no clipping, no color shift).
5. Save with no edits applied. Verify the saved photo matches the original.

**Preview vs. export consistency (RENDER-03, RENDER-04):**
1. Import a photo. Set exposure to +0.5 and saturation to +0.3.
2. Observe the preview looks slightly brighter and more saturated.
3. Save to Photos. Open the saved photo.
4. Verify the saved photo visually matches the in-app preview (same brightness/saturation shift applied at full resolution).

**Performance smoke test — no full-res on slider drag (RENDER-04):**
1. Import a photo.
2. Rapidly drag the exposure slider back and forth for 5 seconds.
3. The app must remain visually responsive — no more than 1–2 frames of lag between drag and preview update on a recent device.
4. The save operation (tap "Save to Photos") should take noticeably longer than a preview render (it's doing full-res), confirming the two paths are indeed separate.

**Software renderer not engaged (RENDER-05 negative check):**
1. In `RenderEngine.init()`, temporarily add a `print` statement confirming the MTLDevice is non-nil.
2. Run the app in Simulator — confirm the app handles the `noMetalDevice` error gracefully rather than crashing (Simulator may not have Metal depending on configuration).
3. Revert the test code.

---

## State of the Art (for this phase)

| Old Approach (existing code) | New Approach (Phase 1) | Impact |
|------------------------------|------------------------|--------|
| `CIContext()` — software renderer | `CIContext(mtlDevice:)` — Metal-backed | 5–20× faster renders; slider responsiveness |
| `UIImage(data:)` → `CIImage(image:)` import | `CIImage(data:options:[.applyOrientationProperty:true])` | Preserves ICC profile; orientation handled correctly |
| Orientation baked via `UIGraphicsImageRenderer` as side effect | `CIImage.oriented(forExifOrientation:)` explicit call | Orientation correct on all 8 EXIF cases; no UIKit detour |
| Flat `@Published` properties (brightness, contrast, saturation) | `AdjustmentStack` value type with `schemaVersion` | Enables undo/redo, persistence, recipe system in later phases |
| `CIPhotoEffect*` built-in Apple filters | `PipelineBuilder` stub returning source (LUT pipeline in Phase 2) | Foundation for 20+ curated film LUTs; eliminates "stock template" look |
| `ObservableObject` + `@Published` + `@StateObject` | `@Observable` + `@State` | iOS 17 idiomatic; fewer re-renders; no `objectWillChange` boilerplate |
| Single `scheduleRender()` path (preview = export resolution) | Separate preview (1080px) and export (full-res) paths | RENDER-04 compliance; prevents frame drops during slider drag |

---

## Open Questions

1. **`EditorViewModel` — observation pattern for AdjustmentStack mutations**
   - What we know: `@Observable` tracks property access, so `viewModel.stack.light.exposure` changes will be observed if `stack` itself is a property of the `@Observable` class.
   - What's unclear: SwiftUI's `@Observable` macro tracks struct property access at the class level — mutating a nested struct property on `stack` will trigger observation because it replaces the `stack` value. However, if sub-properties are observed individually (e.g., two views each observe `stack.light.exposure` and `stack.color.saturation` independently), the macro should coalesce correctly. This needs a quick validation during implementation.
   - Recommendation: Add a computed property `var lightExposure: Double { get { stack.light.exposure } set { stack.light.exposure = newValue; stackDidChange() } }` if direct struct mutation doesn't trigger debounced renders correctly. This is a one-line fix if needed.

2. **Import path: `CIImage(data:options:)` vs `CIImage(contentsOf:)`**
   - What we know: `PhotosPickerItem.loadTransferable(type: Data.self)` returns the image bytes. `CIImage(data:options:)` is the correct call.
   - What's unclear: The `[.applyOrientationProperty: true]` option's exact behavior — Apple's documentation says it "applies any orientation metadata in the image to the output CIImage." This may or may not geometrically transform the image depending on the CI rendering path. The explicit `.oriented(forExifOrientation:)` call is a belt-and-suspenders fix.
   - Recommendation: Always call `.oriented(forExifOrientation:)` explicitly regardless of what `.applyOrientationProperty` does. Test with a known-rotated photo on device.

3. **Rotate buttons in ContentView**
   - What we know: `rotateLeft()` and `rotateRight()` are in the UI and call into the old `rotationAngle: Double` property.
   - What's unclear: Whether to leave the buttons visible-but-disabled in Phase 1, or remove them temporarily.
   - Recommendation: Leave disabled with `.disabled(true)`. This avoids a UX regression (the buttons existed before) and gives Phase 3 a clear hook point.

---

## Sources

### Primary (HIGH confidence — locked in prior research)
- `.planning/research/ARCHITECTURE.md` — RenderEngine actor design, PipelineBuilder pattern, build order, AdjustmentStack full schema
- `.planning/research/STACK.md` — Two-context strategy code example, color management settings, preview pipeline filter order
- `.planning/research/PITFALLS.md` — Pitfalls 3 (EXIF orientation), 4 (color gamut), 5 (software renderer), 6 (full-res on every tick) are all directly addressed in this phase

### Secondary (MEDIUM confidence)
- `PhotoEditor/PhotoEditorViewModel.swift` — existing code analyzed for what to keep (`downsample` helper pattern, Task debounce pattern) and what to remove (CIPhotoEffect enum, software CIContext, UIImage import path)
- `PhotoEditor/ContentView.swift` — existing UI analyzed to confirm which bindings change and which view structure is preserved unchanged

### Note on verification
All architecture and API decisions in this document derive directly from the project's prior research corpus (HIGH confidence, verified against Apple docs during that research pass). No new library lookups were required — the research corpus is authoritative for this phase.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all decisions locked in ARCHITECTURE.md/STACK.md
- Architecture: HIGH — file plan and API surfaces derived from locked decisions
- Pitfalls: HIGH — phase-specific pitfalls are concrete instantiations of already-documented pitfalls
- Validation: MEDIUM — grep gates are verified patterns; runtime UAT items depend on on-device execution

**Research date:** 2026-05-03
**Valid until:** 2026-06-03 (Core Image APIs are stable; no expiry concern within this timeframe)

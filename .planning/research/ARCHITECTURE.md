# Architecture Research

**Domain:** Premium iOS photo editor (SwiftUI, Core Image, LUT pipeline, non-destructive editing)
**Researched:** 2026-05-03
**Confidence:** HIGH (Core Image concurrency model, SwiftData migration, Observable patterns all verified against official sources)

---

## Standard Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                          UI Layer                               │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │  EditorView  │  │  LibraryView │  │  RecipesBrowserView  │  │
│  │  + ViewModel │  │  + ViewModel │  │  + ViewModel         │  │
│  └──────┬───────┘  └──────┬───────┘  └──────────┬───────────┘  │
│         │                 │                      │              │
├─────────┴─────────────────┴──────────────────────┴──────────────┤
│                       Service Layer                             │
│  ┌────────────┐  ┌──────────────┐  ┌──────────┐  ┌──────────┐  │
│  │RenderEngine│  │RecipesService│  │FilterLib │  │ExportSvc │  │
│  └─────┬──────┘  └──────┬───────┘  └────┬─────┘  └────┬─────┘  │
│        │                │               │              │        │
├────────┴────────────────┴───────────────┴──────────────┴────────┤
│                      Persistence Layer                          │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  LibraryStore (SwiftData) — LibraryItem + AdjustStack   │    │
│  │  RecipeStore  (SwiftData) — Recipe + AdjustStack copy   │    │
│  │  FilterAssets (Bundle)   — .cube LUT files              │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

---

## Component Responsibilities

| Component | Responsibility | Owns / Does Not Own |
|-----------|---------------|----------------------|
| **RenderEngine** | Build CIImage filter chain from AdjustmentStack, run preview renders (downsampled) and full-res renders, manage CIContext | Owns: CIContext, render actor. Does NOT own: source images, edit state |
| **EditViewModel** (@MainActor @Observable) | Hold the live AdjustmentStack for the active session, debounce slider changes into render requests, manage undo/redo stack | Owns: session state. Does NOT own: persistence, rendering |
| **LibraryStore** | Persist LibraryItem records (SwiftData @Model), map PHAsset localIdentifiers to stored stacks, thumbnail cache | Owns: SwiftData context. Does NOT own: render output |
| **RecipesService** | CRUD for Recipe entities (SwiftData), share/import via .recipe JSON file, apply recipe to current stack | Owns: Recipe SwiftData entities + file codec. Does NOT own: current session state |
| **FilterLibrary** | Load .cube LUT files from Bundle, parse into CIColorCube data, expose per-filter default adjustment tweaks, version their metadata | Owns: LUT parsing, FilterDefinition catalog. Does NOT own: filter application |
| **ExportService** | Compose full-res CIImage chain, convert to requested format (JPEG/HEIC/PNG), downscale to chosen preset, write to Photos / share sheet | Owns: format encoding, sizing math. Does NOT own: CIContext (borrows from RenderEngine) |
| **Views** | SwiftUI views — no business logic, no direct Core Image calls | Bind to ViewModels only |

---

## Recommended Project Structure

```
PhotoEditor/
├── App/
│   ├── PhotoEditorApp.swift
│   └── AppContainer.swift          # Dependency injection root
│
├── Editor/
│   ├── EditorView.swift
│   ├── EditorViewModel.swift       # @MainActor @Observable — session state
│   ├── AdjustmentStack.swift       # The core edit-model structs (see below)
│   ├── UndoStack.swift             # Typed undo/redo over AdjustmentStack snapshots
│   └── Controls/                   # Slider panels, filter strip, curves UI
│
├── RenderEngine/
│   ├── RenderEngine.swift          # actor — CIContext, pipeline builder
│   ├── PipelineBuilder.swift       # Pure functions: AdjustmentStack → CIImage chain
│   └── PreviewRenderer.swift       # Downsampled-image render path
│
├── FilterLibrary/
│   ├── FilterLibrary.swift         # Load + cache FilterDefinitions
│   ├── FilterDefinition.swift      # Struct: id, name, lutFileName, defaultAdjustments
│   ├── LUTLoader.swift             # .cube → Data → CIColorCube
│   └── Resources/LUTs/             # *.cube files
│
├── Library/
│   ├── LibraryView.swift
│   ├── LibraryViewModel.swift
│   ├── LibraryItem.swift           # @Model — SwiftData entity
│   └── ThumbnailCache.swift
│
├── Recipes/
│   ├── RecipesBrowserView.swift
│   ├── RecipesViewModel.swift
│   ├── RecipesService.swift        # CRUD + file export/import
│   ├── Recipe.swift                # @Model — SwiftData entity
│   └── RecipeFileCodec.swift       # Codable → .recipe JSON file
│
└── Export/
    ├── ExportService.swift
    ├── ExportOptions.swift          # Struct: format, sizePreset, quality
    └── SizePreset.swift
```

---

## The Edit-Stack Data Model (Concrete Swift Sketch)

This is the heart of the non-destructive system. Everything serializable uses `Codable`; SwiftData stores it as a JSON blob (via a `transformedValue` attribute or a direct `Codable` property). This keeps the schema shallow and makes versioning tractable.

```swift
// ── Filter selection ────────────────────────────────────────────
struct FilterSelection: Codable, Equatable {
    var filterID: String        // stable identifier, e.g. "kodak_portra"
    var strength: Double        // 0.0–1.0
}

// ── Per-adjustment-group structs ────────────────────────────────
struct LightAdjustments: Codable, Equatable {
    var exposure: Double    = 0     // EV, –3…+3
    var contrast: Double    = 0     // –1…+1
    var highlights: Double  = 0     // –1…+1
    var shadows: Double     = 0     // –1…+1
    var whites: Double      = 0     // –1…+1
    var blacks: Double      = 0     // –1…+1
}

struct ColorAdjustments: Codable, Equatable {
    var saturation: Double   = 0    // –1…+1
    var temperature: Double  = 0    // –1…+1 (mapped to Kelvin internally)
    var tint: Double         = 0    // –1…+1
    var vibrance: Double     = 0    // –1…+1
}

struct HSLChannel: Codable, Equatable {
    var hue: Double        = 0      // degrees shift
    var saturation: Double = 0
    var luminance: Double  = 0
}

struct HSLAdjustments: Codable, Equatable {
    var red     = HSLChannel()
    var orange  = HSLChannel()
    var yellow  = HSLChannel()
    var green   = HSLChannel()
    var aqua    = HSLChannel()
    var blue    = HSLChannel()
    var purple  = HSLChannel()
    var magenta = HSLChannel()
}

struct CurvePoint: Codable, Equatable {
    var x: Double   // input  0–1
    var y: Double   // output 0–1
}

struct CurveChannel: Codable, Equatable {
    var points: [CurvePoint] = [CurvePoint(x: 0, y: 0), CurvePoint(x: 1, y: 1)]
}

struct ToneCurves: Codable, Equatable {
    var rgb = CurveChannel()
    var red = CurveChannel()
    var green = CurveChannel()
    var blue = CurveChannel()
}

struct SplitToning: Codable, Equatable {
    var highlightHue: Double        = 0
    var highlightSaturation: Double = 0
    var shadowHue: Double           = 0
    var shadowSaturation: Double    = 0
    var balance: Double             = 0
}

struct GrainSettings: Codable, Equatable {
    var size: Double      = 0    // 0 = no grain
    var intensity: Double = 0
}

struct VignetteSettings: Codable, Equatable {
    var amount: Double  = 0
    var feather: Double = 0.5
}

struct CropSettings: Codable, Equatable {
    var normalizedRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    var rotationDegrees: Double = 0   // free rotate (not 90° steps)
    var straighten: Double = 0
    var clockwiseRotations: Int = 0   // 90° step count (0–3)
}

// ── Top-level adjustment stack ───────────────────────────────────
struct AdjustmentStack: Codable, Equatable {
    // Schema version — bump when the shape changes
    var schemaVersion: Int = 1

    var filter: FilterSelection?
    var light  = LightAdjustments()
    var color  = ColorAdjustments()
    var hsl    = HSLAdjustments()
    var curves = ToneCurves()
    var splitToning = SplitToning()
    var grain       = GrainSettings()
    var vignette    = VignetteSettings()
    var crop        = CropSettings()
    var sharpness: Double = 0           // 0…1

    static let identity = AdjustmentStack()
}

// ── SwiftData persistence entity ────────────────────────────────
@Model
final class LibraryItem {
    var id: UUID
    var phAssetLocalIdentifier: String  // link back to Photos
    var stackJSON: Data                 // JSONEncoder().encode(AdjustmentStack)
    var createdAt: Date
    var updatedAt: Date
    var thumbnailData: Data?            // small JPEG thumbnail, lazily cached

    // Computed, not stored
    var adjustmentStack: AdjustmentStack {
        get { (try? JSONDecoder().decode(AdjustmentStack.self, from: stackJSON)) ?? .identity }
        set { stackJSON = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
}

@Model
final class Recipe {
    var id: UUID
    var name: String
    var schemaVersion: Int    // mirrors AdjustmentStack.schemaVersion at save time
    var stackJSON: Data
    var createdAt: Date
    var sortOrder: Int

    var adjustmentStack: AdjustmentStack {
        get { (try? JSONDecoder().decode(AdjustmentStack.self, from: stackJSON)) ?? .identity }
        set { stackJSON = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
}
```

**Why JSON blob rather than normalized SwiftData attributes:**
Storing the full stack as a single JSON value means adding a new adjustment field requires zero schema migration — the decoder just uses the default value for missing keys. Migrations are only needed when a field is *renamed* or *removed*, not when one is added.

---

## Versioning Strategy for AdjustmentStack and Recipes

**The guiding rule: additions are free; renames/removals require a migration.**

1. `AdjustmentStack.schemaVersion` is encoded into every JSON blob. Current is `1`.
2. When a field is *added*, `Codable` decoding simply uses the property's default value. No migration needed. Recipe from v1 loads fine in v2.
3. When a field is *renamed or removed*:
   - Bump `schemaVersion` to `2`.
   - Write a `migrate(from v1Data: Data) -> AdjustmentStack` function in a `StackMigrator` type.
   - On decode, check `schemaVersion` first; if < current, run the migrator chain before returning.
4. SwiftData schema migration (`VersionedSchema`) is only needed if the `LibraryItem` or `Recipe` @Model *entity structure* changes (e.g., a new indexed column). The JSON blob contents do not trigger SwiftData migrations.
5. Exported `.recipe` files embed `schemaVersion` at the top level. On import, the app reads the version and applies the same migrator chain. This means a recipe shared from an older app version loads correctly.

---

## Concurrency Architecture

### Two Render Paths

```
Preview Path (slider drag):
  @MainActor EditViewModel
      → cancel previous Task
      → Task { await RenderEngine.renderPreview(stack, previewImage) }
              [RenderActor — background]
              → PipelineBuilder.build(stack) → CIImage chain
              → CIContext.createCGImage(output, from: downsampled extent)
      → await MainActor: editViewModel.previewImage = result

Export Path (user taps Export):
  ExportService.export(stack, sourceAsset, options)
      → load full-res CIImage from PHImageManager (async)
      → await RenderEngine.renderFullRes(stack, fullResImage)
              [RenderActor — background]
              → same PipelineBuilder.build()
              → CIContext.createCGImage at full extent
      → encode to JPEG/HEIC/PNG
      → PHPhotoLibrary.shared().performChanges { ... }
```

### RenderEngine as a Swift Actor

```swift
actor RenderEngine {
    // One CIContext per actor instance — thread-safe; Metal-backed.
    // CIContext is expensive to create; share one across all renders.
    private let context = CIContext(options: [.useSoftwareRenderer: false])

    // Preview: render against a downsampled CIImage (max 1024px long edge).
    // Caller is responsible for passing in the already-downsampled image.
    func renderPreview(stack: AdjustmentStack, source: CIImage) throws -> CGImage {
        let chain = PipelineBuilder.build(stack: stack, source: source)
        guard let result = context.createCGImage(chain, from: chain.extent) else {
            throw RenderError.outputEmpty
        }
        return result
    }

    // Full-res: same pipeline, full-size source. Called only during export.
    func renderFullRes(stack: AdjustmentStack, source: CIImage) throws -> CGImage {
        let chain = PipelineBuilder.build(stack: stack, source: source)
        guard let result = context.createCGImage(chain, from: chain.extent) else {
            throw RenderError.outputEmpty
        }
        return result
    }
}
```

**Why actor, not GCD queue:** Swift actors give structured concurrency, automatic reentrancy protection, and cooperative cancellation. CIContext is documented as thread-safe for concurrent renders; a single shared actor-owned context is safe and avoids the per-render creation cost of the old GCD pattern.

### Debouncing Slider Drags

```swift
@Observable @MainActor
final class EditorViewModel {
    var stack = AdjustmentStack()
    var previewCGImage: CGImage?

    private let engine = RenderEngine()
    private var renderTask: Task<Void, Never>?

    // Called from any slider's .onChange
    func stackDidChange() {
        renderTask?.cancel()
        let currentStack = stack
        let source = previewSourceImage  // 1024px downsampled CIImage

        renderTask = Task {
            // 40 ms debounce — drops intermediate frames during fast drags
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled else { return }

            if let cg = try? await engine.renderPreview(stack: currentStack, source: source) {
                previewCGImage = cg
            }
        }
    }
}
```

- **40 ms debounce** is the sweet spot: fast enough to feel live (25 fps), slow enough to avoid issuing a render for every point of slider travel.
- Capture `currentStack` as a value-type snapshot before the sleep so the render sees a consistent state even if the user continues dragging.
- **Never run full-res during drag.** Full-res only fires in `ExportService.export()`.

### Preview Image Sizing

- Import: downsample to 2048px long edge for the source (`sourceCIImage`). Store this.
- Preview renders: further downsample to 1024px max (`previewCIImage`). Compute once on import, cache.
- Export: use `PHImageManager` to load the original full-resolution image (or the stored 2048px source if the PHAsset is unavailable).

---

## Data Flow

### 1. Slider Drag → Preview Render

```
User drags slider
  → SwiftUI binding mutates EditViewModel.stack (a value type)
  → stack.didSet → stackDidChange()
    → renderTask?.cancel()             (drop in-flight render)
    → Task { sleep 40ms }              (debounce)
    → not cancelled:
      → RenderEngine.renderPreview(stack, previewCIImage)  [actor background]
        → PipelineBuilder.build() constructs lazy CIImage chain
        → CIContext.createCGImage() rasterizes
      → MainActor: editViewModel.previewCGImage = result
        → SwiftUI Image(cgImage:) refreshes
```

### 2. Apply Recipe → Render

```
User taps Recipe
  → RecipesService.adjustmentStack(for: recipe)  → AdjustmentStack
  → EditViewModel.applyRecipe(_ stack: AdjustmentStack)
    → self.stack = stack          (replaces entire stack atomically)
    → pushToUndoStack(previous)   (preserves undo history)
    → stackDidChange()            (triggers debounced render as above)
```

### 3. Library Item Re-open → Editor Restoration

```
User taps LibraryItem thumbnail
  → LibraryViewModel.open(item: LibraryItem)
    → load PHAsset via item.phAssetLocalIdentifier
    → PHImageManager.requestImage(for:, targetSize: 2048px) async
    → EditorViewModel.load(asset: phAsset, stack: item.adjustmentStack)
      → sourceCIImage = CIImage(cgImage: fullResLoad)
      → previewCIImage = downsample(sourceCIImage, to: 1024)
      → self.stack = item.adjustmentStack    (restore full non-destructive state)
      → stackDidChange()                     (render preview immediately)
```

### 4. Export

```
User configures ExportOptions and taps Save
  → ExportService.export(stack, phAsset, options)
    → PHImageManager.requestImageData(for: phAsset) async   (full res)
    → CIImage(data: imageData)
    → RenderEngine.renderFullRes(stack, source) async       (actor background)
    → encode: switch options.format {
        case .jpeg: CIContext.jpegRepresentation(...)
        case .heic: CIContext.heifRepresentation(...)
        case .png:  CIContext.pngRepresentation(...)
      }
    → resize if needed (CILanczosScaleTransform before encode)
    → PHPhotoLibrary.performChanges { PHAssetCreationRequest... }
```

---

## Architectural Patterns

### Pattern 1: Fixed-Order Pipeline with Value-Type Parameters

**What:** The CIImage filter chain is always built in the same order from an `AdjustmentStack` value. `PipelineBuilder.build()` is a pure function — same input always produces the same CIImage chain, no side effects.

**When to use:** Always. Order matters (LUT before tone curve, tone curve before grain) and fixing it eliminates a class of "did I apply filters in the right order?" bugs.

**Trade-offs:** Users cannot reorder adjustments (intentional — this is a preset-style editor, not a layer compositor).

```swift
// PipelineBuilder.swift — nonisolated, pure
enum PipelineBuilder {
    static func build(stack: AdjustmentStack, source: CIImage) -> CIImage {
        var img = source
        img = applyLUT(stack.filter, to: img)       // 1. Film LUT
        img = applyLight(stack.light, to: img)       // 2. Exposure/tone
        img = applyColor(stack.color, to: img)       // 3. Color
        img = applyHSL(stack.hsl, to: img)           // 4. HSL
        img = applyCurves(stack.curves, to: img)     // 5. Tone curves
        img = applySplitToning(stack.splitToning, to: img) // 6.
        img = applyGrain(stack.grain, to: img)       // 7.
        img = applyVignette(stack.vignette, to: img) // 8.
        img = applySharpness(stack.sharpness, to: img) // 9.
        img = applyCrop(stack.crop, to: img)         // 10. Crop last
        return img
    }
}
```

### Pattern 2: Undo/Redo via AdjustmentStack Snapshots

**What:** The undo stack is a simple `[AdjustmentStack]` array with a cursor. Pushing onto it captures the entire value-type state before a mutating action. Undo = move cursor back and restore; Redo = move cursor forward.

**When to use:** For "discrete" actions (apply recipe, apply filter, crop confirm). Not for every individual slider tick — that would produce hundreds of undo steps.

**Trade-offs:** Memory cost is proportional to undo depth × AdjustmentStack size. AdjustmentStack is ~300 bytes of value data; 50-step history = ~15 KB. Negligible.

```swift
struct UndoStack {
    private var history: [AdjustmentStack] = []
    private var cursor: Int = -1

    mutating func push(_ stack: AdjustmentStack) {
        history = Array(history.prefix(cursor + 1))
        history.append(stack)
        cursor = history.count - 1
    }

    mutating func undo() -> AdjustmentStack? {
        guard cursor > 0 else { return nil }
        cursor -= 1
        return history[cursor]
    }

    mutating func redo() -> AdjustmentStack? {
        guard cursor < history.count - 1 else { return nil }
        cursor += 1
        return history[cursor]
    }
}
```

### Pattern 3: FilterLibrary as a Loaded-Once Singleton

**What:** `FilterLibrary` is initialized at app launch, synchronously reads all .cube files from Bundle, parses them into `[String: FilterDefinition]` keyed by stable `filterID` strings, and is then read-only for the lifetime of the app.

**When to use:** Filter assets don't change at runtime. Parsing a 512KB .cube file is one-time work; caching avoids reloading on every filter tap.

**Trade-offs:** Startup cost is O(n LUT files). At 30 LUTs × ~500 KB each, that's ~15 MB parsed once. Run on a background Task during app init, publish when ready.

---

## Anti-Patterns

### Anti-Pattern 1: Storing CIImage in SwiftData or Across Thread Boundaries as Optionals

**What people do:** Saving a `CIImage?` property on a view model as a `@Published` var and passing it into async contexts.

**Why it's wrong:** `CIImage` is `Sendable` (immutable value type), but holding a reference to an image that may reference a GPU-backed texture across suspension points creates subtle lifecycle bugs. More critically, a CIImage represents a *recipe*, not pixels — you cannot meaningfully serialize one.

**Do this instead:** Pass `AdjustmentStack` + source `CIImage` (captured as a let constant before the Task) into the render actor. Reconstruct the chain inside the actor each time.

### Anti-Pattern 2: One CIContext Per Render Call

**What people do:** `let ctx = CIContext(); ctx.createCGImage(...)` inside `scheduleRender()`.

**Why it's wrong:** CIContext initialization compiles Metal shaders and allocates GPU memory. Doing it per render destroys performance — causes frame drops during slider drags.

**Do this instead:** One `CIContext` per `RenderEngine` actor instance, created once, reused for all renders (thread-safe by Apple documentation).

### Anti-Pattern 3: Mutating AdjustmentStack Properties Directly for Undo

**What people do:** `viewModel.stack.light.exposure = 0.5` directly, then trying to capture "before" state.

**Why it's wrong:** Undo capture becomes error-prone and scattered. Each mutation site needs to remember to push to the undo stack first.

**Do this instead:** Route all discrete mutations through `EditViewModel.apply(_ mutation: (inout AdjustmentStack) -> Void)` which pushes to undo stack before applying. Slider changes (continuous) do NOT push; only confirm actions (crop, recipe apply, filter select) push.

### Anti-Pattern 4: Storing Full-Res Pixel Data in the Library

**What people do:** Re-render the edited image and save the JPEG into the app's Library store alongside the AdjustmentStack.

**Why it's wrong:** Wastes storage (a library of 200 photos × 5 MB = 1 GB in the app sandbox). The source photo already lives in Photos. The edit is cheap to re-render.

**Do this instead:** Store `phAssetLocalIdentifier` + `AdjustmentStack` only. Render on demand when reopening. Store only a small (200px) thumbnail JPEG for the library grid.

---

## Build Order (Component Dependencies)

Each step produces something that unblocks the next. Do not parallelize across these steps — the dependencies are real.

```
Step 1: AdjustmentStack + PipelineBuilder
  ↳ Required by everything. No dependencies of their own.
  ↳ Write the structs and the pure pipeline builder first.
  ↳ Can be unit-tested in isolation (no UI, no SwiftData).

Step 2: RenderEngine actor + preview render path
  ↳ Requires: AdjustmentStack, PipelineBuilder
  ↳ Validates the CIContext + actor concurrency approach works.
  ↳ Enables: slider live preview.

Step 3: FilterLibrary (LUT loader + FilterDefinition catalog)
  ↳ Requires: AdjustmentStack (FilterSelection)
  ↳ Unblocks: replacing the existing CIPhotoEffect filters with LUTs.
  ↳ This is where the "distinctive film look" comes from — do it early.

Step 4: EditorViewModel + UI (sliders, filter strip, undo)
  ↳ Requires: RenderEngine, FilterLibrary, AdjustmentStack
  ↳ This is where the app becomes usable end-to-end for the first time.
  ↳ Full adjustment surface: light, color, HSL, curves, split toning, grain, vignette.

Step 5: LibraryStore (SwiftData + LibraryItem persistence)
  ↳ Requires: AdjustmentStack (for JSON serialization)
  ↳ Unblocks: re-editability — the defining premium-feel feature.

Step 6: RecipesService
  ↳ Requires: AdjustmentStack, LibraryStore (to verify round-trip JSON codec)
  ↳ Unblocks: Recipe save/apply/share — the workflow differentiator.

Step 7: ExportService
  ↳ Requires: RenderEngine (full-res path), AdjustmentStack, PHImageManager
  ↳ Full-res render + format/size choices.
  ↳ Build last — it's a capstone that exercises every prior component.
```

**Rationale for this order:**
- `AdjustmentStack` is the shared language of the whole system. Nothing else can be built without it.
- `RenderEngine` comes before UI because the UI is just a skin over the render result; you need a working render loop to validate the architecture.
- `FilterLibrary` comes before full EditorViewModel polish so the distinctive look is visible early and informs UI design decisions.
- `LibraryStore` before `RecipesService` because Recipes are an AdjustmentStack with a name — exercising the JSON codec on LibraryItem first catches serialization issues cheaply.
- `ExportService` last because it is additive — the app is already useful (edit and view) before export is wired up.

---

## Sources

- Apple: CIContext thread-safety — "CIContext and CIImage objects are immutable, and multiple threads can use the same GPU or CPU CIContext object to render CIImage objects" — https://developer.apple.com/documentation/coreimage/cicontext
- Swift Forums: CIImage Sendable conformance — https://forums.swift.org/t/ciimage-incorrect-sendable-conformance/71125
- Apple WWDC23: Model your schema with SwiftData — https://developer.apple.com/videos/play/wwdc2023/10195/
- Hacking with Swift: SwiftData VersionedSchema migrations — https://www.hackingwithswift.com/quick-start/swiftdata/how-to-create-a-complex-migration-using-versionedschema
- Apple Developer Forums: debounce with async/await — https://developer.apple.com/forums/thread/735510
- AsyncAlgorithms debounce with @Observable — https://medium.com/@lucas.abijmil/debounce-with-async-await-asyncalgorithms-in-swiftui-and-observable-macro-5a6169407326
- Apple: Migrating from ObservableObject to @Observable — https://developer.apple.com/documentation/SwiftUI/Migrating-from-the-observable-object-protocol-to-the-observable-macro

---
*Architecture research for: Premium iOS photo editor (SwiftUI + Core Image + LUT pipeline)*
*Researched: 2026-05-03*

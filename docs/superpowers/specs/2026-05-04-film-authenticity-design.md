# Film Authenticity — Design Spec

**Date:** 2026-05-04
**Status:** Design approved, awaiting implementation plan
**Scope:** Add procedural halation, picture frames, '90s date stamps, and a layered overlay/effects-set system to PhotoEditor.

---

## Goal

Lean into PhotoEditor's film-authenticity brand by giving users tactile film artifacts (light leaks, dust, scratches, halation), shareable picture frames (Polaroid, 35mm, contact-print), and one-tap '90s date stamps. These integrate as orthogonal effects layered on top of the existing filter/preset system, not as new filters.

## Non-Goals

- No App Store distribution work (sideload-only for now, per existing pipeline).
- No customization of date stamp font/color/position/format in v1 — fixed style.
- No procedural dust/scratches — overlays are scanned/sourced PNGs (with placeholder assets in v1).
- No multiple-effects-set stacking — one set active at a time, like presets.
- No new asset sourcing in this scope — placeholder PNGs ship in v1; real asset pack is a follow-up.

---

## Architectural Decisions

### 1. Effects sets are orthogonal to presets/filters

- **Presets/filters** (existing): LUT + adjustments. Live in the inline preset picker.
- **Effects sets** (new): bundle of `{halation, frame, stamp, overlays}` values. Live in their own picker in a new "Overlays" editor tab.

A user can pair any preset with any effects set independently. Effects sets do *not* contain LUT/adjustment values — only the four new film-effect fields.

### 2. Effects sets apply by writing into AdjustmentStack

The active effects set is *not* persisted on the stack. Tapping a set writes its `halation`, `frame`, `stamp`, and `overlays` values into the stack wholesale, the same way picking a preset writes filter/adjustment values today. This keeps recipes simple (pure adjustment values, not "set ID + customizations") and round-trips cleanly.

### 3. Frames are part of the rendered image

Frames apply in the pipeline (stage 13, after crop), so output dimensions grow to include the border. Frames are persisted in the recipe and round-trip on re-import. Existing code that reads `image.extent` (export, thumbnail generation) picks up the new dimensions automatically.

### 4. Halation is procedural, not an overlay

Halation is implemented as a CIFilter chain (extract bright reds → Gaussian blur → screen back), so the bloom tracks actual highlights in the image. It gets a dedicated pipeline stage (8) and is exposed as a slider in the Color tab, not as an overlay asset.

### 5. UI is distributed by conceptual neighborhood

- Halation slider → **Color** tab
- Frame picker → **Crop** tab
- Date stamp toggle + date → **Export** options
- Overlay manual controls + effects-set picker → new **Overlays** tab

### 6. Date stamp is fixed-style v1

Bundled DotMatrix font, fixed `#F4A11C` orange, fixed bottom-right position with 4% inset, fixed `'MMM dd ''yy'` format (e.g., `MAY 04 '26`). The `DateStampAdjustments` struct is shaped for future style extension but v1 only supports one style.

---

## Data Model

New types added to `Editor/AdjustmentStack.swift`. All `Codable`, all default-zero/off so existing recipes round-trip unchanged.

```swift
struct HalationAdjustments: Codable, Equatable {
    var strength: Double = 0      // 0...1; 0 = off
    var threshold: Double = 0.7   // 0...1; brightness cutoff for bloom source
    var radius: Double = 0.5      // 0...1; mapped to px-radius scaled to image size
}

enum FrameStyle: String, Codable { case none, polaroid, sprocket35mm, contactPrint }
struct FrameAdjustments: Codable, Equatable {
    var style: FrameStyle = .none
}

struct DateStampAdjustments: Codable, Equatable {
    var enabled: Bool = false
    var date: Date = Date()
    // style, color, font, format, position hardcoded in v1
}

enum OverlayBlendMode: String, Codable { case screen, multiply, overlay, softLight }

struct OverlayInstance: Codable, Equatable {
    var assetID: String                 // matches manifest entry
    var opacity: Double = 1.0
    var blendMode: OverlayBlendMode
}

struct OverlayAdjustments: Codable, Equatable {
    var instances: [OverlayInstance] = []   // ordered, applied in array order
}
```

`AdjustmentStack` gains four new fields:

```swift
var halation = HalationAdjustments()
var frame = FrameAdjustments()
var stamp = DateStampAdjustments()
var overlays = OverlayAdjustments()
```

Effects sets live in a new file `Library/EffectsSet.swift`:

```swift
struct EffectsSet: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var halation: HalationAdjustments
    var frame: FrameAdjustments
    var stamp: DateStampAdjustments
    var overlays: OverlayAdjustments
}
```

---

## Pipeline Stage Ordering

`PipelineBuilder.build` is extended from 10 stages to 14:

```
1.  LUT
2.  light
3.  color
4.  HSL
5.  curves
6.  split toning
7.  grain
8.  halation        ← NEW: after grain so grain doesn't muddy bloom source;
                       before vignette so glow survives edge darkening
9.  vignette
10. sharpness
11. overlays        ← NEW: after sharpness so overlay textures aren't sharpened
12. crop
13. frame           ← NEW: changes output dimensions; must follow crop
14. stamp           ← NEW: last so it's never inside the frame border
```

Each new stage returns its input unchanged when its adjustment is at zero/off, preserving the identity-stack guarantee from RENDER-02/RENDER-06.

---

## Phase Breakdown

Each phase is one buildable, sideloadable IPA and one atomic git commit, sequenced by risk (highest first).

### Phase 1 — Halation

**Effort:** ~1 day.

- New stage method `applyHalation(_:to:)` in `PipelineBuilder.swift`.
- Filter chain: `CIColorMatrix` (extract red channel, threshold-clamp dark pixels) → `CIGaussianBlur` (radius = `image.extent.width × 0.02 × stack.halation.radius`) → `CIAdditionCompositing` over original, scaled by `strength`.
- UI: "Halation" slider in **Color** editor tab, range 0–100% mapped to `strength`. `threshold` and `radius` exposed under a disclosure with sensible defaults.
- Tests: identity (`strength=0` → output bytes-identical to input), brightness bound (output ≥ input on per-pixel red channel), perf (<20 ms at 2048 px on iPhone 13-class).

### Phase 2 — Frames

**Effort:** ~1.5 days.

- New stage method `applyFrame(_:to:)` in `PipelineBuilder.swift`, runs after crop.
- Generates frame geometry procedurally via Core Graphics — no PNG assets in v1 since frames are clean geometric shapes:
  - **Polaroid white**: 12% border top/sides, 30% bottom, white fill.
  - **35mm sprocket**: 5% top/bottom black bands, repeating white-rounded-rectangle sprocket holes.
  - **Contact-print square**: forces 1:1 aspect, 8% white border.
- Composites the cropped photo inside the frame's photo-window using `CISourceOverCompositing`.
- Output `extent` becomes the frame size, not the photo size. `ExportOptions` and `ThumbnailGenerator` already read `image.extent`, so they pick up new dimensions for free.
- Editor preview must react to aspect ratio change — verify `EditorTabView` re-layouts on `frame.style` change before claiming done.
- UI: 4-tile picker (None / Polaroid / Sprocket / Square) inside the **Crop** tab.
- Tests: identity (`style=.none` → output extent unchanged), dimension (`style=.polaroid` → output height ≈ input height × 1.42), recipe round-trip.

### Phase 3 — Date Stamp

**Effort:** ~0.5 day.

- New stage method `applyStamp(_:to:)`, last in pipeline.
- Renders `'MMM dd ''yy'` formatted date via `NSAttributedString` → `UIGraphicsImageRenderer` → `CIImage`. Composites bottom-right with 4% inset relative to output width.
- Bundled font: `DotMatrix-Regular.ttf` (CC0 source, ~30 KB), registered via `Info.plist` `UIAppFonts`.
- Color: `#F4A11C` orange.
- UI: toggle + `DatePicker` in **Export** options sheet. Stamp lives there because it's a metadata-style adornment in the user's mental model.
- Tests: identity (`enabled=false` → output bytes-identical), positioning sanity (stamp pixel exists in expected bottom-right region), font-load test.

### Phase 4 — Overlays + Effects Sets

**Effort:** ~3 days.

**Overlay asset system:**

- Manifest at `PhotoEditor/Filters/Overlays/manifest.json`:
  ```json
  [
    { "id": "leak.warm-corner", "category": "leak", "filename": "leak-warm-corner.png", "defaultBlendMode": "screen", "defaultOpacity": 0.8 },
    ...
  ]
  ```
- Target inventory once a real asset pack is sourced: 8–10 assets per category (leak / dust / scratch / halation-glow) → ~30 total. v1 ships a small set of procedurally-generated placeholder PNGs (one per category, 4 total) to validate the engine end-to-end. Real assets swap in later by replacing files and updating the manifest — no code changes.
- New file `Filters/Overlays/OverlayAssetStore.swift` — loads manifest, lazy-loads CIImages keyed by `assetID`, scales each overlay to current output size on composite.

**Pipeline stage:**

- `applyOverlays(_:to:)` iterates `OverlayInstance` array in order, composites each via the appropriate `CIBlendMode` filter, scales by `opacity`.

**Effects set system:**

- New `Library/EffectsSetStore.swift` parallels `RecipeStore`. Built-in sets in `Library/BuiltInEffectsSets.swift`:
  - **Polaroid Originals**: white frame + warm leak (low opacity).
  - **Cinestill Dreams**: halation 0.6 + dust overlay + 35mm frame + stamp on.
  - **Disposable '94**: scratches overlay + sprocket frame + stamp on.

Effects sets only write into the four new film fields (`halation`, `frame`, `stamp`, `overlays`). Grain remains under user control via the existing grain adjustment — sets do not touch it.
- User-created sets serialize to disk alongside built-ins.

**Effects-set thumbnails:**

- New `Library/EffectsSetThumbnailCache.swift` — parallels existing `FilterThumbnailCache` pattern. Renders a per-source-image thumbnail for each effects set on import; cache invalidates when source image changes.
- Look Pack thumbnails show full-pipeline result (preset + effects set), so users see the framed/stamped/overlaid look before applying.

**UI:**

- New **Overlays** tab in `EditorTabView` tab bar.
- Top section: horizontal-scroll effects-set picker.
- Bottom section: per-overlay manual controls — add overlay (browse by category), per-instance opacity slider, remove. Halation slider also surfaced here (cross-link with Color tab — same underlying field).

**Apply semantics:**

- Tapping an effects set replaces the stack's `halation`, `frame`, `stamp`, `overlays` values wholesale. Manual edits afterward don't tie back to the set (matches preset behavior). One set active at a time.

**Tests:** asset manifest load, overlay identity (empty `instances` → output bytes-identical), set apply/clear round-trip, effects-set thumbnail cache hit/miss.

---

## File Layout

New and modified files:

```
PhotoEditor/
  RenderEngine/
    PipelineBuilder.swift              (modified — 4 new stage methods)
  Editor/
    AdjustmentStack.swift              (modified — 4 new field types)
    OverlaysTabView.swift              (new — Phase 4)
  Filters/
    Overlays/
      manifest.json                    (new — Phase 4)
      OverlayAssetStore.swift          (new — Phase 4)
      *.png                            (placeholder assets — Phase 4)
  Library/
    EffectsSet.swift                   (new — Phase 4)
    EffectsSetStore.swift              (new — Phase 4)
    BuiltInEffectsSets.swift           (new — Phase 4)
    EffectsSetThumbnailCache.swift     (new — Phase 4)
  Export/
    ExportOptions.swift                (modified — Phase 3 stamp fields)
  Resources/
    DotMatrix-Regular.ttf              (new — Phase 3)
  Info.plist                           (modified — Phase 3 UIAppFonts entry)
docs/superpowers/specs/
  2026-05-04-film-authenticity-design.md   (this file)
```

---

## Testing Strategy

- Each phase ships unit tests for its new pipeline stage (identity, bounds, basic correctness).
- Phase 4 adds integration tests for effects-set apply/clear cycles and asset manifest loading.
- Image-hash snapshot tests for visual regression on built-in presets — confirms no preset's output changes when film fields are at default-zero.
- UI changes are sanity-tested on-device by sideloading the IPA per CLAUDE.md, since type checking and unit tests verify code correctness, not feature correctness.

## Recipe Round-Trip

All new fields default to zero/off/empty, so existing JSON recipes load with all film effects inactive. Verified by loading every built-in preset and confirming bytes-identical re-export. Forward-compat is preserved automatically by `Codable` default values per RENDER-06.

## Sequence and Effort

| Phase | Scope | Effort | Sideload |
|-------|-------|--------|----------|
| 1 | Halation | ~1 day | 1 IPA |
| 2 | Frames | ~1.5 days | 1 IPA |
| 3 | Date stamp | ~0.5 day | 1 IPA |
| 4 | Overlays + Effects Sets | ~3 days | 1 IPA |
| **Total** | | **~6 days** | **4 IPAs** |

Each phase is a standalone atomic git commit and a separately verifiable on-device build, sequenced by risk: halation first (algorithmic correctness + perf), frames second (dimension ripples through export/thumbnails), stamp third (lowest risk), overlays + effects sets last (largest scope, lowest *unknown* risk by that point).

# Project Research Summary

**Project:** PhotoEditor (VSCO Pro-style, free, iOS)
**Domain:** Premium iOS photo editor — LUT-based film filters, non-destructive editing, local library
**Researched:** 2026-05-03
**Confidence:** HIGH

---

## Executive Summary

This is a premium-feel, editor-only iOS photo app modeled on VSCO Pro — film-style LUT filters with strength control, a deep adjustment surface (light, color, HSL, curves, grain, vignette, crop), non-destructive in-app library, reusable Recipes, and polished export. It is distributed free via TestFlight with no backend, no accounts, and no monetization. The competitive bar is high: Darkroom, Lightroom Mobile, and VSCO have established strong expectations around live-preview filter strips, slider responsiveness, and re-editability. The defining choice that makes this product legible is the curated LUT pipeline replacing Apple's generic `CIPhotoEffect*` filters — that is the first, highest-priority build.

The recommended approach is a layered build: establish the `AdjustmentStack` data model and `CIContext`/`RenderEngine` architecture before touching any UI, because every other component — undo, library, recipes, export — hangs off those two foundations. Core Image is the right and only rendering choice at this scope; the full adjustment graph (LUT + exposure + color + HSL + curves + grain + vignette + sharpen) has first-class CI filter equivalents and runs GPU-accelerated without writing Metal shaders. SwiftData covers persistence needs entirely given the two-entity schema. Two SPM dependencies cover crop/straighten (Mantis) and `.cube` parsing (SwiftCube); everything else — tone curve UI, histogram, HSL panel — is built custom.

The primary risks are front-loaded in the rendering foundation. Color space handling (LUT design space vs. CI working space), `CIColorCube` dimension constraints (only power-of-2 sizes; common 33-cube packs are invalid), EXIF orientation correctness, and the dual preview/export pipeline must all be established in Phase 1. Getting any of these wrong and discovering it in Phase 3 means retroactive fixes to every saved item in the library and every exported photo. The undo, recipe, and library systems also depend on a stable, versioned `AdjustmentStack` schema — any rename or structural change after recipes ship breaks stored data. Ship the schema design before the first `@Model` class.

---

## Key Findings

### Recommended Stack

All processing stays on-device using Apple frameworks. Core Image is the GPU-accelerated filter graph; it handles every needed adjustment without custom Metal shaders. A Metal-backed `CIContext` must be created once at launch and reused — the default `CIContext()` initializer may fall back to software rendering, causing 5–20x slower renders. Two contexts are needed (one for preview, one for background export) to avoid render races. SwiftData covers library + recipe persistence with zero boilerplate for a two-entity schema, with adjustment states stored as JSON `Data` blobs (not as normalized columns) so adding new adjustment fields never requires a schema migration.

**Core technologies:**
- **SwiftUI + `@Observable`** (iOS 17+): All UI; already in use; `@Observable` macro replaces `ObservableObject` boilerplate
- **Core Image** (iOS 17+): Full filter graph — LUTs, exposure, color, HSL, curves, grain, vignette, sharpen; GPU-accelerated via Metal-backed `CIContext`
- **SwiftData** (iOS 17+): Persistence for `LibraryItem` and `Recipe` entities; `@Query` gives live-updating grid for free
- **PhotosUI / Photos** (iOS 17+): `PhotosPicker` for import (no read permission needed); `PHPhotoLibrary` for export
- **ImageIO / `CGImageDestination`**: JPEG/HEIC/PNG export with quality control and correct ICC profile embedding
- **vImage / Accelerate**: Histogram calculation on CPU (background task, 512px input); faster and simpler than CI GPU route for display histograms
- **Mantis 2.31.1** (SPM): Crop + free rotate + straighten UI with angle ruler, aspect ratio presets, SwiftUI wrapper
- **SwiftCube 1.0.1** (SPM): `.cube` file parsing to `CIColorCubeWithColorSpace` filter data
- **Custom Canvas components**: Tone curve editor (~150 LOC), histogram display — no maintained SPM packages match the required visual style

**What NOT to use:** `CIPhotoEffect*` filters, 256-point LUTs (64MB each), `UIImage` as CI pipeline intermediate, `UIGraphicsImageRenderer` for export, `CIContext()` default init, `CGColorSpaceCreateDeviceRGB`.

**LUT authoring pipeline:** Author 33-point `.cube` in DaVinci Resolve Free → resample to 64-point via Python `colour-science` → bundle in `App/Resources/LUTs/` → parse lazily at first use via SwiftCube. Valid `CIColorCube` dimensions are 4, 16, 32, 64, 256 only.

### Expected Features

Features research (HIGH confidence) establishes clear priority tiers based on competitor analysis (VSCO, Darkroom, Lightroom Mobile, Afterlight).

**Must have — table stakes (v1 launch):**
- LUT filter strip with live preview thumbnails + strength slider — the product identity
- Full light panel: exposure, contrast, highlights, shadows, whites, blacks
- Color panel: saturation, temperature, tint, vibrance
- Crop + aspect ratio lock list + straighten dial
- Non-destructive edit model — source preserved, adjustments serialized; re-editability is a premium marker
- In-app library with re-edit capability and "edited" badge
- Before/after compare (long-press)
- Undo/redo (full session, in-memory)
- Save copy to Photos + share sheet
- Dark mode + Dynamic Type
- Double-tap to reset individual adjustments to zero
- Filter favorites row

**Should have — differentiators (v1.x after validation):**
- Recipes: save/apply/rename/delete named adjustment stacks
- HSL panel (per-channel hue/saturation/luminance)
- Grain + vignette finishing tools
- Export format/size/quality chooser (JPEG/HEIC/PNG, presets, quality slider)
- Haptic feedback polish (slider end-stops, filter selection, reset-to-zero, recipe applied)
- Recipe sharing via `.photorecipe` file + share sheet
- Value indicators on sliders while dragging
- Fine-adjustment precision mode (slow-drag)

**Defer to v2+:**
- Tone curves (RGB + per-channel) — high complexity, requires stable core stack
- Split toning / color grading panel
- Auto-straighten / horizon detection
- Manual camera (ProRAW) — separate 6-month project
- Multi-select batch export

**Anti-features — explicitly do not build:** AI auto-enhance, sky replacement, social feed, accounts, cloud sync, IAP.

### Architecture Approach

The system uses a layered architecture with a `RenderEngine` Swift actor at the center. The `AdjustmentStack` value type is the shared language across all layers — it is what the editor builds, what the library stores, what recipes serialize, and what the export renders. The pipeline is a pure function (`PipelineBuilder.build(stack:source:)`) that takes an `AdjustmentStack` and source `CIImage` and produces a `CIImage` filter chain in fixed order. Crop is applied last. Undo/redo is a `[AdjustmentStack]` snapshot array — pushed only on discrete actions (filter select, crop confirm, recipe apply), not on every slider tick. Slider debounce is 40ms with `Task` cancellation on each new drag event.

**Major components:**
1. **`AdjustmentStack` + `PipelineBuilder`** — Core edit model structs (Codable, value types) + pure pipeline function; no dependencies; unit-testable in isolation
2. **`RenderEngine` (Swift actor)** — Owns `CIContext`; handles preview (1024px) and full-res renders on a background actor; created once at launch
3. **`FilterLibrary`** — Loads `.cube` files from Bundle at launch, caches `FilterDefinition` catalog (stable IDs, display names, default adjustments)
4. **`EditorViewModel` (`@MainActor @Observable`)** — Holds live `AdjustmentStack`, debounces renders, manages undo stack
5. **`LibraryStore` (SwiftData)** — Persists `LibraryItem` records (PHAsset identifier + `stackJSON` + thumbnail); `@Query` drives library grid
6. **`RecipesService` (SwiftData)** — CRUD for `Recipe` entities; file codec for `.photorecipe` share/import
7. **`ExportService`** — Full-res render + format/size encoding; writes to Photos via temp file URL (preserves ICC profile + EXIF)

**Build order (dependency-driven):** `AdjustmentStack` → `RenderEngine` → `FilterLibrary` → `EditorViewModel` + UI → `LibraryStore` → `RecipesService` → `ExportService`.

### Critical Pitfalls

1. **LUT color space mismatch** — Always use `CIColorCubeWithColorSpace` with `CGColorSpace(name: CGColorSpace.sRGB)` for film LUTs. Test with a neutral gray: luminance shift when filter is applied means the space is wrong. Recovery after shipping is HIGH cost.

2. **`CIColorCube` dimension constraints** — Only power-of-2 sizes valid. Common 33-point `.cube` files are invalid and silently corrupt output. Ship 64-point cubes; write a parser unit test with a known identity LUT before integrating any production LUT.

3. **EXIF orientation lost via `CIImage(image:)`** — Call `.oriented(forExifOrientation:)` immediately after constructing any `CIImage` from PHAsset data. The existing downsample path hides this bug; it surfaces on full-res export. Test all 8 EXIF orientation variants.

4. **`CIContext()` software renderer** — The default init may produce a CPU renderer (5–20x slower). Always create with `CIContext(mtlDevice: MTLCreateSystemDefaultDevice()!, options: [.useSoftwareRenderer: false, .workingColorSpace: ...])`. One-line fix; no excuse for not doing it at project start.

5. **SwiftData schema migration failures** — Store `AdjustmentStack` as a JSON `Data` blob. Start with `VersionedSchema` from the first `@Model`. Never use a non-optional property without a default. JSON additions need no migration; column changes corrupt production data.

6. **Full-res renders on every slider tick** — A deep filter graph at 2048px takes 50–200ms per frame. Separate 1024px preview path; 40ms debounce + `Task` cancellation. Do not defer this to a polish phase.

7. **Recipe filter ID instability** — Recipes store a `filterID` string. Use a stable UUID at authoring time, not the human-readable display name. Renaming a filter breaks all saved recipes that reference it.

---

## Implications for Roadmap

Architecture research defines an explicit build order with real dependencies. This maps directly to phases. The research is prescriptive — follow it.

### Phase 1: Core Rendering Foundation
**Rationale:** `AdjustmentStack` and `RenderEngine` are what everything else requires. Color space and orientation bugs introduced here cascade to every photo in the library and every export.
**Delivers:** Working render loop with live slider preview; 1024px preview + full-res export paths; correct Metal-backed `CIContext`; EXIF orientation correct from day one.
**Implements:** `AdjustmentStack` structs, `PipelineBuilder` (pure function), `RenderEngine` actor, dual-context strategy, `EditorViewModel` skeleton with debounced render.
**Avoids:** CIContext software renderer (P5), full-res on every tick (P6), EXIF orientation loss (P3), color space drift (P4), CIImage retained in closures (P7), transform order regression (P11).
**Research flag:** Standard patterns — no deeper research needed. Apple docs + WWDC20 cover the CIContext + actor pattern completely.

### Phase 2: LUT Filter Pipeline
**Rationale:** The film-look filter library is the product's visual identity. It must land early so UI decisions are made against the real aesthetic.
**Delivers:** 20–30 hand-curated 64-point `.cube` LUT filters with stable IDs, per-filter default adjustments, and strength blending. `FilterLibrary` singleton. Filter strip with live-preview thumbnails.
**Implements:** `FilterLibrary`, `LUTLoader`, `FilterDefinition` catalog, SwiftCube integration, strength blend via `CIColorMatrix`.
**Avoids:** LUT color space mismatch (P1), cube dimension mismatch (P2), filter ID instability (P13).
**Research flag:** LUT authoring workflow (DaVinci → Python resample → bundle) requires hands-on validation. Unit-test the parser with an identity LUT before integrating production LUTs.

### Phase 3: Editor UI + Full Adjustment Surface
**Rationale:** With a working render loop and real filters, the editor UI can be built against live output. This is where the app first becomes usable end-to-end.
**Delivers:** Complete editing experience — light (6 controls), color (4 controls), HSL (8 channels), crop + straighten (Mantis), undo/redo, before/after compare, filter favorites, double-tap reset, dark mode + Dynamic Type.
**Implements:** All `EditorView` panels, `UndoStack`, `CropSettings` via Mantis, accessibility labels on every control.
**Avoids:** SwiftUI excess re-renders (P8), gesture conflicts (P9), extent.integral drift in free-rotate (P10), layout shift on panel open (P19), custom slider VoiceOver silence (P20).
**Research flag:** Gesture conflict between crop and adjustment panels needs real-device testing. Plan extra testing time — Simulator gesture behavior diverges from device.

### Phase 4: Library + Persistence
**Rationale:** Re-editability is the defining premium marker. Depends on a stable `AdjustmentStack` schema settled in Phases 1–3.
**Delivers:** In-app library grid with thumbnails, re-edit from library, delete, "edited" badge, graceful handling of deleted PHAssets.
**Implements:** SwiftData `LibraryItem` + `VersionedSchema` from day one, `LibraryStore`, `ThumbnailCache`, thumbnail pipeline, PHAsset + permissions handling.
**Avoids:** SwiftData schema migration failures (P12), thumbnail orphan (P14), PHAsset full-res memory spike on re-edit (P15), addOnly vs readWrite crash (P17).
**Research flag:** PHAsset `.limited` permission mode needs explicit testing — not just `.authorized`. SwiftData iOS 17 migration path must be tested by opening a v1 store with v2 schema before any update ships.

### Phase 5: Export
**Rationale:** Export is additive — the app is already useful without it. Depends on the full render pipeline and color management from Phase 1.
**Delivers:** Full-res export (JPEG/HEIC/PNG), format/size presets, quality slider, share sheet, progress indicator, correct ICC profile embedding, EXIF passthrough.
**Implements:** `ExportService`, `ExportOptions`, `CGImageDestination` pipeline, Photos write via temp file URL.
**Avoids:** HEIC color profile stripped (P16), `UIImage.jpegData` for export.
**Research flag:** Standard patterns. One integration test with `exiftool` verification on exported HEIC required.

### Phase 6: Recipes
**Rationale:** Requires stable `AdjustmentStack` JSON round-trip proven in Phase 4. Filter IDs must be stable before recipes are saved. Workflow differentiator, not core editing.
**Delivers:** Save/apply/rename/delete named recipes, recipe sharing via `.photorecipe` UTI file + share sheet, recipe import.
**Implements:** `RecipesService` (SwiftData), `RecipeFileCodec`, custom UTI registration in `Info.plist`, share + document picker.
**Avoids:** Recipe filter ID instability (P13) — stable UUID filter IDs must be in place from Phase 2.
**Research flag:** Custom UTI file association must be verified on a real device running iOS 17. Verify both the export and import flows.

### Phase 7: Polish + Accessibility
**Rationale:** Haptics and accessibility are additive polish requiring stable interaction patterns. Adding them during Phase 3 risks stale haptic calls after gesture refactors.
**Delivers:** Haptic feedback at all defined trigger points, spring animations on panel transitions, before/after instant swap, value indicators on sliders, fine-adjustment precision mode, VoiceOver audit, Dynamic Type XL layout verification, Reduce Motion compliance.
**Implements:** `UIImpactFeedbackGenerator` / `UISelectionFeedbackGenerator` / `UINotificationFeedbackGenerator`; `@Environment(\.accessibilityReduceMotion)` guards.
**Research flag:** Standard patterns. No additional research needed.

### Phase Ordering Rationale

- **Data model before UI:** `AdjustmentStack` in Phase 1 because every component serializes, renders, or displays it. Refactoring after Phase 4 breaks library data and saved recipes — the architecture research is explicit on this.
- **Film look early:** LUT aesthetic in Phase 2 so UI decisions are made against the real look. The product identity IS the filter character; building UI without seeing it is a design risk.
- **Library before Recipes:** The same JSON `AdjustmentStack` round-trip exercised by library save/restore must be proven before betting on it with exported recipe files.
- **Export before Recipes:** Recipe sharing requires the full-res render path to be proven.
- **Polish last:** Haptic triggers are defined against final interaction patterns; earlier addition means refactoring when state model changes.

### Research Flags

**Needs hands-on validation during build:**
- **Phase 2 (LUT Pipeline):** Identity LUT unit test + neutral gray color check must pass before any production LUT is integrated.
- **Phase 3 (Editor UI):** Gesture conflict between canvas and adjustment panels — real-device testing required.
- **Phase 4 (Library):** PHAsset `.limited` permission mode test matrix; SwiftData v1→v2 schema migration must be tested before shipping an update.
- **Phase 6 (Recipes):** Custom UTI file association verified on real device, both export and import flows.

**Standard patterns — no additional research needed:**
- **Phase 1 (Rendering Foundation):** Fully covered by Apple WWDC20 + official docs.
- **Phase 5 (Export):** `CGImageDestination` well-documented; one `exiftool` integration test.
- **Phase 7 (Polish):** Haptic + Reduce Motion patterns well-documented.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All core technologies verified against Apple official docs and WWDC sessions. SPM packages (Mantis, SwiftCube) verified active on GitHub. |
| Features | HIGH | Competitor feature matrix from official app listings, Darkroom 7 release notes, Lightroom Mobile Oct 2025 release notes, Apple HIG. Priority tiers match current competitor parity. |
| Architecture | HIGH | CIContext thread-safety, actor concurrency, and SwiftData migration patterns sourced from Apple official docs and Swift Forums. `AdjustmentStack` design is directly from architecture research. |
| Pitfalls | HIGH (rendering/LUT/UX), MEDIUM (SwiftData) | Color space, orientation, LUT dimension, and performance pitfalls sourced from Apple docs + verified community reports. SwiftData iOS 17–18 migration failure modes partially dependent on iOS minor version. |

**Overall confidence:** HIGH

### Gaps to Address

- **LUT aesthetic quality:** The pipeline is defined but visual quality of specific LUTs requires human judgment during Phase 2. Plan time for iterative LUT tuning — this is not automatable.
- **SwiftData iOS 17.x minor version bugs:** Known issues in iOS 17.0–17.4 (predicate bugs, transformable array regressions). The JSON blob strategy mitigates migration risk, but test on the oldest iOS 17 minor version in the TestFlight cohort before shipping Phase 4.
- **Performance ceiling on older devices:** Research recommends 1024px preview renders but does not specify the oldest target device. An iPhone SE (2nd gen) on iOS 17 has materially different GPU throughput than an iPhone 15 Pro. Profile on the oldest expected device early in Phase 1.
- **Tone curves (if promoted from v2):** The `CIToneCurve` 5-point constraint and custom `Canvas` UI have known edge cases not fully explored. If tone curves are promoted to v1.x, they need their own research pass.

---

## Sources

### Primary (HIGH confidence)
- Apple Developer Docs — `CIColorCube`, `CIColorCubeWithColorSpace`, `CIToneCurve`, `CIContext` thread-safety
- Apple Developer Docs — `CGImageDestination`, `kCGImageDestinationLossyCompressionQuality`
- Apple WWDC20 — "Optimize the Core Image pipeline for your video app"
- Apple WWDC23 — "Model your schema with SwiftData"; "Migrate to SwiftData"
- Apple WWDC24 — "Custom visual effects with SwiftUI"; SwiftUI accessibility improvements
- Apple HIG — Photo Editing
- GitHub — Mantis 2.31.1, SwiftCube 1.0.1

### Secondary (MEDIUM confidence)
- JuniperPhoton Substack — Color management across Apple frameworks (2024)
- Darkroom 7 rebuild announcement (Petapixel, 2025) + official update history
- VSCO 2026 review (The Editing Studio)
- Lightroom Mobile October 2025 release notes
- Atomic Robot — SwiftData migrations guide
- Michael Tsai blog — SwiftData iOS 17 predicate bugs
- Swift Forums — CIImage Sendable conformance, debounce with async/await

### Tertiary (supporting)
- CIColorCube data format deep-dive (chibicode.org)
- CIImage orientation fix examples (FlexMonkey/GitHub)
- SwiftUI gesture conflict analysis (fatbobman.com)
- Haptic Teardown #1 — Volume Slider (UX Design Bootcamp)
- PHImageManager memory management (copyprogramming.com)

---
*Research completed: 2026-05-03*
*Ready for roadmap: yes*

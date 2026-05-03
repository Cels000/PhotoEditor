# Roadmap: PhotoEditor

## Overview

Build a premium-feeling iOS photo editor from a brownfield SwiftUI seed. The architecture is dependency-driven: the rendering foundation and data model come first (Phase 1), then the LUT filter pipeline that defines the product's visual identity (Phase 2), then the full adjustment UI against real output (Phase 3), then library persistence that depends on a stable schema (Phase 4), then export (Phase 5), then recipes that require proven library round-trips (Phase 6), and finally a dedicated polish phase to make the interface feel genuinely premium (Phase 7).

## Phases

- [ ] **Phase 1: Rendering Foundation** - Replace the existing CIPhotoEffect pipeline with a Metal-backed RenderEngine, AdjustmentStack data model, and dual preview/export render paths
- [x] **Phase 2: LUT Filter Pipeline** - Ship 20–30 hand-curated 64-point LUT filters with stable IDs, per-filter defaults, strength blending, and a live-preview filter strip (completed 2026-05-03)
- [x] **Phase 3: Editor UI + Full Adjustments** - Build the complete editor surface (light, color, HSL, curves, grain, vignette, sharpen, crop, undo/redo, before/after) against the live render pipeline (completed 2026-05-03)
- [x] **Phase 4: Library + Persistence** - SwiftData-backed in-app library with thumbnails, re-edit capability, and graceful PHAsset handling (completed 2026-05-03)
- [x] **Phase 5: Export** - Full-resolution export with format/size/quality options, share sheet, ICC profile embedding, and EXIF passthrough (completed 2026-05-03)
- [ ] **Phase 6: Recipes** - Save, apply, rename, delete, and share named adjustment stacks via a custom `.photorecipe` file format
- [ ] **Phase 7: Polish + Accessibility** - Elevate the interface to genuinely premium: haptics, spring animations, VoiceOver audit, Dynamic Type XL verification, Reduce Motion compliance

## Phase Details

### Phase 1: Rendering Foundation
**Goal**: A working, correct render loop replaces the old CIPhotoEffect pipeline — sliders produce live output, full-res renders are deferred to export, color space and EXIF orientation are correct from day one
**Depends on**: Nothing (first phase)
**Requirements**: RENDER-01, RENDER-02, RENDER-03, RENDER-04, RENDER-05, RENDER-06
**Success Criteria** (what must be TRUE):
  1. A photo imported from the library appears at full fidelity — correct orientation on all 8 EXIF variants, no color drift vs. the original
  2. Dragging any slider updates the preview visibly smoothly with no perceptible lag (preview renders at ≤1080px; no full-res render fires during drag)
  3. The Metal-backed CIContext is confirmed active (software renderer never engages); verified by a log assert at launch
  4. An AdjustmentStack can be serialized to JSON and deserialized back with bit-identical values (schema version field present)
  5. The existing CIPhotoEffect path is fully removed or gated off; the new RenderEngine drives all rendering
**Plans**: 5 plans
  - [ ] 01-01-PLAN.md — AdjustmentStack value model (Codable, schemaVersion, full struct hierarchy)
  - [ ] 01-02-PLAN.md — XCTest stubs (AdjustmentStackTests, PipelineBuilderTests) + manual target setup README
  - [ ] 01-03-PLAN.md — PipelineBuilder (pure stage chain) and ImageImporter (orientation-correct CIImage path)
  - [ ] 01-04-PLAN.md — RenderEngine actor with Metal-backed preview + export contexts
  - [ ] 01-05-PLAN.md — EditorViewModel + ContentView rewire + delete legacy PhotoEditorViewModel

### Phase 2: LUT Filter Pipeline
**Goal**: The product's visual identity is established — 20–30 hand-curated film-look filters with stable IDs are selectable from a live-preview strip, blend strength is controllable, and favorites are persisted
**Depends on**: Phase 1
**Requirements**: FILTER-01, FILTER-02, FILTER-03, FILTER-04, FILTER-05, FILTER-06
**Success Criteria** (what must be TRUE):
  1. The filter strip shows thumbnails generated from the user's current photo and updates when a new photo is imported
  2. Selecting a filter applies it immediately; dragging the strength slider blends smoothly between unfiltered and full-strength
  3. Marking a filter as a Favorite moves it to the front of the strip and survives an app restart
  4. A unit test passes: an identity LUT produces pixel-identical output to no-filter, confirming correct CIColorCubeWithColorSpace usage and 64-point dimensions
  5. Every filter has a stable UUID; renaming a filter's display name does not change its ID
**Plans**: 6 plans
  - [ ] 02-01-PLAN.md — ColorCubeData value type (validated 64-point cube)
  - [ ] 02-02-PLAN.md — In-house CubeParser (.cube text → ColorCubeData) + tests
  - [ ] 02-03-PLAN.md — BuiltInLUTs (5 procedural starter LUTs)
  - [ ] 02-04-PLAN.md — Filter model + FilterLibrary @Observable service (favorites)
  - [ ] 02-05-PLAN.md — Wire PipelineBuilder.applyLUT with strength blend + identity test
  - [ ] 02-06-PLAN.md — FilterStripView + thumbnail cache + EditorViewModel/ContentView wiring

### Phase 3: Editor UI + Full Adjustments
**Goal**: The app is fully usable as a photo editor — all adjustment panels are functional against live output, crop and geometry work, undo/redo work, and the before/after compare is available
**Depends on**: Phase 2
**Requirements**: ADJUST-01, ADJUST-02, ADJUST-03, ADJUST-04, ADJUST-05, ADJUST-06, ADJUST-07, ADJUST-08, ADJUST-09, ADJUST-10, CROP-01, CROP-02, CROP-03, CROP-04, HIST-01, HIST-02, HIST-03
**Success Criteria** (what must be TRUE):
  1. All 6 light controls, 4 color controls, HSL per-channel panel, grain, vignette, and sharpen are accessible and update the live preview
  2. Tone curves (RGB + per-channel) can be shaped and the output reflects the curve in real time
  3. Crop with aspect-ratio presets, free rotate, straighten ruler, 90° rotate, and flip all work; re-opening a cropped photo shows no progressive pixel drift
  4. Undo and redo step through every discrete adjustment in the session; Reset All (with confirmation) returns to the original
  5. Press-and-hold the canvas shows the unedited original; release restores the edited view
  6. Double-tap any slider resets it to its default value
**Plans**: 10 plans
  - [ ] 03-01-PLAN.md — PipelineBuilder.applyLight: whites + blacks via CIToneCurve 5-point endpoint shaping
  - [ ] 03-02-PLAN.md — PipelineBuilder.applyColor: temperature + tint via CITemperatureAndTint
  - [ ] 03-03-PLAN.md — PipelineBuilder effects group: applyGrain, applyVignette, applySharpness
  - [ ] 03-04-PLAN.md — Reusable AdjustmentSlider + SliderValueFormatter (double-tap reset, value bubble, accessibility)
  - [ ] 03-05-PLAN.md — PipelineBuilder.applyHSL via CIColorMatrix-masked per-channel passes
  - [ ] 03-06-PLAN.md — PipelineBuilder.applyCurves (5-point sampled CIToneCurve, RGB + per-channel) and applySplitToning
  - [ ] 03-07-PLAN.md — UndoStack value type + EditorViewModel undo/redo with drag coalescing and reset-with-undo
  - [ ] 03-08-PLAN.md — Panel container UI: tabs + slide-up + Light/Color/HSL/Curves/Effects panels + UndoToolbar + CompareGesture (no canvas layout shift)
  - [ ] 03-09-PLAN.md — Crop module: aspect presets + rotate/flip + Mantis SPM bridge with #if canImport fallback (build never breaks)
  - [ ] 03-10-PLAN.md — Replace ContentView smoke-test sliders with full panel system; remove inline AdjustmentSlider declaration

### Phase 4: Library + Persistence
**Goal**: Edited photos persist in an in-app library across launches; users can return to any photo and continue editing exactly where they left off
**Depends on**: Phase 3
**Requirements**: LIB-01, LIB-02, LIB-03, LIB-04, LIB-05
**Success Criteria** (what must be TRUE):
  1. After editing and saving a photo, it appears in the library grid with a correct thumbnail and an "edited" badge
  2. Tapping a library item reopens the editor with the exact same adjustment stack — all slider values, filter selection, and crop state restored
  3. Deleting a library item removes the thumbnail and entry; a crash does not occur if the underlying PHAsset has been deleted from Photos
  4. Library data survives an app update (SwiftData VersionedSchema migration is non-destructive)
**Plans**: 6 plans
Plans:
- [ ] 04-01-PLAN.md — SwiftData LibraryItem @Model + VersionedSchema scaffold
- [ ] 04-02-PLAN.md — LibraryStore service (CRUD + observable items)
- [ ] 04-03-PLAN.md — ImageImporter PHAsset support + ThumbnailGenerator
- [ ] 04-04-PLAN.md — EditorViewModel saveToLibrary / openLibraryItem
- [ ] 04-05-PLAN.md — LibraryGridView + delete confirmation + PHAsset-deleted placeholder
- [ ] 04-06-PLAN.md — PhotoEditorApp ModelContainer + ContentView toolbar wiring

### Phase 5: Export
**Goal**: Users can get their edited photos out of the app in any practical format — saved to Photos, shared anywhere, with format, size, and quality control
**Depends on**: Phase 4
**Requirements**: EXPORT-01, EXPORT-02, EXPORT-03, EXPORT-04, EXPORT-05, EXPORT-06
**Success Criteria** (what must be TRUE):
  1. Tapping "Save to Photos" writes the full-resolution edited image to the camera roll with correct ICC profile and EXIF (date, orientation) and no GPS data
  2. Tapping "Share" opens the iOS share sheet with the edited image available for any system destination
  3. Format chooser (JPEG / HEIC / PNG), size presets (full / web / story / custom long-edge), and quality slider all produce correct output files
  4. Export completes with a visible progress indicator and a success/failure confirmation
**Plans**: 6 plans
Plans:
- [ ] 05-01-PLAN.md — ExportOptions / ExportFormat / ExportSize value types
- [ ] 05-02-PLAN.md — ExportService encoder (CGImageDestination + EXIF preserve + GPS strip + P3)
- [ ] 05-03-PLAN.md — PhotoSaver (PHAssetCreationRequest.addResource with raw Data)
- [ ] 05-04-PLAN.md — ShareSheetView (UIActivityViewController representable)
- [ ] 05-05-PLAN.md — EditorViewModel.export/saveExport/shareExport; remove legacy saveImage
- [ ] 05-06-PLAN.md — ExportSheetView UI + ContentView toolbar wiring

### Phase 6: Recipes
**Goal**: Users can capture a look as a named Recipe, reuse it across photos, and share it with others
**Depends on**: Phase 5
**Requirements**: RECIPE-01, RECIPE-02, RECIPE-03, RECIPE-04, RECIPE-05
**Success Criteria** (what must be TRUE):
  1. Saving a Recipe stores the full current adjustment stack (including filter ID and strength) under a user-chosen name
  2. Applying a Recipe to any photo replaces the current adjustment stack and immediately updates the preview
  3. Recipes can be renamed, reordered, and deleted from a management screen
  4. Exporting a Recipe produces a `.photorecipe` file that can be shared; importing it from Files or a share restores all values including filter reference — a missing filter UUID leaves the filter slot blank without crashing
**Plans**: 6 plans
Plans:
- [ ] 06-01-PLAN.md — RecipeItem @Model + LibrarySchemaV1 extension
- [ ] 06-02-PLAN.md — RecipeStore CRUD service
- [ ] 06-03-PLAN.md — ExportedRecipe Codable doc + .photorecipe file I/O
- [ ] 06-04-PLAN.md — Info.plist UTI registration for .photorecipe
- [ ] 06-05-PLAN.md — EditorViewModel applyRecipe/saveCurrentAsRecipe + missing-filter test
- [ ] 06-06-PLAN.md — Recipes UI (sheet, name prompt, toolbar, .onOpenURL import)

### Phase 7: Polish + Accessibility
**Goal**: The interface earns the "premium feel" claim — motion, haptics, accessibility, and visual design are all at the level of a paid pro app
**Depends on**: Phase 6
**Requirements**: UX-01, UX-02, UX-03, UX-04, UX-05, UX-06, UX-07, UX-08, UX-09
**Success Criteria** (what must be TRUE):
  1. The interface is visibly distinct from a default SwiftUI template: distinctive typography, color palette per Light/Dark mode, and motion design are all custom
  2. Slider interactions produce haptic feedback at zero-crossing, end-stops, and value-snaps; filter selection and recipe application have distinct haptic responses
  3. Panel transitions use spring animation with no canvas layout shift; Reduce Motion preference disables non-essential animations while all gestures remain functional
  4. VoiceOver can navigate and adjust every slider (accessibilityAdjustableAction), with correct labels and announced values; Dynamic Type XL does not truncate or overflow any control
  5. First-run photo library permission prompt appears with an explanation; `.limited` access is handled gracefully with a prompt to grant more access
**Plans**: TBD

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Rendering Foundation | 0/5 | Not started | - |
| 2. LUT Filter Pipeline | 0/6 | Complete    | 2026-05-03 |
| 3. Editor UI + Full Adjustments | 0/10 | Complete    | 2026-05-03 |
| 4. Library + Persistence | 0/TBD | Complete    | 2026-05-03 |
| 5. Export | 0/6 | Complete    | 2026-05-03 |
| 6. Recipes | 0/TBD | Not started | - |
| 7. Polish + Accessibility | 0/TBD | Not started | - |

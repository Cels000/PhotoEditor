# Requirements: PhotoEditor

**Defined:** 2026-05-03
**Core Value:** A photo editor that *feels* like a paid pro tool — distinctive filters, deep controls, polished interface — given away free, with edits you can come back to and refine.

## v1 Requirements

### Render Foundation

- [x] **RENDER-01**: App imports a photo from the iOS photo library preserving original orientation and color profile (sRGB/Display P3 round-trip without drift)
- [x] **RENDER-02**: All edits apply non-destructively — the source image is never mutated; every edit is reversible
- [x] **RENDER-03**: Live preview stays responsive (visibly smooth) while a slider is being dragged, by rendering at a downsampled resolution (≤1080px long edge)
- [x] **RENDER-04**: Full-resolution rendering only runs on export (or thumbnail generation), never per-slider-tick
- [x] **RENDER-05**: All rendering uses a Metal-backed CIContext; software rendering never engages
- [x] **RENDER-06**: Edit state is captured in a Codable adjustment-stack model, versioned with a schema integer for forward-compatibility

### Filter Library (LUT)

- [x] **FILTER-01**: App ships with at least 20 hand-curated film-style LUT filters covering film/portrait/B&W/cinematic categories
- [x] **FILTER-02**: Filters are presented as a horizontal strip with thumbnails generated from the user's current photo
- [x] **FILTER-03**: Each filter has a strength slider (0–100%) that smoothly blends between unfiltered and full-strength filtered output
- [x] **FILTER-04**: Filters can be marked as Favorites and Favorites appear first in the strip
- [x] **FILTER-05**: Each filter has a stable UUID so saved Recipes survive filter library updates
- [x] **FILTER-06**: Filters use 64-point `CIColorCubeWithColorSpace` LUTs in linear sRGB working space (no banding, no color drift)

### Adjustments

- [x] **ADJUST-01**: User can adjust Exposure, Contrast, Highlights, Shadows, Whites, Blacks (light panel, 6 controls, default 0)
- [x] **ADJUST-02**: User can adjust Saturation, Vibrance, Temperature, Tint (color panel, 4 controls, default 0)
- [x] **ADJUST-03**: User can adjust Hue, Saturation, Luminance per color channel (HSL panel, 8 channels × 3 controls)
- [x] **ADJUST-04**: User can shape RGB and per-channel tone curves (curves panel)
- [x] **ADJUST-05**: User can apply Split Toning to highlights and shadows (hue + amount per zone)
- [x] **ADJUST-06**: User can apply Grain (size + intensity controls)
- [x] **ADJUST-07**: User can apply Vignette (amount + feather)
- [x] **ADJUST-08**: User can apply Sharpen
- [x] **ADJUST-09**: Every slider supports double-tap to reset to default
- [x] **ADJUST-10**: Adjustments apply in a deterministic order (LUT → light → color → HSL → curves → split-toning → effects → crop) consistent across preview and export

### Crop & Geometry

- [x] **CROP-01**: User can crop with aspect-ratio presets (free, original, 1:1, 4:5, 3:4, 9:16, 16:9, etc.)
- [x] **CROP-02**: User can free-rotate / straighten the crop with an angle ruler
- [x] **CROP-03**: User can rotate in 90° steps (left/right) and flip horizontally/vertically
- [x] **CROP-04**: Crop/rotate/straighten is stored separately from color adjustments and applies after them, with no progressive pixel drift on re-edit

### History & Compare

- [x] **HIST-01**: User can undo and redo every adjustment within an editing session
- [x] **HIST-02**: User can press-and-hold the canvas to compare against the unedited original (before/after)
- [x] **HIST-03**: User can reset all edits at once (with a confirmation step)

### Library

- [x] **LIB-01**: Edited photos appear in an in-app library grid with thumbnails
- [x] **LIB-02**: User can re-open any library item and continue editing exactly where they left off
- [x] **LIB-03**: User can delete library items (with confirmation), and deleted items also remove their thumbnails
- [x] **LIB-04**: Library persists across app launches using SwiftData `VersionedSchema`; schema migrations are non-destructive
- [x] **LIB-05**: Library handles the case where the source PHAsset has been deleted from Photos (graceful error, not a crash)

### Recipes

- [x] **RECIPE-01**: User can save the current adjustment stack as a named Recipe
- [x] **RECIPE-02**: User can apply any saved Recipe to any photo (replaces the current adjustment stack)
- [x] **RECIPE-03**: User can rename, reorder, and delete saved Recipes
- [x] **RECIPE-04**: User can export a Recipe to a shareable file and import a Recipe from a shared file (round-trip preserves all values)
- [x] **RECIPE-05**: Recipes referencing a filter UUID that no longer exists fail gracefully (filter slot blank, other adjustments still apply)

### Export

- [x] **EXPORT-01**: User can save the full-resolution edited image to Photos (full-res, original aspect)
- [x] **EXPORT-02**: User can share via the system share sheet (any iOS share target)
- [x] **EXPORT-03**: User can choose export format: JPEG / HEIC / PNG
- [x] **EXPORT-04**: User can choose export size: full / web / story presets, plus custom long-edge value
- [x] **EXPORT-05**: Lossy formats (JPEG/HEIC) expose a quality slider
- [x] **EXPORT-06**: Exports preserve color profile (Display P3 where supported) and basic EXIF (date/orientation); GPS/identifying metadata stripped by default

### UX & Accessibility

- [x] **UX-01**: The interface visibly distinguishes itself from a stock SwiftUI template — distinctive typography, layout, and motion design
- [x] **UX-02**: All slider interactions have appropriate haptics (zero-crossing tick, end-stop bump, value-snap)
- [x] **UX-03**: Panel transitions use spring animation with no layout shift in the canvas during open/close
- [x] **UX-04**: All controls support Dynamic Type up to XL without truncation or overflow
- [x] **UX-05**: All adjustment controls have correct VoiceOver labels and use `.accessibilityAdjustableAction` so values are announced and adjustable
- [x] **UX-06**: Reduce Motion preference disables non-essential animations; all gestures remain functional
- [x] **UX-07**: App supports both Light and Dark appearance with deliberate per-mode color choices (not just system defaults)
- [x] **UX-08**: First-run flow explains the photo-library permission and gracefully handles `.limited` access
- [x] **UX-09**: iPhone layout is the primary target; iPad runs the same layout without crashing or clipping

## v2 Requirements

### Camera

- **CAM-01**: In-app manual camera (ISO/shutter/focus/WB)
- **CAM-02**: RAW (DNG) capture
- **CAM-03**: Grid overlay, level indicator, front/back switching, flash control
- **CAM-04**: Direct hand-off from camera capture into the editor

### Polish & Beyond

- **CLOUD-01**: Optional iCloud sync of library + recipes (CloudKit, no accounts)
- **IPAD-01**: iPad-optimized layout (split panels, keyboard shortcuts, pencil support)
- **BATCH-01**: Apply a Recipe to multiple library items at once

## Out of Scope

| Feature | Reason |
|---------|--------|
| Social feed / profiles / discovery | VSCO's social side is explicitly not part of this product — editor only |
| Accounts / sign-in / auth | No backend by design |
| AI auto-enhance / sky replace / generative fill | Contradicts the "human-curated film look" identity |
| Video editing | Photos only |
| Subscriptions / IAP / paid filter packs | Free, no monetization |
| Real-time collaborative editing | Local-only by design |
| Backend / analytics / telemetry | Local-only, privacy-first |
| Watermark on exports | Free product, no attribution required |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| RENDER-01 | Phase 1 | Complete |
| RENDER-02 | Phase 1 | Complete |
| RENDER-03 | Phase 1 | Complete |
| RENDER-04 | Phase 1 | Complete |
| RENDER-05 | Phase 1 | Complete |
| RENDER-06 | Phase 1 | Complete |
| FILTER-01 | Phase 2 | Complete |
| FILTER-02 | Phase 2 | Complete |
| FILTER-03 | Phase 2 | Complete |
| FILTER-04 | Phase 2 | Complete |
| FILTER-05 | Phase 2 | Complete |
| FILTER-06 | Phase 2 | Complete |
| ADJUST-01 | Phase 3 | Complete |
| ADJUST-02 | Phase 3 | Complete |
| ADJUST-03 | Phase 3 | Complete |
| ADJUST-04 | Phase 3 | Complete |
| ADJUST-05 | Phase 3 | Complete |
| ADJUST-06 | Phase 3 | Complete |
| ADJUST-07 | Phase 3 | Complete |
| ADJUST-08 | Phase 3 | Complete |
| ADJUST-09 | Phase 3 | Complete |
| ADJUST-10 | Phase 3 | Complete |
| CROP-01 | Phase 3 | Complete |
| CROP-02 | Phase 3 | Complete |
| CROP-03 | Phase 3 | Complete |
| CROP-04 | Phase 3 | Complete |
| HIST-01 | Phase 3 | Complete |
| HIST-02 | Phase 3 | Complete |
| HIST-03 | Phase 3 | Complete |
| LIB-01 | Phase 4 | Complete |
| LIB-02 | Phase 4 | Complete |
| LIB-03 | Phase 4 | Complete |
| LIB-04 | Phase 4 | Complete |
| LIB-05 | Phase 4 | Complete |
| EXPORT-01 | Phase 5 | Complete |
| EXPORT-02 | Phase 5 | Complete |
| EXPORT-03 | Phase 5 | Complete |
| EXPORT-04 | Phase 5 | Complete |
| EXPORT-05 | Phase 5 | Complete |
| EXPORT-06 | Phase 5 | Complete |
| RECIPE-01 | Phase 6 | Complete |
| RECIPE-02 | Phase 6 | Complete |
| RECIPE-03 | Phase 6 | Complete |
| RECIPE-04 | Phase 6 | Complete |
| RECIPE-05 | Phase 6 | Complete |
| UX-01 | Phase 7 | Complete |
| UX-02 | Phase 7 | Complete |
| UX-03 | Phase 7 | Complete |
| UX-04 | Phase 7 | Complete |
| UX-05 | Phase 7 | Complete |
| UX-06 | Phase 7 | Complete |
| UX-07 | Phase 7 | Complete |
| UX-08 | Phase 7 | Complete |
| UX-09 | Phase 7 | Complete |

**Coverage:**
- v1 requirements: 49 total
- Mapped to phases: 49 (6 + 6 + 17 + 5 + 6 + 5 + 9)
- Unmapped: 0 ✓

---
*Requirements defined: 2026-05-03*
*Last updated: 2026-05-03 after roadmap creation*

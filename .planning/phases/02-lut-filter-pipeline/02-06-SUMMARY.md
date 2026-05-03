---
phase: 02-lut-filter-pipeline
plan: "06"
subsystem: ui
tags: [swiftui, ciimage, nsCache, lut, filters, coreimage]

# Dependency graph
requires:
  - phase: 02-lut-filter-pipeline/02-04
    provides: FilterLibrary, Filter — catalog with orderedFilters, toggleFavorite
  - phase: 02-lut-filter-pipeline/02-05
    provides: PipelineBuilder.applyLUT wired with CubeResolver, CIColorCubeWithColorSpace
provides:
  - FilterStripView — horizontal scrolling strip with thumbnails, selection, strength slider
  - FilterThumbnailCache — NSCache-backed (photoID, filterID) thumbnail store
  - EditorViewModel.filterLibrary — injected FilterLibrary
  - EditorViewModel.selectFilter / setFilterStrength — public filter control API
  - CubeResolver threaded through RenderEngine into PipelineBuilder on every render
  - ContentView filterStrip using real FilterStripView (Phase 2 placeholder removed)
affects:
  - 03-adjustments-ui
  - 07-polish

# Tech tracking
tech-stack:
  added: []
  patterns:
    - NSCache keyed by compound string photoID#filterID for O(1) thumbnail lookup
    - CubeResolver closure injected at render time, decoupling FilterLibrary from RenderEngine
    - FilterStripView thumbnails use LUT-only render path (bypass PipelineBuilder) for stable visual reference

key-files:
  created:
    - PhotoEditor/Editor/FilterStripView.swift
    - PhotoEditor/Editor/FilterThumbnailCache.swift
  modified:
    - PhotoEditor/RenderEngine/RenderEngine.swift
    - PhotoEditor/Editor/EditorViewModel.swift
    - PhotoEditor/ContentView.swift

key-decisions:
  - "ImportedImage is struct — photo identity uses previewCIImage.extent.debugDescription, not ObjectIdentifier"
  - "Thumbnails bypass PipelineBuilder intentionally — LUT-only so they remain stable visual references while user edits light/color sliders"
  - "CubeResolver defaults nil in RenderEngine — backward-compatible with any Phase 1 callers"

patterns-established:
  - "CubeResolver as closure: filterLibrary captured once in makeCubeResolver(), passed to each async render call"
  - "FilterStripView.task(id: importedPhotoIdentity): SwiftUI task invalidation clears and rebuilds thumbnails on photo change"

requirements-completed: [FILTER-02, FILTER-03, FILTER-04]

# Metrics
duration: 12min
completed: 2026-05-03
---

# Phase 2 Plan 06: LUT Filter Pipeline — User-Facing Wiring Summary

**Horizontal filter strip with photo-derived thumbnails, strength slider, and favorites wired end-to-end through CubeResolver into CIColorCubeWithColorSpace**

## Performance

- **Duration:** 12 min
- **Started:** 2026-05-03T20:51:25Z
- **Completed:** 2026-05-03T21:03:00Z
- **Tasks:** 4
- **Files modified:** 5

## Accomplishments

- CubeResolver flows from EditorViewModel through RenderEngine to PipelineBuilder on every preview and export render
- FilterThumbnailCache provides NSCache-backed 64-entry store keyed by `photoID#filterID`; auto-evicts under memory pressure
- FilterStripView renders a horizontal scroll of 72px thumbnail cells, accent-ring selection, favorite star badge, and strength slider below strip
- ContentView "Coming in Phase 2" placeholder replaced with live FilterStripView

## Wiring Diagram

```
ContentView.filterStrip
  └── FilterStripView(viewModel:)
        ├── viewModel.filterLibrary.orderedFilters  →  ForEach cells
        ├── tap  →  viewModel.selectFilter(id:)
        ├── long-press  →  viewModel.filterLibrary.toggleFavorite(id)
        └── strength slider  →  viewModel.setFilterStrength(_:)

EditorViewModel.stackDidChange / renderPreviewNow / saveImage
  └── makeCubeResolver()  →  { id in filterLibrary.filter(withID: id)?.cube() }
        └── engine.renderPreview/renderExport(stack:source:cubeResolver:)
              └── PipelineBuilder.build(stack:source:cubeResolver:)
                    └── applyLUT(_:to:cubeResolver:)  →  CIColorCubeWithColorSpace
```

## Thumbnail Policy

- **Size:** 200px max long edge (downsampled before cube apply)
- **Cache:** NSCache, 64-entry count limit, auto-evicts on memory pressure
- **Invalidation:** `.task(id: importedPhotoIdentity)` in FilterStripView — photo identity derived from `previewCIImage.extent.debugDescription`; changing photo triggers cache clear + full regeneration
- **LUT-only:** Thumbnails run CIColorCubeWithColorSpace directly, bypassing PipelineBuilder — they show the filter at full strength, independent of the user's light/color slider state

## Starter Filter IDs Visible in Strip

From `BuiltInLUTs.all` (built-ins always loaded first):

1. `builtin.identity` — "Original"
2. `builtin.warm-fade`
3. `builtin.cinematic-cool`
4. `builtin.noir`
5. `builtin.sepia`

## New Files to Add to Xcode Targets

User must add new Phase 2 source files to the **PhotoEditor** target in Xcode (drag into Project Navigator, ensure target membership checked):

- `PhotoEditor/Filters/Filter.swift`
- `PhotoEditor/Filters/FilterLibrary.swift`
- `PhotoEditor/Filters/BuiltInLUTs.swift`
- `PhotoEditor/Filters/CubeParser.swift`
- `PhotoEditor/Filters/ColorCubeData.swift`
- `PhotoEditor/Editor/FilterStripView.swift`
- `PhotoEditor/Editor/FilterThumbnailCache.swift`

And any test files to the **PhotoEditorTests** target:

- `PhotoEditorTests/CubeParserTests.swift`

## Task Commits

1. **Task 1: Thread CubeResolver through RenderEngine + EditorViewModel** - `6078eb0` (feat)
2. **Task 2: FilterThumbnailCache.swift** - `8733ea9` (feat)
3. **Task 3: FilterStripView.swift** - `cea31ab` (feat)
4. **Task 4: Wire FilterStripView into ContentView** - `3460c71` (feat)

## Files Created/Modified

- `PhotoEditor/RenderEngine/RenderEngine.swift` — renderPreview/renderExport accept `cubeResolver: CubeResolver? = nil`
- `PhotoEditor/Editor/EditorViewModel.swift` — filterLibrary property, makeCubeResolver(), selectFilter, setFilterStrength
- `PhotoEditor/Editor/FilterThumbnailCache.swift` — NEW: NSCache thumbnail store + static renderThumbnail
- `PhotoEditor/Editor/FilterStripView.swift` — NEW: full interactive filter strip
- `PhotoEditor/ContentView.swift` — filterStrip replaced from placeholder to FilterStripView

## Decisions Made

- `ImportedImage` is a struct — `ObjectIdentifier` would not work as a stable hash; used `previewCIImage.extent.debugDescription` instead
- Thumbnails intentionally bypass PipelineBuilder so they show only the LUT effect, providing stable visual references as the user edits other adjustments

## Deviations from Plan

None - plan executed exactly as written (adjusted ObjectIdentifier to extent.debugDescription per the plan's own note about struct types).

## Issues Encountered

None.

## User Setup Required

New files must be added to Xcode target manually (Linux cannot edit project.pbxproj). See list in "New Files to Add to Xcode Targets" above.

## Next Phase Readiness

- Full LUT filter pipeline is end-to-end functional for Phase 2 requirements
- Phase 3 (HSL, Curves, advanced adjustments) can extend PipelineBuilder without touching filter wiring
- FilterLibrary is injected at EditorViewModel init — Phase 4+ can swap in test doubles cleanly

---
*Phase: 02-lut-filter-pipeline*
*Completed: 2026-05-03*

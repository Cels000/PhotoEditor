---
phase: 02-lut-filter-pipeline
plan: "04"
subsystem: filters
tags: [swift, observable, userdefaults, lut, filter-catalog]

requires:
  - phase: 02-lut-filter-pipeline plan 01
    provides: ColorCubeData — validated 64-point cube payload
  - phase: 02-lut-filter-pipeline plan 02
    provides: CubeParser — .cube file parsing with trilinear resample
  - phase: 02-lut-filter-pipeline plan 03
    provides: BuiltInLUTs — procedural starter LUTs with stable IDs
provides:
  - Filter model (Identifiable, Equatable, stable String id, lazy cube() accessor)
  - FilterLibrary @Observable service (catalog + favorites + orderedFilters)
affects: [02-05-pipeline-wiring, 02-06-editor-wiring, 06-recipes]

tech-stack:
  added: []
  patterns:
    - "@Observable final class for read-mostly services"
    - "Class-backed cache (CubeCache) to memoize results through value-type copies"
    - "Stable String IDs: builtin.* for procedural, cube.<lowercased-filename> for .cube files"

key-files:
  created:
    - PhotoEditor/Filters/Filter.swift
    - PhotoEditor/Filters/FilterLibrary.swift
  modified: []

key-decisions:
  - "Filter.id is String (not UUID) to match FilterSelection.filterID from Phase 1 AdjustmentStack"
  - "CubeCache is a private class inside Filter — memoization survives value-type copies"
  - "FilterLibrary.orderedFilters always places identity (builtin.identity) first regardless of favorites"
  - "Bundled .cube files use cube.<lowercased-filename> as stable ID; file renames change identity, content edits do not"
  - "Favorites persisted to UserDefaults key filter.favorites as [String] array"

patterns-established:
  - "Lazy cube loading: cube() checks CubeCache.value, builds on miss, stores result"
  - "Injectable UserDefaults + Bundle in init for testability"
  - "Filter catalog merges built-ins first, then bundled .cube files in filename-sorted order"

requirements-completed: [FILTER-01, FILTER-04, FILTER-05]

duration: 8min
completed: 2026-05-03
---

# Phase 2 Plan 04: Filter Model and FilterLibrary Catalog Summary

**`Filter` struct with stable String IDs and lazy cube caching + `@Observable FilterLibrary` merging 5 built-in procedural LUTs with bundled `.cube` files, favorites persisted under `filter.favorites` UserDefaults key**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-05-03T21:07:19Z
- **Completed:** 2026-05-03T21:15:00Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- `Filter` model: `Identifiable`, `Equatable`, stable `String` id, `Kind` enum (`.builtIn`/`.cubeFile`), lazy `cube()` method with class-backed memoization cache
- `FilterLibrary` `@Observable` service: loads `BuiltInLUTs.all` at init, scans `Bundle.main/LUTs/*.cube` in filename order, exposes `orderedFilters` (identity first, then favorites, then rest)
- `toggleFavorite(_:)` persists `Set<String>` to `UserDefaults` key `filter.favorites`; injected `UserDefaults`/`Bundle` make the class fully testable

## Task Commits

Each task was committed atomically:

1. **Task 1: Create Filter.swift model** - `688d8cc` (feat)
2. **Task 2: Create FilterLibrary.swift @Observable service** - `da5966a` (feat)

## Files Created/Modified
- `PhotoEditor/Filters/Filter.swift` — Filter model with Kind enum, lazy cube cache
- `PhotoEditor/Filters/FilterLibrary.swift` — @Observable catalog, favorites, orderedFilters

## Decisions Made
- `Filter.id` is `String` (not `UUID`) — required to match `FilterSelection.filterID: String` from Phase 1
- `CubeCache` private class inside Filter.swift ensures `cube()` memoization is not reset when Filter values are copied
- `orderedFilters` always pins `builtin.identity` first so "Original" never moves regardless of favorites
- `cube.<lowercased-filename>` ID scheme: lowercased for case-insensitive stability; renames intentionally break the ID (Recipes should reference the stable name)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- `Filter` and `FilterLibrary` are ready for Plan 02-05 (PipelineBuilder LUT wiring) and Plan 02-06 (EditorViewModel injection)
- Phase 6 Recipes should reference `builtin.*` and `cube.<lowercased-filename>` ID patterns documented here

---
*Phase: 02-lut-filter-pipeline*
*Completed: 2026-05-03*

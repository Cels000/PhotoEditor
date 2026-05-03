---
phase: 06-recipes
plan: 02
subsystem: database
tags: [swiftdata, observable, crud, swift]

requires:
  - phase: 06-01
    provides: RecipeItem @Model with sortOrder, stackData, thumbnailData fields

provides:
  - RecipeStore: @Observable @MainActor CRUD service for RecipeItem persistence
  - save(name:stack:thumbnail:) returning inserted RecipeItem
  - rename(_:to:) with whitespace trimming and empty-name guard
  - reorder(_:) rewriting sortOrder from array index
  - delete(_:) freeing inline thumbnail data
  - refresh() sorted fetch used after every mutation

affects: [06-03, 06-04, 06-05]

tech-stack:
  added: []
  patterns:
    - "RecipeStore mirrors LibraryStore: explicit refresh() after every mutation, no @Query"
    - "sortOrder computed as (max existing + 1) on insert so new items always append"

key-files:
  created:
    - PhotoEditor/Library/RecipeStore.swift
  modified: []

key-decisions:
  - "RecipeStore uses explicit refresh() after every mutation rather than @Query — UI-agnostic, consistent with LibraryStore pattern"
  - "nextOrder = (items.map { $0.sortOrder }.max() ?? -1) + 1 ensures monotonic append without gaps"

patterns-established:
  - "RecipeStore: @Observable @MainActor with private(set) var items, explicit refresh() — matches LibraryStore shape exactly"

requirements-completed: [RECIPE-01, RECIPE-02, RECIPE-03]

duration: 5min
completed: 2026-05-03
---

# Phase 06 Plan 02: RecipeStore Summary

**@Observable @MainActor CRUD service wrapping ModelContext for RecipeItem with save/rename/reorder/delete/refresh, mirroring LibraryStore pattern**

## Performance

- **Duration:** 5 min
- **Started:** 2026-05-03T22:15:00Z
- **Completed:** 2026-05-03T22:20:00Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Created RecipeStore as single owner of RecipeItem persistence
- All five CRUD methods implemented: save, rename, reorder, delete, refresh
- sortOrder auto-computed on insert; reorder rewrites all indices from array position

## Task Commits

1. **Task 1: Implement RecipeStore service** - `6f57cad` (feat)

## Files Created/Modified
- `PhotoEditor/Library/RecipeStore.swift` - @Observable @MainActor CRUD facade for RecipeItem

## Decisions Made
None - followed plan as specified

## Deviations from Plan
None - plan executed exactly as written

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- RecipeStore ready for 06-03 (ExportedRecipe Codable + share/import) and 06-05 (EditorViewModel wiring)
- RECIPE-01, RECIPE-02, RECIPE-03 persistence layer complete

---
*Phase: 06-recipes*
*Completed: 2026-05-03*

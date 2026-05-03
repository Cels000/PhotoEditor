---
phase: 02-lut-filter-pipeline
plan: "03"
subsystem: filters
tags: [lut, colorcube, cifilter, swift, procedural]

requires:
  - phase: 02-lut-filter-pipeline/02-01
    provides: ColorCubeData struct with dimension, init?(rgbTriplets:), identity()

provides:
  - enum BuiltInLUTs with five procedural 64-point starter LUTs
  - BuiltInLUTs.ID stable string constants (builtin.identity, builtin.warm_fade, builtin.cinematic_cool, builtin.noir, builtin.sepia)
  - BuiltInLUTs.Descriptor carrying id/displayName/category/make closure
  - BuiltInLUTs.all [Descriptor] array for FilterLibrary consumption

affects:
  - 02-lut-filter-pipeline/02-04 (FilterLibrary merges these with .cube files)
  - Phase 6 Recipes (reference stable IDs)

tech-stack:
  added: []
  patterns:
    - "Procedural LUT generation: build() helper iterates B-outer/G-middle/R-inner over 64^3 voxels"
    - "Stable string IDs in nested ID enum — never change, Recipes depend on them"
    - "Descriptor value type bundles metadata + factory closure for lazy construction"

key-files:
  created:
    - PhotoEditor/Filters/BuiltInLUTs.swift
  modified: []

key-decisions:
  - "Procedural starters are explicit PLACEHOLDERS — comments call this out; artist .cube files are the real aesthetic"
  - "Stable IDs in BuiltInLUTs.ID are frozen for Phase 6 Recipes — documented with DO NOT CHANGE comment"
  - "Build helper uses force-unwrap on ColorCubeData(rgbTriplets:) — safe by construction (count is always 64^3 * 3)"

patterns-established:
  - "LUT factory pattern: static func returning ColorCubeData, wired into Descriptor.make closure"

requirements-completed: [FILTER-01]

duration: 5min
completed: 2026-05-03
---

# Phase 2 Plan 03: BuiltInLUTs Summary

**Five procedurally-generated 64-point starter LUTs in pure Swift — identity, warmFade, cinematicCool, noir, sepia — with frozen stable IDs for Phase 6 Recipes**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-05-03T20:30:00Z
- **Completed:** 2026-05-03T20:35:00Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- Created `PhotoEditor/Filters/BuiltInLUTs.swift` with enum, five factory functions, and all metadata
- Locked five stable string IDs in `BuiltInLUTs.ID` that Phase 6 Recipes will reference
- Established `Descriptor` value type carrying id/displayName/category/make for `FilterLibrary` to consume
- `build()` helper enforces canonical B-outer/G-middle/R-inner sweep order matching `ColorCubeData`

## Stable IDs (DO NOT CHANGE)

| ID | Display Name | Category |
|----|-------------|---------|
| `builtin.identity` | Original | film |
| `builtin.warm_fade` | Warm Fade | film |
| `builtin.cinematic_cool` | Cool Cine | cinematic |
| `builtin.noir` | Noir B&W | bw |
| `builtin.sepia` | Sepia | film |

These IDs are referenced by Recipes (Phase 6). Changing them will break saved recipes.

## Task Commits

1. **Task 1: Implement BuiltInLUTs.swift** - `dcf1bd0` (feat)

**Plan metadata:** (this commit)

## Files Created/Modified

- `PhotoEditor/Filters/BuiltInLUTs.swift` — Five procedural 64-point LUT factory functions with stable IDs, Descriptor type, and all array

## Decisions Made

- Force-unwrap on `ColorCubeData(rgbTriplets:)!` is safe by construction — the `build()` helper always produces exactly `64^3 * 3` floats
- Procedural starters are PLACEHOLDERS — code comments emphasize this distinction so future devs don't mistake them for final aesthetics
- `BuiltInLUTs.ID` stable strings are frozen; noted with `DO NOT CHANGE` comment

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None. `PhotoEditor/Filters/` directory was created as part of this task (no pre-existing directory).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Plan 02-04 (FilterLibrary loader) can consume `BuiltInLUTs.all` directly to merge with `.cube` files
- Plan 02-05 (LUT application) can reference stable IDs for filter selection
- Phase 6 Recipes can reference all five `builtin.*` IDs without code changes

---
*Phase: 02-lut-filter-pipeline*
*Completed: 2026-05-03*

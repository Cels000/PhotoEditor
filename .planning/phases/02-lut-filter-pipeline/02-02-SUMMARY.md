---
phase: 02-lut-filter-pipeline
plan: 02
subsystem: filters
tags: [swift, cube-lut, cube-parser, trilinear-interpolation, xctest]

# Dependency graph
requires:
  - phase: 02-lut-filter-pipeline
    provides: ColorCubeData struct (plan 02-01, same wave)
provides:
  - Pure-Swift .cube file parser with enum CubeParser
  - Trilinear resampler for 16/32/33-point → 64-point upscaling
  - CubeParserTests with 6 test cases covering all parser paths
affects:
  - 02-03-BuiltInLUTs (must use same R-fastest sweep order)
  - 02-04-FilterLibrary (calls CubeParser.parse(text:) to load .cube files)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "CubeParser as enum namespace (no instantiation) — pure-static functions"
    - "parse(text:) returns nil; parseThrowing(text:) throws — dual API for diagnostics"
    - "R-fastest sweep: index = ((b * size + g) * size + r) * 3 — must be consistent across all LUT code"

key-files:
  created:
    - PhotoEditor/Filters/CubeParser.swift
    - PhotoEditorTests/CubeParserTests.swift
  modified:
    - PhotoEditorTests/README.md

key-decisions:
  - "R-fastest sweep order ((b,g,r) outer→inner) matches Resolve .cube format and must be consistent in BuiltInLUTs and ColorCubeData.identity()"
  - "Accepted sizes: {16, 32, 33, 64} — others rejected with nil; all resampled to 64-point output"
  - "No SPM dependency — ~160 LOC pure-Swift implementation as planned"
  - "parse(text:) logs to stderr via FileHandle.standardError; never crashes on malformed input"

patterns-established:
  - "Dual parse API: parse() → nil on error (user-facing), parseThrowing() → throws (diagnostic)"
  - "DOMAIN_MIN/MAX normalization applied before resampling"

requirements-completed: [FILTER-06]

# Metrics
duration: 2min
completed: 2026-05-03
---

# Phase 02 Plan 02: CubeParser Summary

**Pure-Swift `.cube` LUT parser with trilinear 33→64-point resampling — no SPM dependency, nil-on-malformed API**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-05-03T20:44:49Z
- **Completed:** 2026-05-03T20:46:04Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- `enum CubeParser` with `parse(text:) -> ColorCubeData?` and `parseThrowing` variant for diagnostics
- Trilinear resampler handles sizes {16, 32, 33, 64} → 64-point output using R-fastest sweep order
- DOMAIN_MIN/MAX header normalization before resampling
- 6-test suite covering identity roundtrip, 33→64 resample, invalid size rejection, comments+title, domain scaling, malformed input

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement CubeParser.swift** - `800076d` (feat)
2. **Task 2: Add CubeParserTests.swift** - `fb328f3` (test)

## Files Created/Modified
- `PhotoEditor/Filters/CubeParser.swift` - Pure-Swift .cube parser enum, 169 lines
- `PhotoEditorTests/CubeParserTests.swift` - 6 XCTest methods covering all parser paths
- `PhotoEditorTests/README.md` - Added CubeParserTests.swift to Xcode setup steps

## Decisions Made
- R-fastest sweep order (`((b * size + g) * size + r) * 3`) is the canonical index layout. Plan 02-03 (BuiltInLUTs) MUST use the same sweep order when generating procedural LUT data arrays.
- Accepted sizes restricted to {16, 32, 33, 64}. Anything else returns nil (not a silent identity fallback).
- `parse(text:)` is the nil-returning user API; `parseThrowing(text:)` is internal — kept internal/fileprivate available for future diagnostic tooling.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- `ColorCubeData.swift` (plan 02-01) not yet on disk — no blocker since Linux dev env cannot compile Swift; test suite requires Xcode on Mac. Both plans are wave 1 and will be added to the Xcode target together.

## User Setup Required
None — no external service configuration required.

## Next Phase Readiness
- CubeParser ready for plan 02-04 (FilterLibrary) to call `CubeParser.parse(text:)` on bundled `.cube` file contents
- Plan 02-03 (BuiltInLUTs) must use identical R-fastest sweep: `((b * 64 + g) * 64 + r) * 3` when writing procedural `[Float]` arrays
- Tests require plan 02-01 (ColorCubeData) to land before Xcode test run succeeds

---
*Phase: 02-lut-filter-pipeline*
*Completed: 2026-05-03*

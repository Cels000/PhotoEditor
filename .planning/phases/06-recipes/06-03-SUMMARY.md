---
phase: 06-recipes
plan: 03
subsystem: recipes
tags: [swift, codable, json, file-io, xctest]

requires:
  - phase: 06-01
    provides: RecipeItem SwiftData model and AdjustmentStack Codable identity stack

provides:
  - ExportedRecipe Codable struct with schemaVersion, name, stack, thumbnailJPEGBase64 fields
  - ExportedRecipe.fileExtension and ExportedRecipe.uti constants
  - RecipeFileIO namespace with encode, decode, writeTempFile, read(from:) methods
  - Round-trip unit test stubs covering encode→decode and write→read flows

affects: [06-04, 06-05, 06-06]

tech-stack:
  added: []
  patterns:
    - "Pure-namespace enum (RecipeFileIO) wraps JSONEncoder/JSONDecoder with typed error enum"
    - "Forward-compat Codable: all fields have defaults so older app decodes newer files"

key-files:
  created:
    - PhotoEditor/Library/ExportedRecipe.swift
    - PhotoEditor/Library/RecipeFileIO.swift
    - PhotoEditorTests/ExportedRecipeTests.swift
  modified: []

key-decisions:
  - "RecipeFileIO.encode uses prettyPrinted+sortedKeys for human-readable .photorecipe files"
  - "writeTempFile sanitizes doc.name with alphanumeric filter + UUID suffix for uniqueness"
  - "All ExportedRecipe fields carry defaults for forward-compat Codable decoding"

patterns-established:
  - "RecipeFileIO enum pattern: pure namespace with typed RecipeFileIOError, no state"
  - "ExportedRecipe.fileExtension / .uti constants are the single source of truth for 06-04 and 06-06"

requirements-completed: [RECIPE-04]

duration: 3min
completed: 2026-05-03
---

# Phase 06 Plan 03: ExportedRecipe + RecipeFileIO Summary

**Codable .photorecipe document format with JSONEncoder/Decoder file I/O namespace and four round-trip unit tests**

## Performance

- **Duration:** 3 min
- **Started:** 2026-05-03T22:15:19Z
- **Completed:** 2026-05-03T22:18:12Z
- **Tasks:** 1 (TDD: test commit + impl commit)
- **Files modified:** 3

## Accomplishments

- ExportedRecipe: Codable/Equatable struct wrapping AdjustmentStack with schemaVersion, name, and optional thumbnailJPEGBase64 field
- RecipeFileIO: encode (pretty-printed JSON), decode, writeTempFile (sanitized filename + UUID), and read(from:) methods
- Four test cases locking the format: full stack round-trip, disk write-read, thumbnail base64 survival, and missing-thumbnail decode

## Task Commits

1. **Test RED — ExportedRecipe round-trip tests** - `3eda34f` (test)
2. **Implementation GREEN — ExportedRecipe + RecipeFileIO** - `f260747` (feat)

## Files Created/Modified

- `PhotoEditor/Library/ExportedRecipe.swift` - Codable doc type with fileExtension/uti constants
- `PhotoEditor/Library/RecipeFileIO.swift` - encode/decode/writeTempFile/read namespace
- `PhotoEditorTests/ExportedRecipeTests.swift` - testRoundTrip, testWriteReadTempFile, testThumbnailBase64Roundtrip, testMissingThumbnailDecodes

## Decisions Made

- RecipeFileIO.encode uses `.prettyPrinted` + `.sortedKeys` — recipes are small so size is negligible, human readability wins
- writeTempFile strips non-alphanumeric chars from name and appends 8-char UUID prefix to avoid collisions
- All ExportedRecipe fields default-valued so future fields added to the wrapper schema won't break existing decoders

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Plan 06-04 (Info.plist UTI registration) can use `ExportedRecipe.fileExtension` and `ExportedRecipe.uti` constants directly
- Plan 06-05 (share sheet) calls `RecipeFileIO.writeTempFile(_:)` to get the URL for UIActivityViewController
- Plan 06-06 (.onOpenURL import) calls `RecipeFileIO.read(from:)` after receiving the file URL

---
*Phase: 06-recipes*
*Completed: 2026-05-03*

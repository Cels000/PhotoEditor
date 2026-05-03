---
phase: 05-export
plan: 03
subsystem: export
tags: [photos, photoskit, phassetcreationrequest, data, swift, ios]

requires:
  - phase: 05-export-plan-01
    provides: ExportFormat with .uti property (UTType identifiers)
  - phase: 05-export-plan-02
    provides: ExportService.encode producing pre-encoded Data blobs

provides:
  - PhotoSaver.save(encodedData:format:) async throws — writes raw encoded Data to Photos library
  - PhotoSaver.Error typed errors (permissionDenied, saveFailed)

affects: [05-05-export-sheet-ui, editor-view-model-export-wiring]

tech-stack:
  added: [Photos framework (PHAssetCreationRequest, PHPhotoLibrary)]
  patterns:
    - PHAssetCreationRequest.addResource(with:.photo,data:) for format-preserving Photos write
    - addOnly permission request (no read access escalation)
    - Accept both .authorized and .limited for Photos writes

key-files:
  created:
    - PhotoEditor/Export/PhotoSaver.swift
    - PhotoEditorTests/PhotoSaverTests.swift
  modified: []

key-decisions:
  - "PhotoSaver uses addResource(with:.photo,data:) not creationRequestForAsset(from:UIImage) — avoids JPEG re-encode and ICC profile strip (PITFALL #16)"
  - "Both .authorized and .limited PHAuthorizationStatus accepted as success — .limited still permits asset creation (PITFALL #17)"
  - "uniformTypeIdentifier set from format.uti so Photos records HEIC/JPEG/PNG correctly"
  - "Pure Foundation + Photos — no UIKit import, non-isolated enum callable from any actor"

patterns-established:
  - "Photos write pattern: performChanges + PHAssetCreationRequest.forAsset() + addResource(with:.photo,data:options:)"
  - "Pre-encoded Data path: ExportService.encode -> PhotoSaver.save preserves bytes verbatim"

requirements-completed: [EXPORT-01, EXPORT-06]

duration: 5min
completed: 2026-05-03
---

# Phase 05 Plan 03: PhotoSaver Summary

**PHAssetCreationRequest.addResource write path that preserves pre-encoded Data verbatim — no UIImage round-trip, no JPEG re-encode, ICC profile intact**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-05-03T21:57:00Z
- **Completed:** 2026-05-03T21:57:19Z
- **Tasks:** 1 (TDD: 2 commits — test then implementation)
- **Files modified:** 2

## Accomplishments

- Created `PhotoSaver` with `save(encodedData:format:)` async throws entry point
- Writes encoded `Data` via `PHAssetCreationRequest.addResource(with:.photo,data:)` — preserves format and quality choices made upstream by `ExportService`
- Requests `.addOnly` permission; accepts both `.authorized` and `.limited` so limited-access users can save
- Throws typed `PhotoSaver.Error` (permissionDenied, saveFailed) for clean error surfacing in the UI layer
- Test file verifies API contract (error cases, async throws signature)

## Task Commits

1. **Task 1 (RED): PhotoSaver failing tests** - `a45aefd` (test)
2. **Task 1 (GREEN): PhotoSaver implementation** - `e96dcb5` (feat)

## Files Created/Modified

- `PhotoEditor/Export/PhotoSaver.swift` — Public `enum PhotoSaver` with `save(encodedData:format:) async throws` and typed `Error`
- `PhotoEditorTests/PhotoSaverTests.swift` — API contract tests for error cases and method signature

## Decisions Made

- Used `addResource(with: .photo, data:)` instead of `creationRequestForAsset(from: UIImage)` to avoid JPEG re-encode that strips ICC profile (PITFALL #16)
- Accept both `.authorized` and `.limited` authorization statuses — `.limited` mode still permits asset creation but legacy code sometimes incorrectly rejects it (PITFALL #17)
- Set `options.uniformTypeIdentifier = format.uti` so Photos stores the asset with the correct type (otherwise Photos may misidentify HEIC as JPEG)
- No UIKit import — pure `Foundation` + `Photos`, callable from any actor context

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `PhotoSaver.save(encodedData:format:)` is ready for wiring into `EditorViewModel.export(options:)` (Plan 05-05 or later export sheet plan)
- The save path is complete: `ExportService.encode` produces `Data` → `PhotoSaver.save` writes it to Photos preserving bytes verbatim
- Share sheet path (Plan 05-04) uses a parallel pattern: write `Data` to temp file, present `UIActivityViewController`

---
*Phase: 05-export*
*Completed: 2026-05-03*

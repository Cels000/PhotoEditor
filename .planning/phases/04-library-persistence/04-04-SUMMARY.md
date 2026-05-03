---
phase: 04-library-persistence
plan: "04"
subsystem: editor
tags: [swiftdata, swiftui, photos, ciimage, undo]

requires:
  - phase: 04-01
    provides: LibraryItem SwiftData model with adjustmentStack computed property
  - phase: 04-02
    provides: LibraryStore save/update/delete service
  - phase: 04-03
    provides: ImageImporter.importImage(fromAssetID:) and ThumbnailGenerator.makeThumbnail

provides:
  - EditorViewModel.saveToLibrary() — persists current edit + thumbnail to LibraryStore (insert or update)
  - EditorViewModel.openLibraryItem(_:) — restores edit session from LibraryItem with clean undo history
  - currentLibraryItem lifecycle — tracks open item so re-saves update the same row

affects: [04-06, phase-05-export]

tech-stack:
  added: [SwiftData (imported in EditorViewModel)]
  patterns: [Task.detached for off-main thumbnail rendering, optional injection pattern for LibraryStore]

key-files:
  created: []
  modified:
    - PhotoEditor/Editor/EditorViewModel.swift

key-decisions:
  - "Task.detached(.background) for ThumbnailGenerator.makeThumbnail — keeps @MainActor EditorViewModel non-blocking during JPEG render"
  - "currentLibraryItem tracks insert-vs-update: set after first save, set on open, cleared on fresh picker import"
  - "openLibraryItem reseeds undoStack with loaded stack (not .identity) so undo does not regress to blank state"
  - "saveToLibrary/openLibraryItem do not throw — errors surface via errorMessage to match existing saveImage() pattern"

patterns-established:
  - "Library injection: libraryStore is optional var, set post-init by ContentView environment binding"
  - "PHAsset-deleted handling: guard sourceAssetID + catch ImageImportError.phAssetUnavailable produce user-facing string, no crash"

requirements-completed: [LIB-01, LIB-02, LIB-05]

duration: 8min
completed: 2026-05-03
---

# Phase 4 Plan 04: EditorViewModel Library Bridge Summary

**saveToLibrary() and openLibraryItem(_:) wired into EditorViewModel with off-main thumbnail generation, insert-vs-update tracking, and graceful PHAsset-deleted error handling**

## Performance

- **Duration:** 8 min
- **Started:** 2026-05-03T21:40:00Z
- **Completed:** 2026-05-03T21:48:00Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- EditorViewModel gains optional `libraryStore: LibraryStore?` (injected by ContentView, nil-safe for previews/tests)
- `saveToLibrary()` generates 400x400 thumbnail off-main via `Task.detached`, then inserts or updates via LibraryStore based on `currentLibraryItem`
- `openLibraryItem(_:)` re-loads PHAsset, restores `item.adjustmentStack` into `self.stack`, reseeds undo history, triggers preview render
- LIB-05: `ImageImportError.phAssetUnavailable` and nil `sourceAssetID` both produce a readable `errorMessage` with no crash path

## Task Commits

1. **Task 1: Add libraryStore + currentLibraryItem tracking** - `b5a7e50` (feat)
2. **Task 2: saveToLibrary + openLibraryItem methods** - `e8e5af6` (feat)

## Files Created/Modified
- `PhotoEditor/Editor/EditorViewModel.swift` - Added SwiftData import, libraryStore, currentLibraryItem, saveToLibrary(), openLibraryItem(_:)

## Decisions Made
- `libraryStore` is `var` (not `let`) so ContentView can inject it after `@State` initialization, before the SwiftData environment is resolved in `body`
- `undoStack.clear(seed: self.stack)` reseeds with the loaded stack, not `.identity`, preventing the first undo from jumping to a blank state
- `Task.detached` used explicitly so synchronous UIGraphicsImageRenderer calls leave the main thread entirely

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Plan 04-06 (ContentView toolbar wiring) can now call `editorViewModel.saveToLibrary()` and `editorViewModel.openLibraryItem(_:)` directly
- `editorViewModel.libraryStore = store` injection point is ready for ContentView `.task` or `.onChange`
- PHAsset-deleted path (LIB-05) is handled; no additional guard needed at the UI layer

---
*Phase: 04-library-persistence*
*Completed: 2026-05-03*

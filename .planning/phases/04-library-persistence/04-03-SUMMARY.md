---
phase: 04-library-persistence
plan: 03
subsystem: library
tags: [swift, photos, phAsset, ciimage, uikit, thumbnail, jpeg]

requires:
  - phase: 04-library-persistence
    provides: LibraryItem @Model with thumbnailData field (04-01)
  - phase: 01-rendering-foundation
    provides: RenderEngine.renderPreview, ImageImporter base path

provides:
  - ImportedImage.sourceAssetID field (PHAsset localIdentifier or nil)
  - ImageImporter.importImage(fromAssetID:) async throws for re-edit flow
  - ImageImportError.phAssetUnavailable for graceful PHAsset-not-found handling
  - ThumbnailGenerator.makeThumbnail(stack:source:engine:cubeResolver:) producing 400x400 JPEG Data

affects:
  - 04-04 (EditorViewModel hooks that call both helpers)
  - 04-05 (LibraryStore that stores thumbnailData)

tech-stack:
  added: [Photos framework (PHAsset, PHImageManager)]
  patterns:
    - PHAsset isolation: Photos import contained to ImageImporter.swift only
    - async/await + withCheckedThrowingContinuation for PHImageManager callback bridging
    - UIGraphicsImageRenderer for square-crop + scale before JPEG encode

key-files:
  created:
    - PhotoEditor/Library/ThumbnailGenerator.swift
  modified:
    - PhotoEditor/Editor/ImageImporter.swift

key-decisions:
  - "sourceAssetID field is Optional String — nil for picker-imported paths; avoids forced unwrap across non-PHAsset import paths"
  - "importImage(fromAssetID:) reuses existing importImage(from:) decode path so orientation + downsample logic stays in one place"
  - "PHImageManager requestImageDataAndOrientation preferred over requestImage with small targetSize — full decode then existing downsample matches picker import path exactly"
  - "ThumbnailGenerator uses engine.renderPreview (not a fresh CIContext) — caller provides preview-sized source, no duplicate context allocation"
  - "Photos framework import limited to ImageImporter.swift per PITFALLS guidance — PHAsset surface area contained"

requirements-completed: [LIB-01, LIB-02, LIB-05]

duration: 5min
completed: 2026-05-03
---

# Phase 04 Plan 03: ImageImporter PHAsset Loader + ThumbnailGenerator Summary

**PHAsset localIdentifier attached to ImportedImage with graceful error handling; 400x400 JPEG thumbnail generation via RenderEngine preview path**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-05-03T21:39:18Z
- **Completed:** 2026-05-03T21:44:00Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- `ImportedImage` now carries `sourceAssetID: String?` so every edit session can be traced back to its PHAsset across app launches
- `ImageImporter.importImage(fromAssetID:)` bridges PHImageManager callback to async/await, reuses the existing decode/orient/downsample pipeline, and throws `phAssetUnavailable` when the asset is missing or deleted (LIB-05)
- `ThumbnailGenerator.makeThumbnail` renders the applied AdjustmentStack, center-crops to square, scales to 400px, and encodes as JPEG (~30 KB target) — ready for storage in `LibraryItem.thumbnailData`

## Task Commits

1. **Task 1: Extend ImportedImage + add PHAsset loader** - `e03d136` (feat)
2. **Task 2: ThumbnailGenerator** - `70d1b7c` (feat)

## Files Created/Modified

- `PhotoEditor/Editor/ImageImporter.swift` - Added `sourceAssetID: String?` to `ImportedImage`, `phAssetUnavailable` error case, `importImage(fromAssetID:)` async method, `import Photos`
- `PhotoEditor/Library/ThumbnailGenerator.swift` - New file; `ThumbnailGenerator` enum with `makeThumbnail(stack:source:engine:cubeResolver:) async throws -> Data`

## Decisions Made

- `importImage(fromAssetID:)` delegates to existing `importImage(from:)` after data fetch — single decode path for orientation baking and downsampling
- `PHImageManager.requestImageDataAndOrientation` preferred for full-quality data (not `requestImage` with small target) — immediately enters the standard downsample pipeline
- `isNetworkAccessAllowed = true` so iCloud-stored assets download automatically per PITFALLS #5/#17
- `ThumbnailGenerator` is a pure stateless enum — no cache, no CIContext — caller owns lifecycle and background dispatch

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Plan 04-04 (EditorViewModel hooks) can now call `ImageImporter.importImage(fromAssetID:)` for re-edit flow and `ThumbnailGenerator.makeThumbnail` for save-to-library
- `LibraryItem.thumbnailData` storage path is unblocked

---
*Phase: 04-library-persistence*
*Completed: 2026-05-03*

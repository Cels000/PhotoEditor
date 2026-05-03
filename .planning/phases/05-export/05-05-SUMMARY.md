---
phase: 05-export
plan: "05"
subsystem: export-pipeline
tags: [export, editorviewmodel, render, encode, ciimage, cgimage, exif]
dependency_graph:
  requires: ["05-02", "05-03"]
  provides: [EditorViewModel.export, EditorViewModel.saveExport, EditorViewModel.shareExport]
  affects: [ContentView, ExportService, PhotoSaver, RenderEngine]
tech_stack:
  added: [ImageIO]
  patterns: [Task.detached-encode, CGImageSource-exif, defer-isExporting]
key_files:
  modified:
    - PhotoEditor/Editor/EditorViewModel.swift
decisions:
  - "ExportPipelineError defined at file scope above EditorViewModel class for clean namespacing"
  - "readSourceMetadata is private static so it can be called from a Task.detached context without capturing self"
  - "Task.detached(.userInitiated) for encode step keeps @MainActor non-blocking during CPU-heavy CGImageDestination work"
  - "readSourceMetadata returns Optional tuple — nil path falls back to empty props + CIImage.colorSpace gracefully"
metrics:
  duration: 5min
  completed: 2026-05-03
  tasks_completed: 1
  files_modified: 1
---

# Phase 5 Plan 05: EditorViewModel Export Pipeline Summary

Replace legacy `saveImage()` (UIImage round-trip + `creationRequestForAsset`) with a real export pipeline that preserves color profile and EXIF end-to-end.

## New Public Methods

```swift
func export(options: ExportOptions) async throws -> Data
func saveExport(options: ExportOptions) async
func shareExport(options: ExportOptions) async
```

### `export(options:) async throws -> Data`
- Guards: `engine` and `importedImage` must be non-nil; throws `ExportPipelineError.engineUnavailable` or `.notReady`.
- Sets `isExporting = true`; `defer { isExporting = false }` on all exits.
- Calls `engine.renderExport(stack:source:cubeResolver:)` for full-res CGImage.
- Reads source EXIF dictionaries and color space via `CGImageSourceCopyPropertiesAtIndex` from `imported.sourceData`.
- Dispatches `ExportService.encode(cgImage:sourceProperties:colorSpace:options:)` on `Task.detached(priority: .userInitiated)`.
- Returns encoded `Data` to caller.

### `saveExport(options:) async`
- Calls `export(options:)` then `PhotoSaver.save(encodedData:format:)`.
- Sets `successMessage = "Saved to Photos."` on success.
- Maps `PhotoSaver.Error.permissionDenied` to a human-readable `errorMessage`.

### `shareExport(options:) async`
- Calls `export(options:)` then sets `shareData` and `shareFormat`.
- ContentView observes these properties and presents `ShareSheetView`.
- Sets `errorMessage` on failure.

## New Observable State Fields

| Field | Type | Purpose |
|-------|------|---------|
| `isExporting` | `Bool` | Spinner / disable UI during export |
| `shareData` | `Data?` | Staged export bytes for share sheet |
| `shareFormat` | `ExportFormat?` | Format for share sheet UTI / file extension |

## Legacy Removal

`func saveImage() async` has been deleted in its entirety. The old path:
- Round-tripped through `UIImage(cgImage:)` — strips ICC profile (EXPORT-06 violation)
- Used `PHAssetChangeRequest.creationRequestForAsset(from: UIImage)` — re-encodes as JPEG regardless of user choice (EXPORT-03/04/05 violation)
- Requested Photos authorization inline rather than via `PhotoSaver`

No `UIImage` round-trip exists anywhere in the new export path.

## EXIF / Color Profile Preservation

`readSourceMetadata(from:)` uses `CGImageSourceCreateWithData` + `CGImageSourceCopyPropertiesAtIndex` to extract the raw property dictionary from source bytes. GPS dictionary is stripped by omission in `ExportService.encode`. Source CGColorSpace is passed through to `ExportService` which embeds it via `CGImageDestination`.

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check: PASSED

- EditorViewModel.swift: FOUND
- Commit 429d206: FOUND

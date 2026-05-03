---
phase: 05-export
plan: "04"
subsystem: export
tags: [share-sheet, uikit, uiviewcontrollerrepresentable, temp-file]
dependency_graph:
  requires: [05-01]
  provides: [ShareSheetView]
  affects: [05-06]
tech_stack:
  added: []
  patterns: [UIViewControllerRepresentable, UIActivityViewController, temp-file URL sharing]
key_files:
  created:
    - PhotoEditor/Export/ShareSheetView.swift
  modified: []
decisions:
  - "Capture tempURL as local let before constructing UIActivityViewController to satisfy Swift closure capture rules"
  - "UUID-suffixed filename prevents collisions across rapid back-to-back shares"
  - "File written with .atomic option; deletion deferred to completionWithItemsHandler so share extensions can read asynchronously"
metrics:
  duration: 3min
  completed: "2026-05-03"
  tasks_completed: 1
  files_changed: 1
---

# Phase 05 Plan 04: ShareSheetView Summary

ShareSheetView wraps UIActivityViewController via UIViewControllerRepresentable, writing export Data to a UUID-named temp file with the correct format extension before sharing, and deletes the file via completionWithItemsHandler on dismiss.

## What Was Built

`PhotoEditor/Export/ShareSheetView.swift` — a single `struct ShareSheetView: UIViewControllerRepresentable`.

### View Signature

```swift
struct ShareSheetView: UIViewControllerRepresentable {
    let data: Data
    let format: ExportFormat
    var onDismiss: (() -> Void)? = nil
}
```

### Temp-File Naming

Files are written to `FileManager.default.temporaryDirectory` with the pattern:

```
PhotoEditor-Export-<UUID>.<format.fileExtension>
```

For example: `PhotoEditor-Export-A1B2C3....jpg`

UUID suffix prevents collisions when the user shares multiple times in quick succession. The extension comes from `ExportFormat.fileExtension` (defined in 05-01): `jpg`, `heic`, or `png`.

### Cleanup Hook

The temp file is deleted inside `completionWithItemsHandler`:

```swift
avc.completionWithItemsHandler = { _, _, _, _ in
    if let tempURL { try? FileManager.default.removeItem(at: tempURL) }
    onDismiss?()
}
```

Deletion is deferred to the handler (not immediate after `makeUIViewController` returns) because some share extensions read the file asynchronously after the picker is displayed.

### Capture Fix

The plan noted a potential capture issue. The fix is to bind `let tempURL = Self.writeTempFile(...)` before constructing the `UIActivityViewController`, so the closure captures `tempURL` (the resolved `URL?` value) rather than requiring any `let` rebinding inside the handler body.

## Deviations from Plan

None — plan executed exactly as written (with the capture fix already described in the plan notes applied as specified).

## Self-Check: PASSED

- `PhotoEditor/Export/ShareSheetView.swift` — EXISTS
- Commit `944d969` — EXISTS
- Verification grep count: 5 >= 5 — PASSED
- `import Photos` absent — CONFIRMED

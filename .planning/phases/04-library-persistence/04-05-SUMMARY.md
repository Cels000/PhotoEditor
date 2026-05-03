---
phase: 04-library-persistence
plan: 05
subsystem: Library UI
tags: [swiftui, library, grid, photokit, swiftdata]
dependency_graph:
  requires: [04-01, 04-02]
  provides: [LibraryGridView, LibraryItemThumbnail]
  affects: [04-06]
tech_stack:
  added: []
  patterns: [LazyVGrid, contextMenu+alert destructive confirmation, PHAsset.fetchAssets in-memory check]
key_files:
  created:
    - PhotoEditor/Library/LibraryGridView.swift
    - PhotoEditor/Library/LibraryItemThumbnail.swift
  modified: []
decisions:
  - PHAsset.fetchAssets called synchronously inside .task(id:) — fast in-memory lookup, safe on main actor
  - store passed as let (not @Environment) to keep dependency graph explicit for plan 04-06
  - Source-unavailable items still trigger onOpen — EditorViewModel surfaces the error (plan 04-04 already handles this)
metrics:
  duration: ~1min
  completed: 2026-05-03T21:41:53Z
  tasks_completed: 2
  files_created: 2
---

# Phase 4 Plan 05: Library Grid UI Summary

LibraryGridView sheet with 3-column LazyVGrid + LibraryItemThumbnail cell showing PHAsset-deletion placeholder via in-memory PhotoKit check.

## What Was Built

### LibraryItemThumbnail (`PhotoEditor/Library/LibraryItemThumbnail.swift`)

Square 1:1 cell that:
- Renders `item.thumbnailData` JPEG via UIImage, scaledToFill.
- Falls back to `tertiarySystemBackground` when `thumbnailData` is nil.
- Runs `PHAsset.fetchAssets(withLocalIdentifiers:)` at task time to detect source deletion (LIB-05).
- Shows dim overlay + `exclamationmark.triangle.fill` + "Source unavailable" text when source is gone or `sourceAssetID` is nil.
- Square aspect ratio with RoundedRectangle(cornerRadius: 10) clip.

### LibraryGridView (`PhotoEditor/Library/LibraryGridView.swift`)

Sheet-presented view that:
- Wraps content in a `NavigationStack` with title "Library" and a "Done" toolbar button.
- Shows 3-column `LazyVGrid` (three `GridItem(.flexible(), spacing: 8)`) of `store.items`.
- Empty state: `photo.on.rectangle.angled` symbol + "No edits yet" + "Save an edit to see it here."
- Tap cell: calls `onOpen(item)` then dismisses sheet.
- Context menu "Delete" (destructive role): sets `pendingDelete` state.
- `.alert("Delete edit?", presenting: pendingDelete)` with Cancel + Delete (destructive); confirm calls `store.delete(item)` (LIB-03).
- Alert message clarifies only the library entry is removed, not the original photo.

## Constructor Signatures (for plan 04-06)

```swift
struct LibraryGridView: View {
    let store: LibraryStore          // passed explicitly, not via @Environment
    var onOpen: (LibraryItem) -> Void

    // Presented as: .sheet(isPresented: $showLibrary) {
    //     LibraryGridView(store: libraryStore) { item in
    //         viewModel.openLibraryItem(item)
    //     }
    // }
}

struct LibraryItemThumbnail: View {
    let item: LibraryItem
    // Used internally by LibraryGridView; can also be used standalone.
}
```

## onOpen Contract

- Called with the tapped `LibraryItem` before the sheet dismisses.
- Plan 04-06 maps this to `EditorViewModel.openLibraryItem(_:)`.
- Source-unavailable items still trigger `onOpen` — EditorViewModel (plan 04-04) handles the error state.

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check

Files exist:
- PhotoEditor/Library/LibraryItemThumbnail.swift — FOUND
- PhotoEditor/Library/LibraryGridView.swift — FOUND

Commits:
- 990ea91 feat(04-05): add LibraryItemThumbnail cell with PHAsset-availability check
- 1ac7da3 feat(04-05): add LibraryGridView with 3-column grid and delete confirmation

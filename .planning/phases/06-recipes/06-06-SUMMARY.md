---
phase: 06-recipes
plan: 06
subsystem: ui
tags: [swiftui, swiftdata, recipes, sheet, toolbar, onOpenURL, notification]

# Dependency graph
requires:
  - phase: 06-02
    provides: RecipeStore CRUD service
  - phase: 06-03
    provides: RecipeFileIO encode/decode, ExportedRecipe type
  - phase: 06-04
    provides: Info.plist UTI registration for .photorecipe
  - phase: 06-05
    provides: EditorViewModel.applyRecipe and saveCurrentAsRecipe methods
provides:
  - RecipeNamePromptView modal name entry sheet (Save Recipe and Rename flows)
  - RecipesSheetView full recipe management surface (apply, rename, share, delete, reorder)
  - ContentView toolbar Recipes button and Save as Recipe button
  - ContentView RecipeStore lazy init alongside LibraryStore
  - PhotoEditorApp .onOpenURL import handler for .photorecipe files
  - Notification.Name.recipeImported cross-component refresh trigger
affects: [07-polish]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Notification-based cross-component refresh (onOpenURL -> ContentView recipeStore.refresh())
    - sheet(item:) for Identifiable modal presentation (RecipeNamePromptView via renameTarget)
    - Security-scoped resource access guard for Files app URLs in onOpenURL

key-files:
  created:
    - PhotoEditor/Library/RecipeNamePromptView.swift
    - PhotoEditor/Library/RecipesSheetView.swift
  modified:
    - PhotoEditor/ContentView.swift
    - PhotoEditor/PhotoEditorApp.swift

key-decisions:
  - "RecipeItem: Identifiable extension in RecipesSheetView.swift so sheet(item:) works with renameTarget; @Model doesn't auto-conform to Identifiable"
  - "Notification.Name.recipeImported declared at file scope in PhotoEditorApp.swift; ContentView's separate .task subscribes to trigger recipeStore?.refresh()"
  - "ShareLink used for recipe sharing (not UIActivityViewController) — consistent with Phase 5 export pattern for SwiftUI-native share sheet"
  - "Save as Recipe button disabled when stack == .identity to match CONTEXT.md decision about non-identity stack requirement"

patterns-established:
  - "Cross-scene refresh via NotificationCenter: App-level handler posts notification, ContentView .task listens and triggers store refresh"
  - "Modal name entry reused for both create (Save Recipe) and edit (Rename) by parameterizing title + initialName"

requirements-completed: [RECIPE-01, RECIPE-02, RECIPE-03, RECIPE-04]

# Metrics
duration: 8min
completed: 2026-05-03
---

# Phase 06: Recipes Summary

**RecipesSheetView + ContentView toolbar wiring + .onOpenURL import handler expose the full Recipes feature to users: save, apply, rename, share, delete, reorder, and AirDrop/Files import of .photorecipe files**

## Performance

- **Duration:** 8 min
- **Started:** 2026-05-03T22:37:45Z
- **Completed:** 2026-05-03T22:45:00Z
- **Tasks:** 4
- **Files modified:** 4 (2 created, 2 modified)

## Accomplishments
- RecipeNamePromptView: compact modal (h=200) with auto-focused TextField, disabled Save on empty, shared by both Save and Rename flows
- RecipesSheetView: full recipe management — tap-to-apply, context menu (Rename/Share/Delete), EditMode reorder, ShareLink export, empty state
- ContentView: Recipes toolbar button (wand.and.stars) + Save as Recipe button (doc.badge.plus, disabled when stack=.identity), two new sheets, RecipeStore lazy init
- PhotoEditorApp: .onOpenURL handler decodes .photorecipe via RecipeFileIO, persists via transient RecipeStore, posts .recipeImported notification

## Task Commits

1. **Task 1: RecipeNamePromptView** - `8334a97` (feat)
2. **Task 2: RecipesSheetView** - `341cd3d` (feat)
3. **Task 3: ContentView wiring** - `830fd77` (feat)
4. **Task 4: PhotoEditorApp .onOpenURL** - `1702f23` (feat)

## Files Created/Modified
- `PhotoEditor/Library/RecipeNamePromptView.swift` - Modal name entry sheet for save and rename
- `PhotoEditor/Library/RecipesSheetView.swift` - Full recipe management UI surface
- `PhotoEditor/ContentView.swift` - Toolbar buttons, sheets, RecipeStore lazy init, .recipeImported listener
- `PhotoEditor/PhotoEditorApp.swift` - .onOpenURL handler, Notification.Name.recipeImported declaration

## Decisions Made
- Added `extension RecipeItem: Identifiable {}` in RecipesSheetView.swift; @Model macro provides PersistentModel but not Identifiable, which is required for `sheet(item:)` with renameTarget
- Used two separate `.task` closures in ContentView: first for lazy store init, second for notification subscription — cleaner than combining into one with for-await
- Notification.Name declared at PhotoEditorApp.swift file scope (not inside the struct) so ContentView can reference it without circular imports

## Deviations from Plan

None — plan executed exactly as written. The Identifiable extension note was already anticipated by the plan.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 6 (Recipes) is now fully complete end-to-end: model, persistence, file IO, UTI registration, ViewModel integration, and UI surface
- Phase 7 (Polish): .onOpenURL silent failure can be upgraded to a user-facing toast; recipe import success feedback is deferred per plan
- Real-device testing required for .photorecipe UTI routing (Phase 6 blocker documented in STATE.md)

---
*Phase: 06-recipes*
*Completed: 2026-05-03*

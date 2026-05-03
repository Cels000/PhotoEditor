# Phase 6: Recipes - Context

**Gathered:** 2026-05-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Capture an adjustment stack as a named, reusable Recipe. Apply, rename, reorder, delete, and share Recipes via `.photorecipe` file (Codable JSON wrapped in a custom UTI document type). Filter UUID resilience: a recipe referencing a missing filter ID applies all other adjustments and leaves the filter slot empty.

Specifically:
- Recipe model: id (UUID), name, createdAt, updatedAt, sortOrder, AdjustmentStack snapshot, optional thumbnailData
- RecipeStore: SwiftData model + service (mirrors LibraryStore pattern)
- Save flow: "Save as Recipe" from edit panel → name prompt → store
- Apply flow: Recipes drawer → tap → replace current stack (with undo entry)
- Rename / reorder / delete flows
- Share: write `.photorecipe` (Codable JSON) to Files via UIActivityViewController
- Import: open-in handler accepts `.photorecipe` files → adds to library
- Recipe-applies-with-missing-filter: graceful degradation (other adjustments still apply, filter slot blank)

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion

- **Persistence:** SwiftData @Model `RecipeItem` (separate from `LibraryItem`). Same `VersionedSchema` infra (extend `LibrarySchemaV1` to include both, or create `AppSchemaV1` with both — recommendation: `AppSchemaV1` so library + recipes share schema versioning).
- **Recipe model fields:**
  ```
  @Model final class RecipeItem {
      var id: UUID
      var name: String
      var createdAt: Date
      var updatedAt: Date
      var sortOrder: Int
      var stackData: Data       // Codable JSON of AdjustmentStack
      var thumbnailData: Data?  // 200x200 representative preview (optional)
      var schemaVersion: Int
  }
  ```
- **RecipeStore:** `@Observable @MainActor`. CRUD + reorder. Mirrors LibraryStore.
- **Recipes UI:** "Recipes" panel as a 7th tab in `EditorPanelTab` (or separate sheet — pick: separate sheet, accessed from a top toolbar button, since it's a global library not a per-image panel). Sheet shows grid: thumbnail + name. Tap → apply. Long-press → menu: Rename / Share / Delete / Reorder mode.
- **Apply behavior:** Replaces current stack — but the Filter UUID may not exist (e.g., user deleted a filter, recipe came from elsewhere). Apply policy: clear `stack.filter.id = nil` when ID is unresolvable; preserve all other fields. Create one undo entry for the entire apply.
- **Reorder:** EditMode + `.onMove`. Reflects in `sortOrder`.
- **Share format:** `.photorecipe` file = JSON Codable of a small struct:
  ```
  struct ExportedRecipe: Codable {
      var schemaVersion: Int  // recipe doc schema, not stack schema
      var name: String
      var stack: AdjustmentStack
      var thumbnailJPEGBase64: String?
  }
  ```
  UTI declared in Info.plist: `com.photoeditor.recipe` conforms to `public.json` and `public.data`. File extension: `.photorecipe`.
- **Import:** App registers `CFBundleDocumentTypes` for `.photorecipe`. `App.scenePhase` + `.onOpenURL` reads the file → decodes → adds to RecipeStore. Show success toast.
- **Save-as-Recipe entry:** Top toolbar button "Save Recipe" (icon: `doc.badge.plus`) — only enabled when there's a non-identity stack. Prompts for a name (default = first filter name + "..." or "Untitled Look").
- **Thumbnail for recipe:** Optional. If user has a current photo loaded when saving, use Phase 4's `ThumbnailGenerator.makeThumbnail` at 200x200. If no photo, recipe ships without thumbnail (cell shows abstract gradient).

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets

- `AdjustmentStack` Codable (Phase 1)
- `LibrarySchemaV1` / `LibraryMigrationPlan` (Phase 4) — extend or co-locate
- `ThumbnailGenerator.makeThumbnail` (Phase 4)
- `LibraryStore` pattern (Phase 4)
- `UndoStack` (Phase 3)
- `ShareSheetView` (Phase 5) — usable for sharing exported `.photorecipe` files
- `EditorViewModel.beginInteractiveEdit / endInteractiveEdit` (Phase 3) — wrap the apply

### Patterns

- `@Model` + `VersionedSchema`
- `@Observable @MainActor` services
- Sheet-based UI

### Integration Points

- `ContentView` — add Recipes toolbar button + sheet
- `EditorViewModel` — `applyRecipe(_:)`, `saveCurrentAsRecipe(name:)` methods
- `PhotoEditorApp` — register `.onOpenURL` for `.photorecipe` import
- Info.plist — `CFBundleDocumentTypes` + `UTExportedTypeDeclarations`

</code_context>

<specifics>
## Specific Ideas

- Default Recipes pre-shipped: 3-5 starter "looks" derived from the BuiltInLUTs + suggested adjustments. Optional. Skip for v1 if it adds complexity — recipes are user-created.
- Recipe sharing without thumbnail still works (show gradient cell).
- The "missing filter ID" graceful degradation deserves a unit test in `PhotoEditorTests/`.

</specifics>

<deferred>
## Deferred Ideas

- Recipe folders / categories — v2
- Cloud-shared recipe gallery — v2 (anti-feature for v1 — no backend)
- Pre-shipped starter recipes — defer
- Multi-photo batch apply — v2 (BATCH-01)

</deferred>

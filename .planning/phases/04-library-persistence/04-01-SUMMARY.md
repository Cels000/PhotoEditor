---
phase: 04-library-persistence
plan: "01"
subsystem: persistence
tags: [swiftdata, library, model, versioned-schema, json-blob]
dependency_graph:
  requires: [PhotoEditor/Editor/AdjustmentStack.swift]
  provides: [PhotoEditor/Library/LibraryItem.swift, PhotoEditor/Library/LibrarySchema.swift]
  affects: [04-06-PLAN.md (ModelContainer init), 04-02-PLAN.md (LibraryStore service)]
tech_stack:
  added: [SwiftData]
  patterns: [VersionedSchema from v1, JSON blob persistence, computed Codable accessor]
key_files:
  created:
    - PhotoEditor/Library/LibraryItem.swift
    - PhotoEditor/Library/LibrarySchema.swift
  modified: []
decisions:
  - "JSON blob (stackData: Data) over normalized columns — field-additive AdjustmentStack changes decode forward-compat via Codable defaults"
  - "sourceAssetID is Optional<String> to represent PHAsset-deleted state without losing library item"
  - "VersionedSchema scaffold from v1 — per PITFALLS #12 retrofitting after data ships is destructive"
  - "Computed adjustmentStack accessor falls back to .identity on decode failure — corrupt blob cannot crash the library"
metrics:
  duration: 1min
  completed: 2026-05-03
  tasks_completed: 2
  files_created: 2
---

# Phase 4 Plan 01: LibraryItem SwiftData Model + VersionedSchema Scaffold Summary

**One-liner:** SwiftData @Model for library persistence with JSON-blob AdjustmentStack round-trip and VersionedSchema from v1 for non-destructive future migrations.

## What Was Built

Two new Swift files in `PhotoEditor/Library/`:

**LibraryItem.swift** — `@Model final class` with seven storage fields:
- `id: UUID` (`@Attribute(.unique)`) — stable identity across relaunches
- `createdAt: Date`, `updatedAt: Date` — timestamps; updatedAt updated by the computed setter
- `sourceAssetID: String?` — PHAsset localIdentifier, Optional so a deleted-source state is representable without losing the library item
- `stackData: Data` — JSON-encoded AdjustmentStack blob; all edit state lives here, not in normalized columns
- `thumbnailData: Data?` — 400x400 JPEG, nil until generated
- `schemaVersion: Int` — mirrors AdjustmentStack.schemaVersion at save time for migration guards

Computed `adjustmentStack` accessor in an extension transparently encodes/decodes `stackData` via `JSONEncoder`/`JSONDecoder`. Decode failure returns `AdjustmentStack.identity` — defensive against corrupt blobs without crashing the library.

**LibrarySchema.swift** — `LibrarySchemaV1: VersionedSchema` (version 1.0.0) with `LibraryItem.self` registered in `models`. `LibraryMigrationPlan: SchemaMigrationPlan` with `stages: []` for v1. Comments document exact pattern for adding LibrarySchemaV2 when a future migration is needed.

## Schema Versioning Convention (for downstream plans)

Plan 04-06 (ModelContainer init) should construct the container as:
```swift
let schema = Schema(versionedSchema: LibrarySchemaV1.self)
let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
let container = try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self, configurations: config)
```

When a schema change ships: add `LibrarySchemaV2: VersionedSchema`, append to `LibraryMigrationPlan.schemas`, add a `.lightweight(...)` or `.custom(...)` stage to `LibraryMigrationPlan.stages`.

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check

- [x] `PhotoEditor/Library/LibraryItem.swift` exists
- [x] `PhotoEditor/Library/LibrarySchema.swift` exists
- [x] Commits 17adbe5, 79f915c exist
- [x] Exactly one `@Model` class in `PhotoEditor/Library/`
- [x] No `SwiftUI` import in either file
- [x] `adjustmentStack` accessor uses `JSONDecoder().decode(AdjustmentStack.self` and `JSONEncoder().encode`

## Self-Check: PASSED

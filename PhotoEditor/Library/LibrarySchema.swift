// LibrarySchema.swift
// PhotoEditor
//
// VersionedSchema scaffold for the library persistence layer.
// Per PITFALLS #12: VersionedSchema MUST be in place from v1 — retrofitting after data
// ships is destructive. Even though v1 has only one schema version, the plan exists so
// future migrations slot in cleanly without restructuring app init.
//
// v1 covers both LibraryItem (Phase 4) and RecipeItem (Phase 6, RECIPE-01).
// Adding a model to an existing VersionedSchema is the lightweight, non-destructive path —
// renaming to AppSchemaV1 would change SwiftData's persistent type identifier and discard
// existing user library data on upgrade.
//
// Usage (Plan 04-06 / 06-01):
//   Schema(versionedSchema: LibrarySchemaV1.self)
//   migrationPlan: LibraryMigrationPlan.self

import Foundation
import SwiftData

/// v1 schema — the only version that has shipped.
/// Future schema changes: add LibrarySchemaV2 enum, register in versionedSchemas,
/// and add a MigrationStage to LibraryMigrationPlan.stages.
enum LibrarySchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [LibraryItem.self, RecipeItem.self]
    }
}

/// Migration plan — empty stages array for v1, but the plan exists so future
/// migrations slot in cleanly without restructuring app init.
enum LibraryMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [LibrarySchemaV1.self]
    }

    static var stages: [MigrationStage] {
        // No stages until LibrarySchemaV2 is introduced. When it is:
        //   .lightweight(fromVersion: LibrarySchemaV1.self, toVersion: LibrarySchemaV2.self)
        //   or .custom(...) for renames/removals.
        []
    }
}

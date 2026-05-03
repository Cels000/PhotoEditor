// RecipeItem.swift
// PhotoEditor
//
// SwiftData @Model representing a saved Recipe — a named, reusable adjustment stack.
// RECIPE-01: Persistence shape for "save current stack as named Recipe".
// Pattern matches LibraryItem.swift; stackData is a JSON-encoded AdjustmentStack
// so future field-additive changes decode forward-compat (PITFALLS #12).

import Foundation
import SwiftData

@Model
final class RecipeItem {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var sortOrder: Int
    var stackData: Data            // JSON-encoded AdjustmentStack
    var thumbnailData: Data?       // optional 200x200 JPEG (~10 KB)
    var schemaVersion: Int         // mirrors AdjustmentStack.schemaVersion at save time

    init(id: UUID = UUID(),
         name: String = "Untitled Look",
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         sortOrder: Int = 0,
         stackData: Data = Data(),
         thumbnailData: Data? = nil,
         schemaVersion: Int = 1) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortOrder = sortOrder
        self.stackData = stackData
        self.thumbnailData = thumbnailData
        self.schemaVersion = schemaVersion
    }
}

extension RecipeItem {
    /// Decoded view of stackData. Returns .identity on decode failure
    /// (defensive — corrupt blob should not crash recipes UI).
    var adjustmentStack: AdjustmentStack {
        get {
            (try? JSONDecoder().decode(AdjustmentStack.self, from: stackData)) ?? .identity
        }
        set {
            stackData = (try? JSONEncoder().encode(newValue)) ?? Data()
            schemaVersion = newValue.schemaVersion
            updatedAt = Date()
        }
    }
}

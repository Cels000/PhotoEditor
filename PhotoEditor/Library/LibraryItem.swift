// LibraryItem.swift
// PhotoEditor
//
// SwiftData @Model representing a single persisted edit in the library.
// LIB-04: Establishes persistence shape before any service or UI code consumes it.
// All non-id fields use defaults so future additions decode forward-compat (PITFALLS #12).

import Foundation
import SwiftData

@Model
final class LibraryItem {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var sourceAssetID: String?     // PHAsset localIdentifier; nil if PHAsset gone or never linked
    var stackData: Data            // JSON-encoded AdjustmentStack
    var thumbnailData: Data?       // 400x400 JPEG (~30 KB), nil while generating
    var schemaVersion: Int         // mirrors AdjustmentStack.schemaVersion at save time

    init(id: UUID = UUID(),
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         sourceAssetID: String? = nil,
         stackData: Data = Data(),
         thumbnailData: Data? = nil,
         schemaVersion: Int = 1) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sourceAssetID = sourceAssetID
        self.stackData = stackData
        self.thumbnailData = thumbnailData
        self.schemaVersion = schemaVersion
    }
}

extension LibraryItem {
    /// Decoded view of stackData. Returns .identity on decode failure
    /// (defensive — corrupt blob should not crash the library).
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

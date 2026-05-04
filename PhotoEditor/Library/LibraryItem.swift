// LibraryItem.swift
// PhotoEditor
//
// SwiftData @Model representing a single persisted edit in the library.
// LIB-04: Establishes persistence shape before any service or UI code consumes it.
// All non-id fields use defaults so future additions decode forward-compat (PITFALLS #12).
//
// Schema v2 (Task 7): adds `documentData: Data?` (JSON-encoded EditDocument).
// Legacy v1 items have `documentData == nil` and continue to read via the
// stackData fallback in editDocument's getter, transparently lifting to v2.

import Foundation
import SwiftData

@Model
final class LibraryItem {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var sourceAssetID: String?     // PHAsset localIdentifier; nil if PHAsset gone or never linked
    var stackData: Data            // legacy v1 blob; preserved for back-compat
    var documentData: Data?        // v2 blob; nil for items saved before mask feature
    var thumbnailData: Data?       // 400x400 JPEG (~30 KB), nil while generating
    var schemaVersion: Int         // 1 for legacy items, 2 for new writes

    init(id: UUID = UUID(),
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         sourceAssetID: String? = nil,
         stackData: Data = Data(),
         documentData: Data? = nil,
         thumbnailData: Data? = nil,
         schemaVersion: Int = 2) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sourceAssetID = sourceAssetID
        self.stackData = stackData
        self.documentData = documentData
        self.thumbnailData = thumbnailData
        self.schemaVersion = schemaVersion
    }
}

extension LibraryItem {
    /// v2 accessor. Reads `documentData` if present, otherwise falls back to
    /// `stackData` and lifts a legacy v1 stack into a v2 EditDocument.
    var editDocument: EditDocument {
        get {
            if let documentData,
               let decoded = try? JSONDecoder().decode(EditDocument.self, from: documentData) {
                return decoded
            }
            if !stackData.isEmpty,
               let migrated = try? EditDocument.migrating(fromLegacyStackData: stackData) {
                return migrated
            }
            return .identity
        }
        set {
            documentData = (try? JSONEncoder().encode(newValue))
            // Keep stackData populated with subjectStack so older code paths
            // (and the legacy adjustmentStack accessor below) still see a
            // sensible value if they bypass editDocument.
            stackData = (try? JSONEncoder().encode(newValue.subjectStack)) ?? Data()
            schemaVersion = newValue.schemaVersion
            updatedAt = Date()
        }
    }

    /// Legacy v1 accessor — returns the subject stack of the document.
    /// Kept for callers that haven't migrated to editDocument (recipes, etc.).
    var adjustmentStack: AdjustmentStack {
        get { editDocument.subjectStack }
        set {
            var doc = editDocument
            doc.subjectStack = newValue
            doc.backgroundStack = newValue
            editDocument = doc
        }
    }
}

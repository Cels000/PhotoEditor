// LibraryStore.swift
// PhotoEditor
//
// Single owner of the SwiftData ModelContext for LibraryItem.
// All CRUD operations on library items go through this service.
// Views observe `items` via @Observable — no @Query in this layer.
// LIB-01, LIB-03, LIB-04

import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class LibraryStore {
    private(set) var items: [LibraryItem] = []
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
        refresh()
    }

    /// Fetch newest-first. Called after every mutating op so `items` stays current
    /// without relying on @Query (we deliberately keep this layer view-agnostic).
    func refresh() {
        var descriptor = FetchDescriptor<LibraryItem>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = nil
        do {
            self.items = try context.fetch(descriptor)
        } catch {
            self.items = []
        }
    }

    /// Insert a brand-new library item. Used by EditorViewModel.saveToLibrary().
    @discardableResult
    func save(stack: AdjustmentStack,
              sourceAssetID: String?,
              thumbnail: Data?) -> LibraryItem {
        let now = Date()
        let item = LibraryItem(
            id: UUID(),
            createdAt: now,
            updatedAt: now,
            sourceAssetID: sourceAssetID,
            stackData: (try? JSONEncoder().encode(stack)) ?? Data(),
            thumbnailData: thumbnail,
            schemaVersion: stack.schemaVersion
        )
        context.insert(item)
        try? context.save()
        refresh()
        return item
    }

    /// Camera-capture entry point. Inserts a fresh LibraryItem whose stack
    /// reflects the recipe selected in the viewfinder at shutter time. The
    /// thumbnail is the cooked preview frame (JPEG bytes) — passing it in
    /// avoids a re-render via ThumbnailGenerator on first display.
    @discardableResult
    func importFromCamera(assetID: String,
                          stack: AdjustmentStack,
                          thumbnail: Data?) -> LibraryItem {
        save(stack: stack, sourceAssetID: assetID, thumbnail: thumbnail)
    }

    /// Update an existing item's stack and (optionally) thumbnail.
    /// Used by EditorViewModel.saveToLibrary() when re-saving an opened item.
    func update(_ item: LibraryItem,
                stack: AdjustmentStack,
                thumbnail: Data?) {
        item.adjustmentStack = stack    // updates stackData, schemaVersion, updatedAt
        if let thumbnail { item.thumbnailData = thumbnail }
        try? context.save()
        refresh()
    }

    /// Delete an item. Thumbnail data is stored inline on the item, so deleting
    /// the model row also removes the thumbnail (LIB-03).
    func delete(_ item: LibraryItem) {
        context.delete(item)
        try? context.save()
        refresh()
    }
}

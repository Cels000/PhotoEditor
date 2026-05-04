// RecipeStore.swift
// PhotoEditor
//
// Single owner of RecipeItem persistence. Mirrors LibraryStore.swift exactly.
// Views observe `items` via @Observable — no @Query in this layer.
// RECIPE-01 (save), RECIPE-02 (fetch for apply), RECIPE-03 (rename/reorder/delete).

import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class RecipeStore {
    private(set) var items: [RecipeItem] = []
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
        refresh()
    }

    /// Fetch all recipes ordered by sortOrder ascending.
    /// Called after every mutating op so `items` stays current.
    func refresh() {
        var descriptor = FetchDescriptor<RecipeItem>(
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )
        descriptor.fetchLimit = nil
        do {
            self.items = try context.fetch(descriptor)
        } catch {
            self.items = []
        }
    }

    /// Insert a new recipe. sortOrder is computed as (max existing) + 1 so new
    /// recipes always land at the end of the list.
    @discardableResult
    func save(name: String,
              stack: AdjustmentStack,
              thumbnail: Data?) -> RecipeItem {
        let now = Date()
        let nextOrder = (items.map { $0.sortOrder }.max() ?? -1) + 1
        let item = RecipeItem(
            id: UUID(),
            name: name,
            createdAt: now,
            updatedAt: now,
            sortOrder: nextOrder,
            stackData: (try? JSONEncoder().encode(stack)) ?? Data(),
            thumbnailData: thumbnail,
            schemaVersion: stack.schemaVersion
        )
        context.insert(item)
        do {
            try context.save()
        } catch {
            NSLog("PhotoEditor: RecipeStore.save failed: \(error)")
        }
        refresh()
        return item
    }

    /// Rename a recipe. Trims whitespace; ignores empty names.
    func rename(_ item: RecipeItem, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        item.name = trimmed
        item.updatedAt = Date()
        try? context.save()
        refresh()
    }

    /// Reorder recipes — caller passes the new array order. We rewrite
    /// sortOrder on every item to match the array index, then refresh.
    func reorder(_ newOrder: [RecipeItem]) {
        for (index, item) in newOrder.enumerated() {
            item.sortOrder = index
        }
        try? context.save()
        refresh()
    }

    /// Delete a recipe. Thumbnail data is inline so deleting the row also
    /// frees the thumbnail.
    func delete(_ item: RecipeItem) {
        context.delete(item)
        try? context.save()
        refresh()
    }
}

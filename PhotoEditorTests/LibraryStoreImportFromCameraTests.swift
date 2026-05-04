// Coverage for LibraryStore.importFromCamera — the camera-capture entry point.
// A captured photo arrives as (PHAsset.localIdentifier, full recipe stack,
// JPEG thumbnail bytes). The store must persist all three on a fresh
// LibraryItem and surface it via `items` at the front of the list.

import XCTest
import SwiftData
@testable import PhotoEditor

@MainActor
final class LibraryStoreImportFromCameraTests: XCTestCase {

    private func makeStore() throws -> LibraryStore {
        let schema = Schema([LibraryItem.self, RecipeItem.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        return LibraryStore(context: ModelContext(container))
    }

    func testImportFromCameraPersistsAssetIDAndStack() throws {
        let store = try makeStore()

        var stack = AdjustmentStack.identity
        stack.filter = FilterSelection(filterID: "cube.portra-400", strength: 1.0)
        stack.grain.intensity = 0.4

        let thumb = Data([0xFF, 0xD8, 0xFF, 0xD9])  // dummy JPEG marker bytes
        let item = store.importFromCamera(
            assetID: "ASSET-ID-123",
            stack: stack,
            thumbnail: thumb
        )

        XCTAssertEqual(item.sourceAssetID, "ASSET-ID-123")
        XCTAssertEqual(item.thumbnailData, thumb)
        XCTAssertEqual(item.adjustmentStack.filter?.filterID, "cube.portra-400")
        XCTAssertEqual(item.adjustmentStack.grain.intensity, 0.4, accuracy: 1e-9)
        XCTAssertEqual(store.items.first?.id, item.id, "newest-first ordering")
    }

    func testImportFromCameraWithIdentityStack() throws {
        let store = try makeStore()
        let item = store.importFromCamera(
            assetID: "ORIGINAL-ASSET",
            stack: .identity,
            thumbnail: nil
        )
        XCTAssertNil(item.adjustmentStack.filter)
        XCTAssertNil(item.thumbnailData)
        XCTAssertEqual(item.sourceAssetID, "ORIGINAL-ASSET")
    }
}

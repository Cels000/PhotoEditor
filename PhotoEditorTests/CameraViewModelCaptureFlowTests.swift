import XCTest
import SwiftData
@testable import PhotoEditor

@MainActor
final class CameraViewModelCaptureFlowTests: XCTestCase {

    private func makeStores() throws -> (LibraryStore, RecipeStore) {
        let schema = Schema([LibraryItem.self, RecipeItem.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        let ctx = ModelContext(container)
        return (LibraryStore(context: ctx), RecipeStore(context: ctx))
    }

    func testCaptureWithRecipeSlotCooksAndPersistsIdentity() async throws {
        let (libraryStore, recipeStore) = try makeStores()

        var stack = AdjustmentStack.identity
        stack.filter = FilterSelection(filterID: "cube.portra-400", strength: 1.0)
        stack.grain.intensity = 0.5
        let recipe = recipeStore.save(name: "Portra 400", stack: stack, thumbnail: nil)

        // Passthrough cooker so the test doesn't require a real HEIC payload.
        // Camera flow now cooks the HEIC in-process and stores `.identity` on
        // the library row (the look is baked into the pixels).
        let vm = CameraViewModel(
            libraryStore: libraryStore,
            recipeStore: recipeStore,
            cubeResolver: { _ in nil },
            photosWriter: StubPhotosWriter(returning: "ASSET-A"),
            heicProvider: { Data([0x00]) },
            heicCooker: { data, _ in data }
        )
        vm.selectSlot(.recipe(recipe))

        try await vm.capture()

        XCTAssertEqual(libraryStore.items.count, 1)
        let item = libraryStore.items[0]
        XCTAssertEqual(item.sourceAssetID, "ASSET-A")
        XCTAssertNil(item.adjustmentStack.filter)
        XCTAssertEqual(item.adjustmentStack.grain.intensity, 0, accuracy: 1e-9)
    }

    func testCaptureWithOriginalSlotPersistsIdentityStack() async throws {
        let (libraryStore, recipeStore) = try makeStores()
        let vm = CameraViewModel(
            libraryStore: libraryStore,
            recipeStore: recipeStore,
            cubeResolver: { _ in nil },
            photosWriter: StubPhotosWriter(returning: "ASSET-B"),
            heicProvider: { Data([0x00]) }
        )
        vm.selectSlot(.original)

        try await vm.capture()

        XCTAssertEqual(libraryStore.items.count, 1)
        let item = libraryStore.items[0]
        XCTAssertNil(item.adjustmentStack.filter)
    }

    func testSelectSlotPersistsLastUsedID() throws {
        let r = RecipeItem(name: "x")
        let suite = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let (libraryStore, recipeStore) = try makeStores()
        let vm = CameraViewModel(
            libraryStore: libraryStore,
            recipeStore: recipeStore,
            cubeResolver: { _ in nil },
            photosWriter: StubPhotosWriter(returning: ""),
            heicProvider: { Data() },
            userDefaults: defaults
        )
        vm.selectSlot(.recipe(r))
        XCTAssertEqual(defaults.string(forKey: CameraViewModel.lastSlotKey),
                       r.id.uuidString)

        vm.selectSlot(.original)
        XCTAssertEqual(defaults.string(forKey: CameraViewModel.lastSlotKey),
                       CameraSlot.originalID)
    }
}

private struct StubPhotosWriter: PhotosWriter {
    let returning: String
    func writeHEIC(_ data: Data) async throws -> String { returning }
}

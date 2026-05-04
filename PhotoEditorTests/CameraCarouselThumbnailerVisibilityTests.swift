import XCTest
@testable import PhotoEditor

@MainActor
final class CameraCarouselThumbnailerVisibilityTests: XCTestCase {

    func testVisibleSlotIDsFiltersOutOffscreen() {
        let r1 = RecipeItem(name: "A")
        let r2 = RecipeItem(name: "B")
        let r3 = RecipeItem(name: "C")
        let slots: [CameraSlot] = [.original, .recipe(r1), .recipe(r2), .recipe(r3)]

        let thumbnailer = CameraCarouselThumbnailer(
            renderer: nil,
            cubeResolver: { _ in nil }
        )
        thumbnailer.setVisibleSlotIDs([CameraSlot.originalID, r2.id.uuidString])
        let visible = thumbnailer.slotsToRender(from: slots)
        XCTAssertEqual(visible.map { $0.id },
                       [CameraSlot.originalID, r2.id.uuidString])
    }

    func testEmptyVisibilityRendersNothing() {
        let r1 = RecipeItem(name: "A")
        let thumbnailer = CameraCarouselThumbnailer(
            renderer: nil,
            cubeResolver: { _ in nil }
        )
        thumbnailer.setVisibleSlotIDs([])
        let visible = thumbnailer.slotsToRender(from: [.original, .recipe(r1)])
        XCTAssertTrue(visible.isEmpty)
    }
}

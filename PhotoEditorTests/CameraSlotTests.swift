import XCTest
import SwiftData
@testable import PhotoEditor

@MainActor
final class CameraSlotTests: XCTestCase {

    func testOriginalSlotIsIdentityStack() {
        let slot = CameraSlot.original
        XCTAssertEqual(slot.id, "__original__")
        XCTAssertEqual(slot.displayName, "ORIGINAL")
        XCTAssertNil(slot.stack.filter)
        XCTAssertEqual(slot.filterSelection, nil)
    }

    func testRecipeSlotExposesRecipeStackAndFilter() {
        var stack = AdjustmentStack.identity
        stack.filter = FilterSelection(filterID: "cube.portra-400", strength: 0.85)
        stack.grain.intensity = 0.3

        let recipe = RecipeItem(name: "Portra 400")
        recipe.adjustmentStack = stack

        let slot = CameraSlot.recipe(recipe)
        XCTAssertEqual(slot.id, recipe.id.uuidString)
        XCTAssertEqual(slot.displayName, "Portra 400")
        XCTAssertEqual(slot.stack.filter?.filterID, "cube.portra-400")
        XCTAssertEqual(slot.filterSelection?.filterID, "cube.portra-400")
        XCTAssertEqual(slot.filterSelection?.strength, 0.85, accuracy: 1e-9)
    }

    func testBuildSlotsPrependsOriginal() {
        let r1 = RecipeItem(name: "Portra 400")
        let r2 = RecipeItem(name: "Tri-X 400")
        let slots = CameraSlot.build(from: [r1, r2])
        XCTAssertEqual(slots.count, 3)
        XCTAssertEqual(slots[0].id, "__original__")
        XCTAssertEqual(slots[1].displayName, "Portra 400")
        XCTAssertEqual(slots[2].displayName, "Tri-X 400")
    }
}

// RecipeApplyTests.swift
// Coverage for the apply-recipe code path with focus on the missing-filter
// degradation case (RECIPE-05). Other adjustments must survive even when the
// referenced filter UUID has been removed from FilterLibrary.

import XCTest
@testable import PhotoEditor

@MainActor
final class RecipeApplyTests: XCTestCase {

    /// RECIPE-05: a recipe referencing an unknown filter ID applies all other
    /// adjustments and leaves the filter slot blank — no crash, no thrown error.
    func testApplyWithMissingFilterClearsFilterSlot() {
        let library = FilterLibrary()  // built-in catalog only; unknown IDs return nil
        let vm = EditorViewModel(filterLibrary: library)

        // Build a recipe stack with a definitely-missing filter UUID + non-default
        // adjustments that MUST survive the degradation.
        var recipeStack = AdjustmentStack.identity
        recipeStack.filter = FilterSelection(filterID: "cube.this-filter-does-not-exist", strength: 0.8)
        recipeStack.light.exposure = 0.4
        recipeStack.color.saturation = -0.2
        recipeStack.hsl.red.hue = 0.15
        recipeStack.grain.intensity = 0.3

        let recipe = RecipeItem(name: "Broken-Filter Recipe")
        recipe.adjustmentStack = recipeStack

        // Apply
        vm.applyRecipe(recipe)

        // Filter slot cleared
        XCTAssertNil(vm.stack.filter, "Missing filter ID must clear the filter slot")

        // Every other adjustment preserved
        XCTAssertEqual(vm.stack.light.exposure, 0.4, accuracy: 1e-9)
        XCTAssertEqual(vm.stack.color.saturation, -0.2, accuracy: 1e-9)
        XCTAssertEqual(vm.stack.hsl.red.hue, 0.15, accuracy: 1e-9)
        XCTAssertEqual(vm.stack.grain.intensity, 0.3, accuracy: 1e-9)
    }

    /// Recipe with no filter applies cleanly (control case — no degradation needed).
    func testApplyWithNilFilterPreservesNilFilter() {
        let vm = EditorViewModel(filterLibrary: FilterLibrary())

        var recipeStack = AdjustmentStack.identity
        recipeStack.filter = nil
        recipeStack.light.contrast = 0.5

        let recipe = RecipeItem(name: "No Filter Recipe")
        recipe.adjustmentStack = recipeStack

        vm.applyRecipe(recipe)

        XCTAssertNil(vm.stack.filter)
        XCTAssertEqual(vm.stack.light.contrast, 0.5, accuracy: 1e-9)
    }

    /// Recipe with a filter ID that DOES resolve preserves filter selection + strength.
    func testApplyWithKnownFilterPreservesFilter() {
        let library = FilterLibrary()
        // Identity is always present in BuiltInLUTs (per Phase 2 STATE.md decisions).
        let knownID = BuiltInLUTs.ID.identity

        let vm = EditorViewModel(filterLibrary: library)

        var recipeStack = AdjustmentStack.identity
        recipeStack.filter = FilterSelection(filterID: knownID, strength: 0.5)

        let recipe = RecipeItem(name: "Identity Recipe")
        recipe.adjustmentStack = recipeStack

        vm.applyRecipe(recipe)

        XCTAssertEqual(vm.stack.filter?.filterID, knownID)
        XCTAssertEqual(vm.stack.filter?.strength ?? 0, 0.5, accuracy: 1e-9)
    }

    /// Single apply produces exactly one undo entry — undoing returns to pre-apply state.
    func testApplyCreatesSingleUndoEntry() {
        let vm = EditorViewModel(filterLibrary: FilterLibrary())
        // Pre-apply state is .identity (seeded in init).
        XCTAssertEqual(vm.stack, .identity)

        var recipeStack = AdjustmentStack.identity
        recipeStack.light.exposure = 0.6
        let recipe = RecipeItem(name: "Test")
        recipe.adjustmentStack = recipeStack

        vm.applyRecipe(recipe)
        XCTAssertEqual(vm.stack.light.exposure, 0.6, accuracy: 1e-9)

        // Single undo should restore identity (one apply = one undo entry)
        vm.undo()
        XCTAssertEqual(vm.stack, .identity, "applyRecipe must create exactly one undo entry")
    }
}

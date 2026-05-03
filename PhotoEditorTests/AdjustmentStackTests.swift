import XCTest
@testable import PhotoEditor

final class AdjustmentStackTests: XCTestCase {
    func testCodableRoundTrip_identity_preservesEquality() throws {
        let original = AdjustmentStack.identity
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AdjustmentStack.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testSchemaVersion_default_isOne() {
        XCTAssertEqual(AdjustmentStack.identity.schemaVersion, 1)
    }

    func testCodableRoundTrip_mutated_preservesValues() throws {
        var stack = AdjustmentStack.identity
        stack.light.exposure = 0.5
        stack.color.saturation = -0.3
        stack.filter = FilterSelection(filterID: "test_lut", strength: 0.75)
        let data = try JSONEncoder().encode(stack)
        let decoded = try JSONDecoder().decode(AdjustmentStack.self, from: data)
        XCTAssertEqual(stack, decoded)
        XCTAssertEqual(decoded.light.exposure, 0.5)
        XCTAssertEqual(decoded.color.saturation, -0.3)
        XCTAssertEqual(decoded.filter?.filterID, "test_lut")
    }
}

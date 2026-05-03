// ExportedRecipeTests.swift
// Round-trip and edge-case tests for the .photorecipe doc format.
// RECIPE-04.

import XCTest
@testable import PhotoEditor

final class ExportedRecipeTests: XCTestCase {

    func testRoundTrip() throws {
        var stack = AdjustmentStack.identity
        stack.filter = FilterSelection(filterID: "cube.kodachrome64", strength: 0.7)
        stack.light.exposure = 0.5
        stack.color.saturation = -0.3
        stack.hsl.red.hue = 0.25

        let original = ExportedRecipe(
            schemaVersion: 1,
            name: "Test Look",
            stack: stack,
            thumbnailJPEGBase64: nil
        )

        let data = try RecipeFileIO.encode(original)
        let decoded = try RecipeFileIO.decode(data)

        XCTAssertEqual(decoded.name, "Test Look")
        XCTAssertEqual(decoded.stack, stack)
        XCTAssertEqual(decoded.schemaVersion, 1)
    }

    func testWriteReadTempFile() throws {
        var stack = AdjustmentStack.identity
        stack.light.contrast = 0.4
        let original = ExportedRecipe(name: "Disk Roundtrip", stack: stack)

        let url = try RecipeFileIO.writeTempFile(original)
        XCTAssertEqual(url.pathExtension, "photorecipe")

        let decoded = try RecipeFileIO.read(from: url)
        XCTAssertEqual(decoded.stack, stack)
        XCTAssertEqual(decoded.name, "Disk Roundtrip")

        try? FileManager.default.removeItem(at: url)
    }

    func testThumbnailBase64Roundtrip() throws {
        let doc = ExportedRecipe(
            name: "Thumb",
            stack: .identity,
            thumbnailJPEGBase64: "QUJDMTIz"  // base64 for "ABC123"
        )
        let data = try RecipeFileIO.encode(doc)
        let decoded = try RecipeFileIO.decode(data)
        XCTAssertEqual(decoded.thumbnailJPEGBase64, "QUJDMTIz")
    }

    func testMissingThumbnailDecodes() throws {
        // JSON literal omitting thumbnailJPEGBase64 — must still decode (optional + default).
        let json = """
        { "schemaVersion": 1, "name": "NoThumb", "stack": { "schemaVersion": 1 } }
        """.data(using: .utf8)!
        let decoded = try RecipeFileIO.decode(json)
        XCTAssertNil(decoded.thumbnailJPEGBase64)
        XCTAssertEqual(decoded.name, "NoThumb")
    }
}

// PhotoEditorTests/LibraryItemMigrationTests.swift
import XCTest
@testable import PhotoEditor

final class LibraryItemMigrationTests: XCTestCase {

    func testV1Item_readsAsEditDocumentWithCopiedStacks() throws {
        var legacyStack = AdjustmentStack.identity
        legacyStack.light.exposure = 0.6
        legacyStack.filter = FilterSelection(filterID: "kodak_100", strength: 0.8)
        let legacyData = try JSONEncoder().encode(legacyStack)

        let item = LibraryItem(stackData: legacyData, documentData: nil, schemaVersion: 1)
        let doc = item.editDocument

        XCTAssertEqual(doc.schemaVersion, 2)
        XCTAssertNil(doc.mask)
        XCTAssertEqual(doc.subjectStack, legacyStack)
        XCTAssertEqual(doc.backgroundStack, legacyStack)
    }

    func testV2Item_roundTripsViaDocumentData() throws {
        var doc = EditDocument()
        doc.subjectStack.light.exposure = 0.4
        doc.backgroundStack.color.temperature = -0.5
        doc.mask = SubjectMask(feather: 0.3, invert: false, excludedInstances: [1])

        let item = LibraryItem()
        item.editDocument = doc
        let read = item.editDocument

        XCTAssertEqual(read, doc)
        XCTAssertEqual(item.schemaVersion, 2)
        XCTAssertNotNil(item.documentData)
    }

    func testEmptyItem_readsAsIdentity() {
        let item = LibraryItem()
        XCTAssertEqual(item.editDocument, .identity)
    }

    func testAdjustmentStackAccessor_returnsSubjectStack() throws {
        var doc = EditDocument()
        doc.subjectStack.light.exposure = 0.5
        doc.backgroundStack.light.exposure = -0.5  // different on purpose

        let item = LibraryItem()
        item.editDocument = doc

        XCTAssertEqual(item.adjustmentStack, doc.subjectStack)
        XCTAssertNotEqual(item.adjustmentStack, doc.backgroundStack)
    }

    func testAdjustmentStackSetter_mirrorsToBothStacks() {
        var stack = AdjustmentStack.identity
        stack.color.saturation = 0.7

        let item = LibraryItem()
        item.adjustmentStack = stack

        XCTAssertEqual(item.editDocument.subjectStack, stack)
        XCTAssertEqual(item.editDocument.backgroundStack, stack)
        XCTAssertNil(item.editDocument.mask)
    }
}

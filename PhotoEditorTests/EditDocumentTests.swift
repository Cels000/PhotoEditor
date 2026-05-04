import XCTest
@testable import PhotoEditor

final class EditDocumentTests: XCTestCase {

    func testIdentity_hasV2SchemaAndNilMask() {
        let doc = EditDocument()
        XCTAssertEqual(doc.schemaVersion, 2)
        XCTAssertNil(doc.mask)
        XCTAssertEqual(doc.subjectStack, .identity)
        XCTAssertEqual(doc.backgroundStack, .identity)
    }

    func testCodableRoundTrip_unmasked_preservesEquality() throws {
        var doc = EditDocument()
        doc.subjectStack.light.exposure = 0.4
        let data = try JSONEncoder().encode(doc)
        let decoded = try JSONDecoder().decode(EditDocument.self, from: data)
        XCTAssertEqual(doc, decoded)
    }

    func testCodableRoundTrip_masked_preservesAllFields() throws {
        var doc = EditDocument()
        doc.subjectStack.color.saturation = 0.5
        doc.backgroundStack.color.temperature = -0.3
        doc.mask = SubjectMask(feather: 0.4, invert: true, excludedInstances: [0, 2])
        let data = try JSONEncoder().encode(doc)
        let decoded = try JSONDecoder().decode(EditDocument.self, from: data)
        XCTAssertEqual(doc, decoded)
        XCTAssertEqual(decoded.mask?.feather, 0.4)
        XCTAssertEqual(decoded.mask?.excludedInstances, [0, 2])
    }

    func testMigrateFromLegacyStackData_producesV2WithCopiedStacks() throws {
        var legacy = AdjustmentStack.identity
        legacy.light.exposure = 0.7
        legacy.color.vibrance = 0.2
        let legacyData = try JSONEncoder().encode(legacy)

        let doc = try EditDocument.migrating(fromLegacyStackData: legacyData)

        XCTAssertEqual(doc.schemaVersion, 2)
        XCTAssertNil(doc.mask)
        XCTAssertEqual(doc.subjectStack, legacy)
        XCTAssertEqual(doc.backgroundStack, legacy)
    }

    func testSubjectMask_defaults() {
        let m = SubjectMask()
        XCTAssertEqual(m.feather, 0)
        XCTAssertFalse(m.invert)
        XCTAssertTrue(m.excludedInstances.isEmpty)
    }
}

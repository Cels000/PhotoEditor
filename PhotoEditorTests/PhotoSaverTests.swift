import XCTest
@testable import PhotoEditor

// NOTE: PhotoSaver calls PHPhotoLibrary which requires a live device / simulator.
// These tests verify the structural API contract and static properties.
// Full integration (actual save) requires a device test target with permission granted.

final class PhotoSaverTests: XCTestCase {

    // MARK: - API contract: PhotoSaver.Error cases exist

    func testErrorCasePermissionDenied() {
        let error = PhotoSaver.Error.permissionDenied
        // Ensure it is a Swift.Error
        let _: Swift.Error = error
        XCTAssertNotNil(error)
    }

    func testErrorCaseSaveFailedWithUnderlying() {
        let underlying = NSError(domain: "test", code: 42)
        let error = PhotoSaver.Error.saveFailed(underlying: underlying)
        let _: Swift.Error = error
        if case .saveFailed(let u) = error {
            XCTAssertEqual((u as? NSError)?.code, 42)
        } else {
            XCTFail("Expected saveFailed case")
        }
    }

    func testErrorCaseSaveFailedWithNilUnderlying() {
        let error = PhotoSaver.Error.saveFailed(underlying: nil)
        if case .saveFailed(let u) = error {
            XCTAssertNil(u)
        } else {
            XCTFail("Expected saveFailed case")
        }
    }

    // MARK: - save(_:format:) signature compiles as async throws

    func testSaveSignatureIsAsyncThrows() {
        // Compile-time check: Task confirms save is async throws and returns Void.
        // This test never runs the actual Photos write — it just ensures the
        // method signature exists with the correct shape.
        let _: (Data, ExportFormat) async throws -> Void = { data, format in
            try await PhotoSaver.save(encodedData: data, format: format)
        }
    }
}

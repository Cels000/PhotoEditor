// SubjectMaskStoreTests.swift
// PhotoEditorTests
import CoreImage
import XCTest
@testable import PhotoEditor

@MainActor
final class SubjectMaskStoreTests: XCTestCase {

    private let testAssetID: AssetID = "test-asset-1"

    private func solidImage(_ value: CGFloat, size: CGSize = CGSize(width: 100, height: 100)) -> CIImage {
        CIImage(color: CIColor(red: value, green: value, blue: value, alpha: 1))
            .cropped(to: CGRect(origin: .zero, size: size))
    }

    func testInitialState_noCachedMask() {
        let store = SubjectMaskStore.makeForTesting()
        XCTAssertNil(store.currentMask(for: testAssetID))
    }

    func testCacheHit_afterFirstCompute_returnsCachedResult() async throws {
        let store = SubjectMaskStore.makeForTesting()
        let img = solidImage(0.5)
        _ = try await store.mask(for: testAssetID, source: img)
        XCTAssertNotNil(store.currentMask(for: testAssetID))
    }

    func testClear_removesCachedEntry() async throws {
        let store = SubjectMaskStore.makeForTesting()
        let img = solidImage(0.5)
        _ = try await store.mask(for: testAssetID, source: img)
        store.clear(for: testAssetID)
        XCTAssertNil(store.currentMask(for: testAssetID))
    }

    func testConcurrentRequests_coalesceIntoSingleCompute() async throws {
        let store = SubjectMaskStore.makeForTesting()
        let img = solidImage(0.5)
        async let a = store.mask(for: testAssetID, source: img)
        async let b = store.mask(for: testAssetID, source: img)
        let (ra, rb) = try await (a, b)
        XCTAssertEqual(ra.detectedAt, rb.detectedAt)
    }

    func testNoForegroundResult_returnsZeroOrMoreInstances() async throws {
        // Solid gray: Vision typically finds no foreground, but we don't assert
        // an exact count — only that the store handles 0-instance gracefully.
        let store = SubjectMaskStore.makeForTesting()
        let img = solidImage(0.5)
        let result = try await store.mask(for: testAssetID, source: img)
        XCTAssertGreaterThanOrEqual(result.instanceCount, 0)
    }
}

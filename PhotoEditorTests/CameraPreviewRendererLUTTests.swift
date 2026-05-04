import XCTest
import CoreImage
@testable import PhotoEditor

final class CameraPreviewRendererLUTTests: XCTestCase {

    private func solidImage() -> CIImage {
        CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
            .cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
    }

    func testNilFilterSelectionReturnsInputUnchanged() {
        let input = solidImage()
        let out = CameraPreviewRenderer.applyLUT(
            filterSelection: nil,
            to: input,
            cubeResolver: { _ in nil }
        )
        XCTAssertEqual(out.extent, input.extent)
        // Identity passthrough should yield the same CIImage instance.
        XCTAssertTrue(out === input)
    }

    func testMissingCubeFallsThroughToIdentity() {
        let input = solidImage()
        let sel = FilterSelection(filterID: "does-not-exist", strength: 1.0)
        let out = CameraPreviewRenderer.applyLUT(
            filterSelection: sel,
            to: input,
            cubeResolver: { _ in nil }
        )
        XCTAssertTrue(out === input)
    }

    func testZeroStrengthReturnsInputUnchanged() {
        let input = solidImage()
        let sel = FilterSelection(filterID: "anything", strength: 0)
        let out = CameraPreviewRenderer.applyLUT(
            filterSelection: sel,
            to: input,
            cubeResolver: { _ in
                // Identity cube — supplying a non-nil cube ensures the bypass
                // is driven by `strength: 0`, not by missing cube data.
                ColorCubeData.identity()
            }
        )
        XCTAssertTrue(out === input)
    }
}

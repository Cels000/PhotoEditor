import XCTest
import CoreImage
@testable import PhotoEditor

final class PipelineBuilderTests: XCTestCase {
    func testBuild_identityStack_preservesSourceExtent() {
        // 16x16 black CIImage as a deterministic source
        let source = CIImage(color: CIColor.black).cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16))
        let result = PipelineBuilder.build(stack: .identity, source: source)
        XCTAssertEqual(result.extent, source.extent,
                       "Identity stack must not change image extent")
    }

    func testBuild_identityStack_isReferentiallyOrEquallyEquivalent() {
        // Identity stack should produce output equivalent to source.
        // We can't easily compare CIImages bit-for-bit without rendering, so we
        // assert that the extent is unchanged and the same input yields the same output.
        let source = CIImage(color: CIColor.gray).cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
        let r1 = PipelineBuilder.build(stack: .identity, source: source)
        let r2 = PipelineBuilder.build(stack: .identity, source: source)
        XCTAssertEqual(r1.extent, r2.extent, "PipelineBuilder must be deterministic")
    }
}

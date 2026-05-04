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

extension PipelineBuilderTests {

    // Helper: build a 4x4 solid-color CIImage for testing.
    private func sampleImage(r: CGFloat, g: CGFloat, b: CGFloat) -> CIImage {
        let color = CIColor(red: r, green: g, blue: b, alpha: 1)
        return CIImage(color: color).cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4))
    }

    // Helper: render to RGBA8 bytes via a CPU CIContext (deterministic).
    private func renderBytes(_ image: CIImage) -> [UInt8] {
        let ctx = CIContext(options: [.useSoftwareRenderer: true])
        guard let cg = ctx.createCGImage(image, from: image.extent) else { return [] }
        let w = cg.width, h = cg.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        let ctx2 = CGContext(data: &bytes, width: w, height: h,
                             bitsPerComponent: 8, bytesPerRow: w * 4,
                             space: cs, bitmapInfo: info)!
        ctx2.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return bytes
    }

    func testIdentityLUTProducesPixelIdenticalOutput() {
        let identity = ColorCubeData.identity()
        let resolver: CubeResolver = { _ in identity }
        let source = sampleImage(r: 0.4, g: 0.6, b: 0.2)
        let selection = FilterSelection(filterID: "test.identity", strength: 1.0)

        let baseline = renderBytes(source)
        let filtered = renderBytes(PipelineBuilder.applyLUT(selection, to: source, cubeResolver: resolver))

        XCTAssertEqual(baseline.count, filtered.count)
        // Allow 1/255 rounding tolerance per byte.
        for i in 0..<min(baseline.count, filtered.count) {
            XCTAssertLessThanOrEqual(abs(Int(baseline[i]) - Int(filtered[i])), 1,
                                     "Identity LUT should not shift pixel \(i)")
        }
    }

    func testStrengthZeroReturnsOriginal() {
        let identity = ColorCubeData.identity()
        let resolver: CubeResolver = { _ in identity }
        let source = sampleImage(r: 0.5, g: 0.5, b: 0.5)
        let selection = FilterSelection(filterID: "test.identity", strength: 0.0)
        let out = PipelineBuilder.applyLUT(selection, to: source, cubeResolver: resolver)
        XCTAssertEqual(out.extent, source.extent)
    }

    func testNilCubeResolverReturnsInput() {
        let source = sampleImage(r: 0.1, g: 0.2, b: 0.3)
        let selection = FilterSelection(filterID: "anything", strength: 1.0)
        let out = PipelineBuilder.applyLUT(selection, to: source, cubeResolver: nil)
        XCTAssertEqual(out.extent, source.extent)
    }

    // MARK: - Crop suppression (Task 2)

    func testBuildSuppressingCrop_ignoresCropField() {
        let source = CIImage(color: CIColor.gray)
            .cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
        var stack = AdjustmentStack.identity
        stack.crop.normalizedRect = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)

        let cropped = PipelineBuilder.build(stack: stack, source: source, cubeResolver: nil)
        let uncropped = PipelineBuilder.build(stack: stack, source: source, cubeResolver: nil, suppressCrop: true)

        XCTAssertEqual(cropped.extent.width, 50, accuracy: 0.5,
                       "default build should apply crop normalizedRect")
        XCTAssertEqual(uncropped.extent.width, 100, accuracy: 0.5,
                       "suppressCrop:true should skip the crop stage")
    }

    func testBuildSuppressingCrop_preservesNonCropAdjustments() {
        let source = CIImage(color: CIColor.gray)
            .cropped(to: CGRect(x: 0, y: 0, width: 50, height: 50))
        var stack = AdjustmentStack.identity
        stack.light.exposure = 0.5
        stack.crop.normalizedRect = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)

        let withCrop = PipelineBuilder.build(stack: stack, source: source, cubeResolver: nil)
        let suppressed = PipelineBuilder.build(stack: stack, source: source, cubeResolver: nil, suppressCrop: true)

        // Both should have +0.5 exposure applied. Sample average brightness.
        let ctx = CIContext(options: [.useSoftwareRenderer: true])
        guard let withCG = ctx.createCGImage(withCrop, from: withCrop.extent),
              let suppressedCG = ctx.createCGImage(suppressed, from: suppressed.extent) else {
            XCTFail("CIContext rendering failed")
            return
        }
        XCTAssertEqual(averagePixel(withCG), averagePixel(suppressedCG), accuracy: 0.05,
                       "non-crop adjustments must be identical between cropped and suppressed paths")
    }

    private func averagePixel(_ cg: CGImage) -> Double {
        let bpr = cg.width * 4
        var data = [UInt8](repeating: 0, count: bpr * cg.height)
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: &data, width: cg.width, height: cg.height,
                            bitsPerComponent: 8, bytesPerRow: bpr,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        var total: Double = 0
        let count = cg.width * cg.height
        for i in 0..<count {
            total += Double(data[i*4]) / 255
            total += Double(data[i*4+1]) / 255
            total += Double(data[i*4+2]) / 255
        }
        return total / Double(count * 3)
    }
}

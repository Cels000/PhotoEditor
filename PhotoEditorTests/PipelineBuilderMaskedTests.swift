// PipelineBuilderMaskedTests.swift
// PhotoEditorTests
import CoreImage
import XCTest
@testable import PhotoEditor

final class PipelineBuilderMaskedTests: XCTestCase {

    private func source(_ size: CGSize = CGSize(width: 100, height: 100)) -> CIImage {
        CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
            .cropped(to: CGRect(origin: .zero, size: size))
    }

    private func solidMask(value: CGFloat, size: CGSize) -> CIImage {
        CIImage(color: CIColor(red: value, green: value, blue: value, alpha: 1))
            .cropped(to: CGRect(origin: .zero, size: size))
    }

    func testBuildDocument_unmasked_matchesLegacyBuild() {
        let s = source()
        var stack = AdjustmentStack.identity
        stack.light.exposure = 0.3
        let doc = EditDocument(schemaVersion: 2, subjectStack: stack, backgroundStack: stack, mask: nil)
        let legacy = PipelineBuilder.build(stack: stack, source: s, cubeResolver: nil)
        let viaDoc = PipelineBuilder.build(document: doc, source: s, cubeResolver: nil, maskProvider: nil)
        XCTAssertEqual(legacy.extent, viaDoc.extent)
    }

    func testBuildDocument_maskedWithSolidWhiteMask_yieldsSubjectStackOnly() {
        let s = source()
        var subj = AdjustmentStack.identity
        subj.light.exposure = 0.8
        var bg = AdjustmentStack.identity
        bg.light.exposure = -0.8
        let doc = EditDocument(
            schemaVersion: 2, subjectStack: subj, backgroundStack: bg,
            mask: SubjectMask()
        )

        let provider = StubMaskProvider(combined: solidMask(value: 1, size: CGSize(width: 100, height: 100)))
        let composite = PipelineBuilder.build(document: doc, source: s, cubeResolver: nil,
                                              maskProvider: provider, assetID: "x")

        let ctx = CIContext(options: [.useSoftwareRenderer: true])
        let cg = ctx.createCGImage(composite, from: composite.extent)!
        XCTAssertGreaterThan(averagePixel(cg), 0.6)
    }

    func testBuildDocument_maskedWithSolidBlackMask_yieldsBackgroundStackOnly() {
        let s = source()
        var subj = AdjustmentStack.identity
        subj.light.exposure = 0.8
        var bg = AdjustmentStack.identity
        bg.light.exposure = -0.8
        let doc = EditDocument(
            schemaVersion: 2, subjectStack: subj, backgroundStack: bg,
            mask: SubjectMask()
        )

        let provider = StubMaskProvider(combined: solidMask(value: 0, size: CGSize(width: 100, height: 100)))
        let composite = PipelineBuilder.build(document: doc, source: s, cubeResolver: nil,
                                              maskProvider: provider, assetID: "x")

        let ctx = CIContext(options: [.useSoftwareRenderer: true])
        let cg = ctx.createCGImage(composite, from: composite.extent)!
        XCTAssertLessThan(averagePixel(cg), 0.4)
    }

    func testBuildDocument_invertedMask_swapsRegions() {
        let s = source()
        var subj = AdjustmentStack.identity
        subj.light.exposure = 0.8
        var bg = AdjustmentStack.identity
        bg.light.exposure = -0.8

        let provider = StubMaskProvider(combined: solidMask(value: 1, size: CGSize(width: 100, height: 100)))

        let docNormal = EditDocument(schemaVersion: 2, subjectStack: subj, backgroundStack: bg, mask: SubjectMask())
        var docInverted = docNormal
        docInverted.mask?.invert = true

        let normal = PipelineBuilder.build(document: docNormal, source: s, cubeResolver: nil,
                                           maskProvider: provider, assetID: "x")
        let inverted = PipelineBuilder.build(document: docInverted, source: s, cubeResolver: nil,
                                             maskProvider: provider, assetID: "x")

        let ctx = CIContext(options: [.useSoftwareRenderer: true])
        let nCG = ctx.createCGImage(normal, from: normal.extent)!
        let iCG = ctx.createCGImage(inverted, from: inverted.extent)!
        XCTAssertGreaterThan(averagePixel(nCG), averagePixel(iCG))
    }

    func testBuildDocument_cropAppliedFromSubjectStack_postComposite() {
        let s = source(CGSize(width: 200, height: 200))
        var subj = AdjustmentStack.identity
        subj.crop.normalizedRect = CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        var bg = AdjustmentStack.identity
        bg.crop.normalizedRect = CGRect(x: 0, y: 0, width: 1, height: 1)

        let doc = EditDocument(
            schemaVersion: 2, subjectStack: subj, backgroundStack: bg,
            mask: SubjectMask()
        )
        let provider = StubMaskProvider(combined: solidMask(value: 0.5, size: CGSize(width: 200, height: 200)))
        let composite = PipelineBuilder.build(document: doc, source: s, cubeResolver: nil,
                                              maskProvider: provider, assetID: "x")

        XCTAssertEqual(composite.extent.width, 100, accuracy: 0.5,
                       "crop must come from subjectStack (200 * 0.5 = 100)")
    }

    // MARK: - Stub provider

    final class StubMaskProvider: SubjectMaskProvider {
        let combined: CIImage
        let perInstance: [CIImage]
        init(combined: CIImage, perInstance: [CIImage] = []) {
            self.combined = combined
            self.perInstance = perInstance
        }
        func currentMask(for assetID: AssetID) -> SubjectMaskResult? {
            SubjectMaskResult(combined: combined,
                              perInstance: perInstance,
                              instanceCount: max(1, perInstance.count),
                              detectedAt: Date())
        }
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

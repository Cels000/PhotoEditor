import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Resolves a filter ID to its loaded cube data. Injected so PipelineBuilder
/// stays decoupled from FilterLibrary. Pass nil from contexts where no LUT
/// resolution is possible (tests, Phase-1 callers).
typealias CubeResolver = (String) -> ColorCubeData?

/// Pure namespace that turns an `AdjustmentStack` into a CIImage filter chain.
/// Stage order is locked per ADJUST-10:
/// LUT → light → color → HSL → curves → split toning → grain → vignette → sharpness → crop.
/// Phase 1 implements light + color; every other stage returns its input unchanged.
enum PipelineBuilder {

    /// Top-level entry point. Pure: same inputs always produce the same output.
    static func build(stack: AdjustmentStack, source: CIImage, cubeResolver: CubeResolver? = nil) -> CIImage {
        var img = source
        img = applyLUT(stack.filter, to: img, cubeResolver: cubeResolver)  // 1. Phase 2
        img = applyLight(stack.light, to: img)            // 2. Phase 1
        img = applyColor(stack.color, to: img)            // 3. Phase 1
        img = applyHSL(stack.hsl, to: img)                // 4. Phase 3
        img = applyCurves(stack.curves, to: img)          // 5. Phase 3
        img = applySplitToning(stack.splitToning, to: img)// 6. Phase 3
        img = applyGrain(stack.grain, to: img)            // 7. Phase 3
        img = applyVignette(stack.vignette, to: img)      // 8. Phase 3
        img = applySharpness(stack.sharpness, to: img)    // 9. Phase 3
        img = applyCrop(stack.crop, to: img)              // 10. Phase 3
        return img
    }

    // MARK: - Stage 2: Light (Phase 1 implementation)

    static func applyLight(_ light: LightAdjustments, to image: CIImage) -> CIImage {
        var output = image

        // Exposure: stack.light.exposure is -1...+1; map to EV in -3...+3 range.
        if light.exposure != 0 {
            let exposureFilter = CIFilter.exposureAdjust()
            exposureFilter.inputImage = output
            exposureFilter.ev = Float(light.exposure * 3.0)
            if let result = exposureFilter.outputImage {
                output = result
            }
        }

        // Contrast: stack.light.contrast is -1...+1; CIColorControls.contrast neutral = 1.0,
        // so map -1 → 0.0, 0 → 1.0, +1 → 2.0.
        if light.contrast != 0 {
            let contrastFilter = CIFilter.colorControls()
            contrastFilter.inputImage = output
            contrastFilter.contrast = Float(1.0 + light.contrast)
            contrastFilter.brightness = 0
            contrastFilter.saturation = 1.0
            if let result = contrastFilter.outputImage {
                output = result
            }
        }

        // Highlights / shadows
        if light.highlights != 0 || light.shadows != 0 {
            let hsFilter = CIFilter.highlightShadowAdjust()
            hsFilter.inputImage = output
            // CIHighlightShadowAdjust: highlightAmount default 1.0, shadowAmount default 0.0.
            // We map our -1...+1 sliders to reasonable ranges.
            hsFilter.highlightAmount = Float(1.0 - max(0, light.highlights * 0.7))
            hsFilter.shadowAmount = Float(light.shadows * 0.7)
            if let result = hsFilter.outputImage {
                output = result
            }
        }

        // whites / blacks: Phase 1 stub — no-op (Phase 3 wires fully)
        return output
    }

    // MARK: - Stage 3: Color (Phase 1 implementation)

    static func applyColor(_ color: ColorAdjustments, to image: CIImage) -> CIImage {
        var output = image

        // Saturation: -1...+1 maps to CIColorControls.saturation 0.0 → 1.0 → 2.0
        if color.saturation != 0 {
            let satFilter = CIFilter.colorControls()
            satFilter.inputImage = output
            satFilter.saturation = Float(1.0 + color.saturation)
            satFilter.contrast = 1.0
            satFilter.brightness = 0
            if let result = satFilter.outputImage {
                output = result
            }
        }

        // Vibrance: stack.color.vibrance is -1...+1; CIVibrance.amount accepts roughly that range.
        if color.vibrance != 0 {
            let vibFilter = CIFilter.vibrance()
            vibFilter.inputImage = output
            vibFilter.amount = Float(color.vibrance)
            if let result = vibFilter.outputImage {
                output = result
            }
        }

        // temperature / tint: Phase 1 stub — no-op (Phase 3 wires fully via CITemperatureAndTint)
        return output
    }

    // MARK: - Phase-deferred stages (return input unchanged in Phase 1)

    static func applyLUT(_ filter: FilterSelection?,
                         to image: CIImage,
                         cubeResolver: CubeResolver? = nil) -> CIImage {
        guard let filter = filter,
              !filter.filterID.isEmpty,
              filter.strength > 0,
              let resolver = cubeResolver,
              let cube = resolver(filter.filterID) else {
            return image
        }

        // Apply the cube in linear sRGB working space (matches RenderEngine config).
        // PITFALLS #1: explicitly pass the LUT's design color space.
        let linearSRGB = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!

        let cubeFilter = CIFilter.colorCubeWithColorSpace()
        cubeFilter.inputImage = image
        cubeFilter.cubeDimension = Float(ColorCubeData.dimension)
        cubeFilter.cubeData = cube.rawData
        cubeFilter.colorSpace = linearSRGB

        guard let filtered = cubeFilter.outputImage else { return image }

        // Strength == 1 → full filter; otherwise linear blend with original via
        // CISourceOverCompositing on an alpha-scaled top layer.
        let s = max(0.0, min(1.0, filter.strength))
        if s >= 0.999 { return filtered }

        let alpha = CIFilter.colorMatrix()
        alpha.inputImage = filtered
        alpha.aVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(s))
        guard let topLayer = alpha.outputImage else { return filtered }

        let composite = CIFilter.sourceOverCompositing()
        composite.inputImage = topLayer
        composite.backgroundImage = image
        return composite.outputImage ?? filtered
    }
    static func applyHSL(_ hsl: HSLAdjustments, to image: CIImage) -> CIImage { image }            // Phase 3
    static func applyCurves(_ curves: ToneCurves, to image: CIImage) -> CIImage { image }          // Phase 3
    static func applySplitToning(_ split: SplitToning, to image: CIImage) -> CIImage { image }     // Phase 3
    static func applyGrain(_ grain: GrainSettings, to image: CIImage) -> CIImage { image }         // Phase 3
    static func applyVignette(_ vignette: VignetteSettings, to image: CIImage) -> CIImage { image }// Phase 3
    static func applySharpness(_ sharpness: Double, to image: CIImage) -> CIImage { image }        // Phase 3
    static func applyCrop(_ crop: CropSettings, to image: CIImage) -> CIImage { image }            // Phase 3
}

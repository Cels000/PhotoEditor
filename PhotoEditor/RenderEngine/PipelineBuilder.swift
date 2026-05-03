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

        // Whites/Blacks: 5-point CIToneCurve endpoint shaping (full free-form curves come in 03-06).
        // Skip if both zero to preserve identity-stack guarantee.
        if light.whites != 0 || light.blacks != 0 {
            let curve = CIFilter.toneCurve()
            curve.inputImage = output

            // -1...+1 inputs → endpoint shifts of ±0.3 in normalized space.
            let blacksShift = Float(max(-1, min(1, light.blacks))) * 0.3
            let whitesShift = Float(max(-1, min(1, light.whites))) * 0.3

            // p0 lifts/crushes blacks: positive blacks → x>0 → blacks lifted; negative → y<0 (clamped 0).
            let p0x: Float = max(0, blacksShift)
            let p0y: Float = max(0, -blacksShift)
            // p4 compresses/extends whites: positive whites → y stays 1.0 (push x<1 toward 1, brightening); negative → y<1 (compress whites)
            let p4x: Float = min(1, 1.0 - max(0, whitesShift))
            let p4y: Float = min(1, 1.0 + min(0, whitesShift))

            curve.point0 = CGPoint(x: CGFloat(p0x), y: CGFloat(p0y))
            curve.point1 = CGPoint(x: 0.25, y: 0.25)
            curve.point2 = CGPoint(x: 0.5,  y: 0.5)
            curve.point3 = CGPoint(x: 0.75, y: 0.75)
            curve.point4 = CGPoint(x: CGFloat(p4x), y: CGFloat(p4y))

            if let result = curve.outputImage {
                output = result
            }
        }

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

        // Temperature/Tint via CITemperatureAndTint.
        // Map -1...+1 to Kelvin offset of ±2500K around 6500K neutral.
        // Tint maps -1...+1 to ±100 on y axis (magenta/green).
        if color.temperature != 0 || color.tint != 0 {
            let tt = CIFilter.temperatureAndTint()
            tt.inputImage = output
            let kelvin = 6500.0 + color.temperature * 2500.0
            let tintY = color.tint * 100.0
            tt.neutral = CIVector(x: 6500, y: 0)
            tt.targetNeutral = CIVector(x: CGFloat(kelvin), y: CGFloat(tintY))
            if let result = tt.outputImage {
                output = result
            }
        }

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
    /// HSL: per-channel hue/sat/luminance adjustments.
    ///
    /// Implementation route: CIColorMatrix masking. Free-form Metal kernel HSL deferred to v2.
    ///
    /// Per Phase 3 plan 03-05: CIColorMatrix-based hue band masking + global CIHueAdjust per
    /// channel. This is a documented approximation; a precise per-pixel HSL requires a Metal
    /// CIColorKernel and is deferred to v2.
    ///
    /// For each non-default channel:
    ///   1. Build a hue-band mask by isolating pixels whose dominant channel matches the band
    ///      via a CIColorMatrix that boosts the band's primary RGB component and clamps others.
    ///   2. Apply CIHueAdjust (hue rotation), CIColorControls (saturation), and CIExposureAdjust
    ///      (luminance) to the source globally.
    ///   3. Composite the adjusted result over the running output via CIBlendWithMask using
    ///      the band mask — only band pixels receive the adjustment.
    static func applyHSL(_ hsl: HSLAdjustments, to image: CIImage) -> CIImage {
        let channels: [(name: String, ch: HSLChannel, mask: (CIImage) -> CIImage)] = [
            ("red",     hsl.red,     { hslMask(channel: .red,     in: $0) }),
            ("orange",  hsl.orange,  { hslMask(channel: .orange,  in: $0) }),
            ("yellow",  hsl.yellow,  { hslMask(channel: .yellow,  in: $0) }),
            ("green",   hsl.green,   { hslMask(channel: .green,   in: $0) }),
            ("aqua",    hsl.aqua,    { hslMask(channel: .aqua,    in: $0) }),
            ("blue",    hsl.blue,    { hslMask(channel: .blue,    in: $0) }),
            ("purple",  hsl.purple,  { hslMask(channel: .purple,  in: $0) }),
            ("magenta", hsl.magenta, { hslMask(channel: .magenta, in: $0) }),
        ]

        // Early-out: every channel default → identity (zero render cost).
        let nonDefault = channels.filter { $0.ch.hue != 0 || $0.ch.saturation != 0 || $0.ch.luminance != 0 }
        guard !nonDefault.isEmpty else { return image }

        var output = image
        for (_, ch, makeMask) in nonDefault {
            // Apply hue rotation globally on the *current* output.
            var adjusted = output
            if ch.hue != 0 {
                let hue = CIFilter.hueAdjust()
                hue.inputImage = adjusted
                hue.angle = Float(ch.hue * .pi / 6.0) // ±30° rotation at ±1
                if let r = hue.outputImage { adjusted = r }
            }
            if ch.saturation != 0 {
                let sat = CIFilter.colorControls()
                sat.inputImage = adjusted
                sat.saturation = Float(1.0 + ch.saturation)
                sat.contrast = 1.0
                sat.brightness = 0
                if let r = sat.outputImage { adjusted = r }
            }
            if ch.luminance != 0 {
                let lum = CIFilter.exposureAdjust()
                lum.inputImage = adjusted
                lum.ev = Float(ch.luminance * 0.5)
                if let r = lum.outputImage { adjusted = r }
            }

            // Composite the channel-band region from `adjusted` over `output`.
            let mask = makeMask(image)
            let blend = CIFilter.blendWithMask()
            blend.inputImage = adjusted
            blend.backgroundImage = output
            blend.maskImage = mask
            if let r = blend.outputImage { output = r }
        }
        return output
    }

    /// 8 hue bands. Each mask isolates pixels whose dominant color matches the channel.
    /// Implemented as CIColorMatrix-based RGB-component-emphasis filters; the resulting
    /// luminance image is the mask (bright where channel dominates).
    private enum HSLBand { case red, orange, yellow, green, aqua, blue, purple, magenta }

    private static func hslMask(channel: HSLBand, in source: CIImage) -> CIImage {
        // Build a luminance-style image where the target band has high values.
        // Approximation: each band emphasizes specific (R,G,B) combinations.
        let m = CIFilter.colorMatrix()
        m.inputImage = source
        let zero = CIVector(x: 0, y: 0, z: 0, w: 0)
        switch channel {
        case .red:
            m.rVector = CIVector(x:  1, y: -0.5, z: -0.5, w: 0)
            m.gVector = CIVector(x:  1, y: -0.5, z: -0.5, w: 0)
            m.bVector = CIVector(x:  1, y: -0.5, z: -0.5, w: 0)
        case .orange:
            m.rVector = CIVector(x:  1, y:  0.5, z: -1, w: 0)
            m.gVector = CIVector(x:  1, y:  0.5, z: -1, w: 0)
            m.bVector = CIVector(x:  1, y:  0.5, z: -1, w: 0)
        case .yellow:
            m.rVector = CIVector(x:  0.5, y:  1, z: -1, w: 0)
            m.gVector = CIVector(x:  0.5, y:  1, z: -1, w: 0)
            m.bVector = CIVector(x:  0.5, y:  1, z: -1, w: 0)
        case .green:
            m.rVector = CIVector(x: -0.5, y:  1, z: -0.5, w: 0)
            m.gVector = CIVector(x: -0.5, y:  1, z: -0.5, w: 0)
            m.bVector = CIVector(x: -0.5, y:  1, z: -0.5, w: 0)
        case .aqua:
            m.rVector = CIVector(x: -1, y:  0.5, z:  1, w: 0)
            m.gVector = CIVector(x: -1, y:  0.5, z:  1, w: 0)
            m.bVector = CIVector(x: -1, y:  0.5, z:  1, w: 0)
        case .blue:
            m.rVector = CIVector(x: -0.5, y: -0.5, z: 1, w: 0)
            m.gVector = CIVector(x: -0.5, y: -0.5, z: 1, w: 0)
            m.bVector = CIVector(x: -0.5, y: -0.5, z: 1, w: 0)
        case .purple:
            m.rVector = CIVector(x:  0.5, y: -1, z: 1, w: 0)
            m.gVector = CIVector(x:  0.5, y: -1, z: 1, w: 0)
            m.bVector = CIVector(x:  0.5, y: -1, z: 1, w: 0)
        case .magenta:
            m.rVector = CIVector(x:  1, y: -1, z: 0.5, w: 0)
            m.gVector = CIVector(x:  1, y: -1, z: 0.5, w: 0)
            m.bVector = CIVector(x:  1, y: -1, z: 0.5, w: 0)
        }
        m.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        m.biasVector = zero
        let raw = m.outputImage ?? source

        // Clamp to 0...1 so blendWithMask reads it as alpha.
        let clamp = CIFilter.colorClamp()
        clamp.inputImage = raw
        clamp.minComponents = CIVector(x: 0, y: 0, z: 0, w: 0)
        clamp.maxComponents = CIVector(x: 1, y: 1, z: 1, w: 1)
        return clamp.outputImage ?? raw
    }

    static func applyCurves(_ curves: ToneCurves, to image: CIImage) -> CIImage { image }          // Phase 3
    static func applySplitToning(_ split: SplitToning, to image: CIImage) -> CIImage { image }     // Phase 3
    static func applyGrain(_ grain: GrainSettings, to image: CIImage) -> CIImage {
        guard grain.intensity > 0 else { return image }

        // Generate infinite random noise; crop to source extent.
        let random = CIFilter.randomGenerator()
        guard let randomImage = random.outputImage else { return image }

        // Scale pattern by (1 + size*3) so size=1 → 4× larger blobs (coarser grain).
        let scale = 1.0 + grain.size * 3.0
        let scaled = randomImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // Convert to grayscale luminance via CIColorMatrix (Rec.709 weights, alpha = intensity*0.4).
        let gray = CIFilter.colorMatrix()
        gray.inputImage = scaled
        gray.rVector = CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0)
        gray.gVector = CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0)
        gray.bVector = CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0)
        let alpha = max(0, min(1, grain.intensity * 0.4))
        gray.aVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(alpha))
        guard let grainLayer = gray.outputImage else { return image }

        let cropped = grainLayer.cropped(to: image.extent)

        let comp = CIFilter.sourceOverCompositing()
        comp.inputImage = cropped
        comp.backgroundImage = image
        return comp.outputImage ?? image
    }

    static func applyVignette(_ vignette: VignetteSettings, to image: CIImage) -> CIImage {
        guard vignette.amount != 0 else { return image }
        let v = CIFilter.vignette()
        v.inputImage = image
        v.intensity = Float(max(-1, min(1, vignette.amount)) * 2.0) // CIVignette useful intensity ±2
        v.radius = Float(1.0 + max(0, min(1, vignette.feather)) * 1.5) // 1.0...2.5
        return v.outputImage ?? image
    }

    static func applySharpness(_ sharpness: Double, to image: CIImage) -> CIImage {
        guard sharpness > 0 else { return image }
        let s = CIFilter.sharpenLuminance()
        s.inputImage = image
        s.sharpness = Float(max(0, min(1, sharpness)) * 2.0) // 0...2 useful
        return s.outputImage ?? image
    }
    static func applyCrop(_ crop: CropSettings, to image: CIImage) -> CIImage { image }            // Phase 3
}

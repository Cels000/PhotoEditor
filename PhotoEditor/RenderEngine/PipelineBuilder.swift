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
    static func build(stack: AdjustmentStack,
                      source: CIImage,
                      cubeResolver: CubeResolver? = nil,
                      suppressCrop: Bool = false) -> CIImage {
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
        if !suppressCrop {
            img = applyCrop(stack.crop, to: img)          // 10. Phase 3 (skipped when masking)
        }
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

    // MARK: - Stage 5: Curves (Phase 3 implementation)

    /// Tone curves: composite (RGB) + per-channel R/G/B.
    ///
    /// CIToneCurve accepts exactly 5 control points. We sample the user's
    /// piecewise-linear curve at 5 evenly-spaced X positions to fit. Free-form
    /// (>5 point) curves require a Metal CIColorKernel and are deferred to v2.
    ///
    /// Per-channel curves are implemented by isolating each color channel via
    /// CIColorMatrix, applying CIToneCurve, and additively recomposing — a
    /// documented approximation. v2 may switch to a kernel for higher fidelity.
    static func applyCurves(_ curves: ToneCurves, to image: CIImage) -> CIImage {
        var output = image
        // Composite RGB curve.
        if let curveFilter = makeCurveFilter(curves.rgb) {
            curveFilter.setValue(output, forKey: kCIInputImageKey)
            if let r = curveFilter.outputImage { output = r }
        }
        // Per-channel: skip if curve is identity.
        if !isIdentityCurve(curves.red) {
            output = applyChannelCurve(channel: .r, curve: curves.red, base: output)
        }
        if !isIdentityCurve(curves.green) {
            output = applyChannelCurve(channel: .g, curve: curves.green, base: output)
        }
        if !isIdentityCurve(curves.blue) {
            output = applyChannelCurve(channel: .b, curve: curves.blue, base: output)
        }
        return output
    }

    private enum RGBChannel { case r, g, b }

    private static func isIdentityCurve(_ channel: CurveChannel) -> Bool {
        // Identity: every point.y == point.x.
        return channel.points.allSatisfy { abs($0.x - $0.y) < 1e-6 }
    }

    /// Sample the user's piecewise-linear curve at 5 evenly-spaced X positions
    /// and return a CIToneCurve filter. Returns nil if curve is identity.
    private static func makeCurveFilter(_ channel: CurveChannel) -> CIFilter? {
        guard !isIdentityCurve(channel) else { return nil }

        let xs: [Double] = [0.0, 0.25, 0.5, 0.75, 1.0]
        let ys = xs.map { sampleCurve(channel.points, at: $0) }

        let f = CIFilter.toneCurve()
        f.point0 = CGPoint(x: xs[0], y: ys[0])
        f.point1 = CGPoint(x: xs[1], y: ys[1])
        f.point2 = CGPoint(x: xs[2], y: ys[2])
        f.point3 = CGPoint(x: xs[3], y: ys[3])
        f.point4 = CGPoint(x: xs[4], y: ys[4])
        return f
    }

    private static func sampleCurve(_ pts: [CurvePoint], at x: Double) -> Double {
        guard !pts.isEmpty else { return x }
        let sorted = pts.sorted { $0.x < $1.x }
        if x <= sorted.first!.x { return sorted.first!.y }
        if x >= sorted.last!.x  { return sorted.last!.y  }
        for i in 0..<(sorted.count - 1) {
            let a = sorted[i], b = sorted[i+1]
            if x >= a.x && x <= b.x {
                let t = (x - a.x) / max(1e-9, (b.x - a.x))
                return a.y + t * (b.y - a.y)
            }
        }
        return x
    }

    /// Apply per-channel curve via decompose-recompose.
    /// - Extract the target channel as a grayscale image.
    /// - Apply CIToneCurve to that grayscale image.
    /// - Recompose into RGBA by re-injecting the adjusted channel.
    private static func applyChannelCurve(channel: RGBChannel, curve: CurveChannel, base: CIImage) -> CIImage {
        // Extract: keep only target channel, zero others.
        let extract = CIFilter.colorMatrix()
        extract.inputImage = base
        let zero = CIVector(x: 0, y: 0, z: 0, w: 0)
        switch channel {
        case .r:
            extract.rVector = CIVector(x: 1, y: 0, z: 0, w: 0)
            extract.gVector = CIVector(x: 1, y: 0, z: 0, w: 0)
            extract.bVector = CIVector(x: 1, y: 0, z: 0, w: 0)
        case .g:
            extract.rVector = CIVector(x: 0, y: 1, z: 0, w: 0)
            extract.gVector = CIVector(x: 0, y: 1, z: 0, w: 0)
            extract.bVector = CIVector(x: 0, y: 1, z: 0, w: 0)
        case .b:
            extract.rVector = CIVector(x: 0, y: 0, z: 1, w: 0)
            extract.gVector = CIVector(x: 0, y: 0, z: 1, w: 0)
            extract.bVector = CIVector(x: 0, y: 0, z: 1, w: 0)
        }
        extract.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        extract.biasVector = zero
        guard let channelImage = extract.outputImage else { return base }

        guard let curveFilter = makeCurveFilter(curve) else { return base }
        curveFilter.setValue(channelImage, forKey: kCIInputImageKey)
        guard let curved = curveFilter.outputImage else { return base }

        // Re-inject: zero out the target channel of base.
        let inject = CIFilter.colorMatrix()
        inject.inputImage = base
        switch channel {
        case .r: inject.rVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        case .g: inject.gVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        case .b: inject.bVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        }
        guard let zeroed = inject.outputImage else { return base }

        // Mask the curved-channel image to write only the target channel.
        let mask = CIFilter.colorMatrix()
        mask.inputImage = curved
        switch channel {
        case .r:
            mask.rVector = CIVector(x: 1, y: 0, z: 0, w: 0)
            mask.gVector = zero
            mask.bVector = zero
        case .g:
            mask.rVector = zero
            mask.gVector = CIVector(x: 1, y: 0, z: 0, w: 0)
            mask.bVector = zero
        case .b:
            mask.rVector = zero
            mask.gVector = zero
            mask.bVector = CIVector(x: 1, y: 0, z: 0, w: 0)
        }
        mask.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        mask.biasVector = zero
        guard let maskedCurved = mask.outputImage else { return base }

        // Add: zeroed + maskedCurved → recomposed.
        let add = CIFilter.additionCompositing()
        add.inputImage = maskedCurved
        add.backgroundImage = zeroed
        return add.outputImage ?? base
    }

    // MARK: - Stage 6: Split Toning (Phase 3 implementation)

    /// Split toning: tint highlights and shadows with chosen hues.
    /// Implementation: build a luminance image, derive shadow + highlight masks
    /// via CIToneCurve thresholding, tint each by converting (hue,sat) → RGB
    /// via CIColorMatrix, additively composite over the source.
    /// `balance` shifts the dividing line between shadows and highlights.
    static func applySplitToning(_ split: SplitToning, to image: CIImage) -> CIImage {
        guard split.highlightSaturation != 0 || split.shadowSaturation != 0 else { return image }

        // 1. Luminance.
        let lumaFilter = CIFilter.colorMatrix()
        lumaFilter.inputImage = image
        let luma = CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0)
        lumaFilter.rVector = luma
        lumaFilter.gVector = luma
        lumaFilter.bVector = luma
        lumaFilter.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        guard let lumaImage = lumaFilter.outputImage else { return image }

        // Balance shifts midpoint: balance > 0 → highlights region grows.
        let mid = 0.5 - split.balance * 0.25  // 0.25...0.75
        let edge = 0.15

        var output = image

        // 2. Highlights tint.
        if split.highlightSaturation != 0 {
            let maskFilter = CIFilter.toneCurve()
            maskFilter.inputImage = lumaImage
            maskFilter.point0 = CGPoint(x: 0, y: 0)
            maskFilter.point1 = CGPoint(x: max(0, mid - edge), y: 0)
            maskFilter.point2 = CGPoint(x: mid, y: 0.5)
            maskFilter.point3 = CGPoint(x: min(1, mid + edge), y: 1)
            maskFilter.point4 = CGPoint(x: 1, y: 1)
            if let highlightMask = maskFilter.outputImage {
                output = applyTint(over: output,
                                   mask: highlightMask,
                                   hueDegrees: split.highlightHue,
                                   amount: split.highlightSaturation)
            }
        }

        // 3. Shadows tint (inverted mask).
        if split.shadowSaturation != 0 {
            let maskFilter = CIFilter.toneCurve()
            maskFilter.inputImage = lumaImage
            // Inverted curve: bright at low luma, dark at high luma.
            maskFilter.point0 = CGPoint(x: 0, y: 1)
            maskFilter.point1 = CGPoint(x: max(0, mid - edge), y: 1)
            maskFilter.point2 = CGPoint(x: mid, y: 0.5)
            maskFilter.point3 = CGPoint(x: min(1, mid + edge), y: 0)
            maskFilter.point4 = CGPoint(x: 1, y: 0)
            if let shadowMask = maskFilter.outputImage {
                output = applyTint(over: output,
                                   mask: shadowMask,
                                   hueDegrees: split.shadowHue,
                                   amount: split.shadowSaturation)
            }
        }
        return output
    }

    /// Apply a hue-tint over an image, modulated by a luminance mask. amount in -1...+1.
    private static func applyTint(over image: CIImage,
                                  mask: CIImage,
                                  hueDegrees: Double,
                                  amount: Double) -> CIImage {
        // Hue → RGB. Use simple HSV-to-RGB at full saturation, value = 0.5.
        let h = (hueDegrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60.0
        let sector = Int(h) % 6
        let f = h - Double(Int(h))
        let v = 0.5
        let p = 0.0
        let q = v * (1 - f)
        let t = v * f
        var r: Double = 0, g: Double = 0, b: Double = 0
        switch sector {
        case 0: r = v; g = t; b = p
        case 1: r = q; g = v; b = p
        case 2: r = p; g = v; b = t
        case 3: r = p; g = q; b = v
        case 4: r = t; g = p; b = v
        default: r = v; g = p; b = q
        }
        // Build a constant-color tint image and crop to source extent.
        let tinted = CIImage(color: CIColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1.0))
            .cropped(to: image.extent)

        // Modulate tint alpha by mask intensity * amount cap.
        let cap = max(-0.5, min(0.5, amount * 0.3))
        let alphaFilter = CIFilter.colorMatrix()
        alphaFilter.inputImage = tinted
        alphaFilter.aVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(abs(cap)))
        guard let tintLayer = alphaFilter.outputImage else { return image }

        // Multiply tint layer by mask.
        let masked = CIFilter.blendWithMask()
        masked.inputImage = tintLayer
        masked.backgroundImage = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: image.extent)
        masked.maskImage = mask
        guard let tintMasked = masked.outputImage else { return image }

        // Composite over source.
        let comp = CIFilter.sourceOverCompositing()
        comp.inputImage = tintMasked
        comp.backgroundImage = image
        return comp.outputImage ?? image
    }
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
    /// Crop, free-rotate, 90° steps, and flips. Applied LAST in the pipeline.
    /// Per Pitfall #10: free-rotate MUST be a single transform from the source extent;
    /// never chain extent.integral across renders.
    static func applyCrop(_ crop: CropSettings, to image: CIImage) -> CIImage {
        let isFullRect = crop.normalizedRect == CGRect(x: 0, y: 0, width: 1, height: 1)
        let isIdentity = isFullRect
            && crop.rotationDegrees == 0
            && crop.clockwiseRotations == 0
            && !crop.flippedHorizontally
            && !crop.flippedVertically
        guard !isIdentity else { return image }

        var output = image
        let extent0 = output.extent

        // 1. 90° rotations.
        let steps = ((crop.clockwiseRotations % 4) + 4) % 4
        if steps != 0 {
            let radians = -CGFloat(steps) * .pi / 2  // CW
            let t = CGAffineTransform(rotationAngle: radians)
            output = output.transformed(by: t)
        }

        // 2. Flips around the (current) extent center.
        if crop.flippedHorizontally || crop.flippedVertically {
            let ext = output.extent
            let cx = ext.midX, cy = ext.midY
            var t = CGAffineTransform(translationX: cx, y: cy)
            t = t.scaledBy(x: crop.flippedHorizontally ? -1 : 1,
                           y: crop.flippedVertically ? -1 : 1)
            t = t.translatedBy(x: -cx, y: -cy)
            output = output.transformed(by: t)
        }

        // 3. Free rotation (single transform, applied to current output).
        if crop.rotationDegrees != 0 {
            let rad = CGFloat(crop.rotationDegrees) * .pi / 180
            let ext = output.extent
            let cx = ext.midX, cy = ext.midY
            var t = CGAffineTransform(translationX: cx, y: cy)
            t = t.rotated(by: rad)
            t = t.translatedBy(x: -cx, y: -cy)
            output = output.transformed(by: t)
        }

        // 4. Crop to normalizedRect (computed in current extent).
        if !isFullRect {
            let ext = output.extent
            let cropRect = CGRect(
                x: ext.origin.x + crop.normalizedRect.origin.x * ext.width,
                y: ext.origin.y + crop.normalizedRect.origin.y * ext.height,
                width: crop.normalizedRect.width * ext.width,
                height: crop.normalizedRect.height * ext.height
            )
            output = output.cropped(to: cropRect)
        }

        // Origin-correct: shift back to (0,0) for downstream consumers (export).
        let final = output.transformed(by: CGAffineTransform(
            translationX: -output.extent.origin.x,
            y: -output.extent.origin.y))
        _ = extent0  // referenced for symmetry (no-op)
        return final
    }
}

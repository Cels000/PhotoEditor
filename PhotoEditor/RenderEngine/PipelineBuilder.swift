import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Resolves a filter ID to its loaded cube data. Injected so PipelineBuilder
/// stays decoupled from FilterLibrary. Pass nil from contexts where no LUT
/// resolution is possible (tests, Phase-1 callers).
typealias CubeResolver = (String) -> ColorCubeData?

/// Pure namespace that turns an `AdjustmentStack` into a CIImage filter chain.
/// Stage order: LUT → light → color → HSL → curves → split toning → halation
/// → sharpness → softness → grain → vignette → crop. Halation lands after the
/// color/tone work (so the red glow respects the final highlight tone) but
/// before sharpness/softness/grain so the glow gets the same final treatment
/// as the rest of the image.
enum PipelineBuilder {

    /// Camera-viewfinder variant. Skips the two stages that dominate per-frame
    /// cost — grain (per-pixel noise) and halation (Gaussian blur + composite)
    /// — and forces suppressCrop. Everything else (LUT, light, color, HSL,
    /// curves, split toning, sharpness, softness, vignette) runs as in the
    /// editor pipeline so the live preview shows the recipe's true color
    /// signature, not just the LUT. Grain/halation only land on capture.
    static func buildLive(stack: AdjustmentStack,
                          source: CIImage,
                          cubeResolver: CubeResolver? = nil) -> CIImage {
        var live = stack
        live.grain = GrainSettings()
        live.halation = 0
        return build(stack: live, source: source,
                     cubeResolver: cubeResolver, suppressCrop: true)
    }

    /// Top-level entry point. Pure: same inputs always produce the same output.
    static func build(stack: AdjustmentStack,
                      source: CIImage,
                      cubeResolver: CubeResolver? = nil,
                      suppressCrop: Bool = false) -> CIImage {
        var img = source
        img = applyLUT(stack.filter, to: img, cubeResolver: cubeResolver)  // 1
        img = applyLight(stack.light, to: img)             // 2
        img = applyColor(stack.color, to: img)             // 3
        img = applyHSL(stack.hsl, to: img)                 // 4
        img = applyCurves(stack.curves, to: img)           // 5
        img = applySplitToning(stack.splitToning, to: img) // 6
        img = applyHalation(stack.halation, to: img)       // 7  red highlight bloom
        img = applySharpness(stack.sharpness, to: img)     // 8
        img = applySoftness(stack.softness, to: img)       // 9  MTF roll-off
        img = applyGrain(stack.grain, to: img)             // 10
        img = applyVignette(stack.vignette, to: img)       // 11
        if !suppressCrop {
            img = applyCrop(stack.crop, to: img)           // 12 (skipped when masking)
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

        // Highlights / shadows. Lightroom convention: +highlights brightens, -highlights recovers.
        // CIHighlightShadowAdjust.highlightAmount can only DARKEN (range 0...1, default 1.0),
        // so we use it for the recovery direction only and lift highlights via a tone curve.
        // shadowAmount range is -1...1 (negative darkens, positive lifts) so it maps directly.
        if light.highlights < 0 || light.shadows != 0 {
            let hsFilter = CIFilter.highlightShadowAdjust()
            hsFilter.inputImage = output
            hsFilter.highlightAmount = Float(1.0 + min(0, light.highlights) * 0.7)
            hsFilter.shadowAmount = Float(light.shadows * 0.7)
            if let result = hsFilter.outputImage {
                output = result
            }
        }
        if light.highlights > 0 {
            // Lift the upper tone region — anchors at 0/0.25/0.5 stay put so
            // mids/shadows are untouched; p3 rises toward 1.0 to brighten highlights.
            let lift = CGFloat(min(1, light.highlights)) * 0.18
            let curve = CIFilter.toneCurve()
            curve.inputImage = output
            curve.point0 = CGPoint(x: 0,    y: 0)
            curve.point1 = CGPoint(x: 0.25, y: 0.25)
            curve.point2 = CGPoint(x: 0.5,  y: 0.5)
            curve.point3 = CGPoint(x: 0.75, y: min(1, 0.75 + lift))
            curve.point4 = CGPoint(x: 1,    y: 1)
            if let result = curve.outputImage {
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

            // p0 lifts/crushes blacks (Lightroom convention):
            //   positive blacks → p0=(0, +shift)  → input 0 maps to output >0  → LIFTED
            //   negative blacks → p0=(+shift, 0)  → input 0..+shift maps to 0  → CRUSHED
            let p0x: Float = max(0, -blacksShift)
            let p0y: Float = max(0,  blacksShift)
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
    /// HSL: per-channel hue/sat/luminance via a per-pixel CIColorKernel.
    ///
    /// Each pixel's hue is computed once, then 8 triangle-shaped band weights
    /// (centered on Lightroom's hue stops: red=0°, orange=30°, yellow=60°,
    /// green=120°, aqua=180°, blue=240°, purple=270°, magenta=300°, each with
    /// a 45° radius) are normalized so adjacent bands overlap smoothly without
    /// the heavy bleed the previous CIColorMatrix-mask approach had. Per-band
    /// hue/sat/lum deltas are blended by weight, applied in HSL space, and
    /// converted back to RGB. Single GPU pass replaces ~40 filter passes.
    ///
    /// Slider semantics (matches the prior implementation, callers don't change):
    ///   hue:        ±1 → ±30° rotation within the band
    ///   saturation: ±1 → CI sat 0...2 within the band
    ///   luminance:  ±1 → ±0.25 added to HSL L within the band
    static func applyHSL(_ hsl: HSLAdjustments, to image: CIImage) -> CIImage {
        let channels: [HSLChannel] = [hsl.red, hsl.orange, hsl.yellow, hsl.green,
                                      hsl.aqua, hsl.blue, hsl.purple, hsl.magenta]
        let allIdentity = channels.allSatisfy {
            $0.hue == 0 && $0.saturation == 0 && $0.luminance == 0
        }
        if allIdentity { return image }

        guard let kernel = hslKernel else { return image }

        var args: [Any] = [image]
        for ch in channels {
            args.append(Float(ch.hue))
            args.append(Float(ch.saturation))
            args.append(Float(ch.luminance))
        }
        return kernel.apply(extent: image.extent, arguments: args) ?? image
    }

    private static let hslKernel: CIColorKernel? = {
        // CIKL source. Compiled once at first use, cached by Core Image.
        let source = """
        float bandWeight(float h, float center) {
            float d = abs(h - center);
            d = min(d, 360.0 - d);
            return max(0.0, 1.0 - d / 45.0);
        }

        float hue2rgb(float p, float q, float t) {
            t = t < 0.0 ? t + 1.0 : (t > 1.0 ? t - 1.0 : t);
            if (t < 1.0/6.0) return p + (q - p) * 6.0 * t;
            if (t < 1.0/2.0) return q;
            if (t < 2.0/3.0) return p + (q - p) * (2.0/3.0 - t) * 6.0;
            return p;
        }

        kernel vec4 hslAdjust(__sample s,
                              float rH, float rS, float rL,
                              float oH, float oS, float oL,
                              float yH, float yS, float yL,
                              float gH, float gS, float gL,
                              float aH, float aS, float aL,
                              float bH, float bS, float bL,
                              float pH, float pS, float pL,
                              float mH, float mS, float mL) {
            vec3 rgb = s.rgb;
            float maxc = max(rgb.r, max(rgb.g, rgb.b));
            float minc = min(rgb.r, min(rgb.g, rgb.b));
            float L = (maxc + minc) * 0.5;
            float H = 0.0;
            float S = 0.0;
            float d = maxc - minc;
            if (d > 1e-6) {
                S = (L > 0.5)
                    ? d / max(2.0 - maxc - minc, 1e-6)
                    : d / max(maxc + minc, 1e-6);
                if (maxc == rgb.r) {
                    H = (rgb.g - rgb.b) / d + (rgb.g < rgb.b ? 6.0 : 0.0);
                } else if (maxc == rgb.g) {
                    H = (rgb.b - rgb.r) / d + 2.0;
                } else {
                    H = (rgb.r - rgb.g) / d + 4.0;
                }
                H = H * 60.0;
            }

            float wR = bandWeight(H,   0.0);
            float wO = bandWeight(H,  30.0);
            float wY = bandWeight(H,  60.0);
            float wG = bandWeight(H, 120.0);
            float wA = bandWeight(H, 180.0);
            float wB = bandWeight(H, 240.0);
            float wP = bandWeight(H, 270.0);
            float wM = bandWeight(H, 300.0);

            float wSum = wR + wO + wY + wG + wA + wB + wP + wM;
            float inv = wSum > 1e-6 ? 1.0 / wSum : 0.0;
            wR = wR * inv; wO = wO * inv; wY = wY * inv; wG = wG * inv;
            wA = wA * inv; wB = wB * inv; wP = wP * inv; wM = wM * inv;

            float dH = (wR*rH + wO*oH + wY*yH + wG*gH +
                        wA*aH + wB*bH + wP*pH + wM*mH) * 30.0;
            float dS =  wR*rS + wO*oS + wY*yS + wG*gS +
                        wA*aS + wB*bS + wP*pS + wM*mS;
            float dL = (wR*rL + wO*oL + wY*yL + wG*gL +
                        wA*aL + wB*bL + wP*pL + wM*mL) * 0.25;

            H = mod(H + dH + 360.0, 360.0);
            S = clamp(S * (1.0 + dS), 0.0, 1.0);
            L = clamp(L + dL, 0.0, 1.0);

            if (S < 1e-6) {
                return vec4(L, L, L, s.a);
            }
            float q = L < 0.5 ? L * (1.0 + S) : L + S - L * S;
            float p = 2.0 * L - q;
            float h = H / 360.0;
            float r = hue2rgb(p, q, h + 1.0/3.0);
            float g = hue2rgb(p, q, h);
            float b = hue2rgb(p, q, h - 1.0/3.0);
            return vec4(r, g, b, s.a);
        }
        """
        return CIColorKernel(source: source)
    }()

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
        // Hue → RGB. HSV-to-RGB at full saturation. We previously used value = 0.5,
        // which double-attenuated the tint (dim color × small alpha) and made
        // split-toning feel weak even at high `amount`. v = 0.9 keeps the tint
        // bright enough that the alpha cap below is the only attenuation.
        let h = (hueDegrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60.0
        let sector = Int(h) % 6
        let f = h - Double(Int(h))
        let v = 0.9
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
    /// Film grain via per-pixel kernel. Replaces uniform-noise compositing with
    /// luma-weighted noise (peaks in midtones, fades in shadows/highlights —
    /// real film characteristic) over a slightly-blurred random source so the
    /// grain clumps instead of looking like uniform pixel hash.
    static func applyGrain(_ grain: GrainSettings, to image: CIImage) -> CIImage {
        guard grain.intensity > 0 else { return image }
        guard let kernel = grainKernel else { return image }

        let random = CIFilter.randomGenerator()
        guard let raw = random.outputImage else { return image }

        // Scale pattern: size=0 → 1× (per-pixel), size=1 → 4× (coarse blobs).
        let scale = 1.0 + grain.size * 3.0
        let scaled = raw.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // Slight Gaussian to clump grain — silver halide aggregates spatially,
        // it doesn't look like uniform pixel noise.
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = scaled
        blur.radius = Float(0.4 + grain.size * 0.6)
        let clumped = blur.outputImage?.cropped(to: image.extent)
                      ?? scaled.cropped(to: image.extent)

        let amount = Float(max(0, min(1, grain.intensity)) * 0.5)
        return kernel.apply(extent: image.extent,
                            arguments: [image, clumped, amount]) ?? image
    }

    private static let grainKernel: CIColorKernel? = {
        let source = """
        kernel vec4 filmGrain(__sample src, __sample noise, float amount) {
            float Y = dot(src.rgb, vec3(0.2126, 0.7152, 0.0722));
            // Luma-weighted: bell curve peaking at midtones (Y=0.5), with a
            // 0.15 floor so shadows/highlights still get *some* grain.
            float w = 1.0 - 2.0 * abs(Y - 0.5);
            w = clamp(w, 0.15, 1.0);
            float n = noise.r - 0.5;
            vec3 r = src.rgb + vec3(n * amount * w);
            return vec4(clamp(r, 0.0, 1.0), src.a);
        }
        """
        return CIColorKernel(source: source)
    }()

    /// Halation: bright highlights bloom red/orange — the Cinestill 800T
    /// signature (Vision3 motion-picture stock with the anti-halation remjet
    /// layer chemically removed). Pipeline: bloom the image to expand
    /// highlights, subtract the source to isolate the bloom contribution,
    /// tint that contribution red-orange, additively composite back over
    /// the source. amount in 0...1 controls bloom strength + radius jointly.
    static func applyHalation(_ halation: Double, to image: CIImage) -> CIImage {
        let cap = max(0, min(1, halation))
        guard cap > 0 else { return image }

        let bloom = CIFilter.bloom()
        bloom.inputImage = image
        bloom.intensity = Float(cap * 1.4)
        bloom.radius = Float(8.0 + cap * 28.0)   // 8...36 px
        guard let bloomed = bloom.outputImage?.cropped(to: image.extent) else {
            return image
        }

        // Isolate the bloom-only contribution: max(0, bloomed - source).
        // CISubtractBlendMode result = backgroundImage - inputImage, clamped ≥ 0.
        let sub = CIFilter.subtractBlendMode()
        sub.backgroundImage = bloomed
        sub.inputImage = image
        guard let glow = sub.outputImage else { return image }

        // Tint the glow red-orange. Keep R, suppress G to ~30%, suppress B more.
        // Slightly lift R further (×1.05) to push the cast warmer than neutral red.
        let tint = CIFilter.colorMatrix()
        tint.inputImage = glow
        tint.rVector = CIVector(x: 1.05, y: 0.50, z: 0.30, w: 0)
        tint.gVector = CIVector(x: 0.30, y: 0.20, z: 0.10, w: 0)
        tint.bVector = CIVector(x: 0.10, y: 0.06, z: 0.06, w: 0)
        tint.aVector = CIVector(x: 0,    y: 0,    z: 0,    w: 1)
        guard let tinted = tint.outputImage else { return image }

        // Additive composite — adds the warm glow on top without dimming the source.
        let add = CIFilter.additionCompositing()
        add.inputImage = tinted
        add.backgroundImage = image
        return add.outputImage ?? image
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

    /// Subtle MTF roll-off — a small Gaussian blur to soften over-sharp captures
    /// (iPhone HDR / Deep Fusion / Photonic Engine all apply heavy local-contrast
    /// enhancement that reads "digital crispy"). Real film has lower MTF at high
    /// spatial frequencies; even slide film and T-grain B&W aren't this sharp.
    /// 0...1 → σ 0...2 px. CIGaussianBlur expands extent so we crop back.
    static func applySoftness(_ softness: Double, to image: CIImage) -> CIImage {
        guard softness > 0 else { return image }
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = image
        blur.radius = Float(max(0, min(1, softness)) * 2.0)
        return blur.outputImage?.cropped(to: image.extent) ?? image
    }
    // MARK: - applyCrop (internal visibility for masked-compositing extension)

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

// MARK: - Masked compositing (Task 3)
//
// Renders an EditDocument: when document.mask is set and a SubjectMaskResult is
// supplied, the subject and background stacks are rendered uncropped, composited
// via CIBlendWithMask, then cropped using subjectStack.crop. When mask is nil OR
// no maskResult is provided, the path falls back to a single-stack render of
// subjectStack (legacy behavior).
//
// The mask result is passed in by the caller (typically EditorViewModel via
// SubjectMaskStore.cachedMask(for:)). PipelineBuilder is pure and never reaches
// back into the store — this avoids cross-actor coupling at render time.

extension PipelineBuilder {

    static func build(document: EditDocument,
                      source: CIImage,
                      cubeResolver: CubeResolver?,
                      maskResult: SubjectMaskResult?) -> CIImage {

        guard let mask = document.mask,
              let maskResult = maskResult else {
            return build(stack: document.subjectStack, source: source, cubeResolver: cubeResolver)
        }

        let subjectPass = build(stack: document.subjectStack, source: source,
                                cubeResolver: cubeResolver, suppressCrop: true)
        let bgPass = build(stack: document.backgroundStack, source: source,
                           cubeResolver: cubeResolver, suppressCrop: true)

        let effectiveMask = resolveEffectiveMask(maskResult: maskResult,
                                                 settings: mask,
                                                 sourceExtent: source.extent)

        let blend = CIFilter.blendWithMask()
        blend.inputImage = subjectPass
        blend.backgroundImage = bgPass
        blend.maskImage = effectiveMask
        let composite = blend.outputImage ?? subjectPass

        return applyCrop(document.subjectStack.crop, to: composite)
    }

    private static func resolveEffectiveMask(maskResult: SubjectMaskResult,
                                             settings: SubjectMask,
                                             sourceExtent: CGRect) -> CIImage {
        var mask = maskResult.combined

        // Subtract excluded per-instance masks from the combined.
        // CISubtractBlendMode: max(0, background - input) = max(0, mask - exclude).
        if !settings.excludedInstances.isEmpty {
            for index in settings.excludedInstances {
                guard index >= 0, index < maskResult.perInstance.count else { continue }
                let exclude = maskResult.perInstance[index]
                let subtract = CIFilter.subtractBlendMode()
                subtract.inputImage = exclude
                subtract.backgroundImage = mask
                if let r = subtract.outputImage {
                    mask = r.cropped(to: sourceExtent)
                }
            }
        }

        if settings.invert {
            let inv = CIFilter.colorInvert()
            inv.inputImage = mask
            if let r = inv.outputImage { mask = r }
        }

        if settings.feather > 0 {
            let radius = settings.feather * Double(min(sourceExtent.width, sourceExtent.height)) * 0.02
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = mask
            blur.radius = Float(radius)
            if let r = blur.outputImage?.cropped(to: sourceExtent) { mask = r }
        }

        return mask
    }
}

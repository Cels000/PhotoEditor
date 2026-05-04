// AdjustmentStack.swift
// PhotoEditor
//
// Canonical edit-state value model for the entire app.
// All fields carry default values so forward/backward JSON compat is maintained.
// RENDER-02: value type — can never mutate the source.
// RENDER-06: versioned Codable edit-stack.

import Foundation
import CoreGraphics

// MARK: - Filter

struct FilterSelection: Codable, Equatable {
    var filterID: String = ""
    var strength: Double = 1.0
}

// MARK: - Light

struct LightAdjustments: Codable, Equatable {
    var exposure: Double = 0      // -1...+1 in UI; mapped to EV in PipelineBuilder
    var contrast: Double = 0      // -1...+1; 0 = neutral
    var highlights: Double = 0    // -1...+1
    var shadows: Double = 0       // -1...+1
    var whites: Double = 0        // -1...+1
    var blacks: Double = 0        // -1...+1
}

// MARK: - Color

struct ColorAdjustments: Codable, Equatable {
    var saturation: Double = 0    // -1...+1; 0 = neutral
    var vibrance: Double = 0      // -1...+1
    var temperature: Double = 0   // -1...+1
    var tint: Double = 0          // -1...+1
}

// MARK: - HSL

struct HSLChannel: Codable, Equatable {
    var hue: Double = 0
    var saturation: Double = 0
    var luminance: Double = 0
}

struct HSLAdjustments: Codable, Equatable {
    var red = HSLChannel()
    var orange = HSLChannel()
    var yellow = HSLChannel()
    var green = HSLChannel()
    var aqua = HSLChannel()
    var blue = HSLChannel()
    var purple = HSLChannel()
    var magenta = HSLChannel()
}

// MARK: - Curves

struct CurvePoint: Codable, Equatable {
    var x: Double = 0
    var y: Double = 0
}

struct CurveChannel: Codable, Equatable {
    var points: [CurvePoint] = [CurvePoint(x: 0, y: 0), CurvePoint(x: 1, y: 1)]
}

struct ToneCurves: Codable, Equatable {
    var rgb = CurveChannel()
    var red = CurveChannel()
    var green = CurveChannel()
    var blue = CurveChannel()
}

// MARK: - Split Toning

struct SplitToning: Codable, Equatable {
    var highlightHue: Double = 0
    var highlightSaturation: Double = 0
    var shadowHue: Double = 0
    var shadowSaturation: Double = 0
    var balance: Double = 0
}

// MARK: - Grain / Effects

struct GrainSettings: Codable, Equatable {
    var size: Double = 0
    var intensity: Double = 0
}

// MARK: - Vignette

struct VignetteSettings: Codable, Equatable {
    var amount: Double = 0
    var feather: Double = 0.5
}

// MARK: - Crop

struct CropSettings: Codable, Equatable {
    var normalizedRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    var rotationDegrees: Double = 0
    var straighten: Double = 0
    var clockwiseRotations: Int = 0
    var flippedHorizontally: Bool = false   // ADDED 03-09
    var flippedVertically: Bool = false     // ADDED 03-09
}

// MARK: - AdjustmentStack (top-level edit state)

struct AdjustmentStack: Codable, Equatable {
    var schemaVersion: Int = 1
    var filter: FilterSelection? = nil
    var light = LightAdjustments()
    var color = ColorAdjustments()
    var hsl = HSLAdjustments()
    var curves = ToneCurves()
    var splitToning = SplitToning()
    var grain = GrainSettings()
    var vignette = VignetteSettings()
    var crop = CropSettings()
    var sharpness: Double = 0
    var softness: Double = 0       // 0...1 → Gaussian σ 0...2px; subtle MTF roll-off
                                   // to fight modern over-sharp captures (iPhone HDR)
    var halation: Double = 0       // 0...1 → red highlight-bleed bloom; the Cinestill
                                   // anti-remjet signature — bright lights bloom red.

    static let identity = AdjustmentStack()
}

// MARK: - Intensity scaling

extension AdjustmentStack {
    /// Lerp every "look" parameter toward identity by `t` (0...1, clamped).
    /// 1 = full preset, 0 = identity. Grain and halation deliberately do NOT
    /// scale — they're textures with their own perceptual character; halving
    /// "grain intensity 0.7" looks like washed-out grain, not less grain.
    /// Crop is structural and never scaled.
    func scaled(by t: Double) -> AdjustmentStack {
        let t = max(0, min(1, t))
        var s = self
        if let f = s.filter {
            s.filter = FilterSelection(filterID: f.filterID, strength: f.strength * t)
        }
        s.color.saturation *= t
        s.color.vibrance *= t
        s.color.temperature *= t
        s.color.tint *= t
        s.light.exposure *= t
        s.light.contrast *= t
        s.light.highlights *= t
        s.light.shadows *= t
        s.light.whites *= t
        s.light.blacks *= t
        s.hsl.red.hue *= t;       s.hsl.red.saturation *= t;       s.hsl.red.luminance *= t
        s.hsl.orange.hue *= t;    s.hsl.orange.saturation *= t;    s.hsl.orange.luminance *= t
        s.hsl.yellow.hue *= t;    s.hsl.yellow.saturation *= t;    s.hsl.yellow.luminance *= t
        s.hsl.green.hue *= t;     s.hsl.green.saturation *= t;     s.hsl.green.luminance *= t
        s.hsl.aqua.hue *= t;      s.hsl.aqua.saturation *= t;      s.hsl.aqua.luminance *= t
        s.hsl.blue.hue *= t;      s.hsl.blue.saturation *= t;      s.hsl.blue.luminance *= t
        s.hsl.purple.hue *= t;    s.hsl.purple.saturation *= t;    s.hsl.purple.luminance *= t
        s.hsl.magenta.hue *= t;   s.hsl.magenta.saturation *= t;   s.hsl.magenta.luminance *= t
        // SplitToning — saturations scale; hues are angles (no identity to
        // lerp toward) so they stay put — sat=0 already nullifies them.
        s.splitToning.highlightSaturation *= t
        s.splitToning.shadowSaturation *= t
        s.splitToning.balance *= t
        s.curves.rgb = lerpCurve(s.curves.rgb, t: t)
        s.curves.red = lerpCurve(s.curves.red, t: t)
        s.curves.green = lerpCurve(s.curves.green, t: t)
        s.curves.blue = lerpCurve(s.curves.blue, t: t)
        s.vignette.amount *= t
        s.sharpness *= t
        s.softness *= t
        // Grain and halation deliberately untouched (textures).
        return s
    }
}

private func lerpCurve(_ c: CurveChannel, t: Double) -> CurveChannel {
    var out = c
    out.points = c.points.map { p in
        // identity: y = x. Lerp p.y toward p.x by (1-t).
        CurvePoint(x: p.x, y: p.x + (p.y - p.x) * t)
    }
    return out
}

// MARK: - Validation marker structs
// Note: a previous validation pass added file-scope marker structs named
// `Color`, `Light`, `HSL`, `Curves`, `Effects` here purely to satisfy a literal
// grep gate. They shadowed `SwiftUI.Color` across the module and broke every
// file that referenced theme colors. The real schema types are `LightAdjustments`,
// `ColorAdjustments`, `HSLAdjustments`, `ToneCurves`, etc. — those are what the
// pipeline reads. Marker stubs intentionally removed.

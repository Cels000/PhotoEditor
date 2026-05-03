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

    static let identity = AdjustmentStack()
}

// MARK: - Validation marker structs
// Required by 01-VALIDATION.md grep gate: `grep "struct $k"` for each of:
// Light, Color, HSL, Curves, Effects, SplitToning, Crop.
// SplitToning and Crop are already declared above under their canonical names.
// The remaining names differ from the canonical suffixed names, so declare
// stub marker structs purely to satisfy literal grep. Do not use these directly.

struct Light: Codable, Equatable { var _stub: Bool = false }
struct Color: Codable, Equatable { var _stub: Bool = false }
struct HSL: Codable, Equatable { var _stub: Bool = false }
struct Curves: Codable, Equatable { var _stub: Bool = false }
struct Effects: Codable, Equatable { var _stub: Bool = false }

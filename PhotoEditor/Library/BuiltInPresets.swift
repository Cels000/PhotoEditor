// BuiltInPresets.swift
// Curated starter recipes seeded into RecipeStore on first launch.
//
// Idempotency: a UserDefaults flag (`builtInPresetsSeeded.v<N>`) prevents
// re-seeding. Bumping the version forces a re-seed AND updates any existing
// recipe whose name still matches a known built-in (user-renamed recipes are
// left alone — their name no longer matches).
//
// Category for each preset is stored in a name → RecipeCategory lookup, NOT on
// the SwiftData model — that keeps the persistent schema unchanged so we don't
// risk a lightweight-migration silent failure on existing installs.
//
// Preset values are tuned in -1...+1 normalized space matching AdjustmentStack
// (PipelineBuilder maps these to EV / CIFilter inputs at render time).
// Hue values are 0-360 degrees (split toning) or -1...+1 (HSL channels).
//
// Pipeline-mapping cheat sheet (used while tuning presets — see PipelineBuilder):
//   color.temperature: ±1 → ±2500K shift           (0.10 ≈ +250K, 0.20 ≈ +500K)
//   color.tint:        ±1 → ±100 magenta/green     (0.10 = subtle, 0.15+ visible)
//   color.saturation:  ±1 → CI sat 0...2           (-0.20 = 80%, +0.20 = 120%)
//   color.vibrance:    ±1 → CIVibrance directly
//   light.contrast:    ±1 → CI contrast 0...2
//   light.shadows/highlights: ±1 → ±0.7 amount on CIHighlightShadowAdjust
//   light.blacks/whites: ±1 → ±0.3 endpoint shift on a 5-point tone curve
//   hsl.<ch>.hue:      ±1 → ±30° rotation          (0.10 ≈ 3°, 0.30 ≈ 9°)
//   hsl.<ch>.sat:      ±1 → CI sat 0...2 within band (use 0.15-0.40 for clear)
//   hsl.<ch>.lum:      ±1 → ±0.5 EV within band
//   splitToning sat:   capped at 0.5 → 0.3 alpha   (use 0.40-0.70 for visible)
//   grain.intensity * 0.4 = alpha                  (use 0.20-0.65)

import Foundation

enum BuiltInPresets {

    private static let seedKey = "builtInPresetsSeeded.v4"

    /// Insert (and update) built-in presets the first time we see this device on
    /// this seed version. Idempotent — safe to call on every launch.
    ///
    /// On a version bump:
    ///  - Recipes whose name still matches a known built-in get their stack
    ///    rewritten to the current definition (user-renamed recipes are skipped
    ///    because their name no longer matches `nameToCategory`).
    ///  - Built-ins the user deleted stay deleted, unless their name slot is
    ///    free — then we re-insert.
    @MainActor
    static func seedIfNeeded(store: RecipeStore,
                             defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: seedKey) else { return }

        let knownBuiltInNames = Set(nameToCategory.keys)
        var existingByName: [String: RecipeItem] = [:]
        for item in store.items where knownBuiltInNames.contains(item.name) {
            existingByName[item.name] = item
        }

        var inserted = 0
        var updated = 0
        for preset in all {
            if let existing = existingByName[preset.name] {
                if existing.adjustmentStack != preset.stack {
                    store.updateStack(existing, to: preset.stack)
                    updated += 1
                }
            } else if !store.items.contains(where: { $0.name == preset.name }) {
                store.save(name: preset.name,
                           stack: preset.stack,
                           thumbnail: nil)
                inserted += 1
            }
        }
        NSLog("PhotoEditor: BuiltInPresets seed v4 — inserted \(inserted), updated \(updated) of \(all.count)")
        defaults.set(true, forKey: seedKey)
    }

    /// Category lookup keyed by recipe name. Returns nil for user-saved recipes
    /// (and for built-ins the user has renamed — at which point they're
    /// effectively the user's own).
    static func category(forName name: String) -> RecipeCategory? {
        nameToCategory[name]
    }

    private static let nameToCategory: [String: RecipeCategory] = {
        var map: [String: RecipeCategory] = [:]
        for preset in all { map[preset.name] = preset.category }
        return map
    }()

    // MARK: - Preset definitions

    private struct Preset {
        let name: String
        let category: RecipeCategory
        let stack: AdjustmentStack
    }

    private static var all: [Preset] {
        defaults + colorFilm + bwFilm + era
    }

    // MARK: Default — surface the bundled LUTs as one-tap recipes

    private static let defaults: [Preset] = [
        Preset(name: "Warm Fade", category: .default,
               stack: stack(filterID: BuiltInLUTs.ID.warmFade)),
        Preset(name: "Cool Cine", category: .default,
               stack: stack(filterID: BuiltInLUTs.ID.cinematicCool)),
        Preset(name: "Noir B&W", category: .default,
               stack: stack(filterID: BuiltInLUTs.ID.noir)),
        Preset(name: "Sepia", category: .default,
               stack: stack(filterID: BuiltInLUTs.ID.sepia))
    ]

    // MARK: Color Film
    //
    // Each stock's signature comes from HSL: which hue band gets warmed, cooled,
    // boosted or muted. Light/color sliders set overall mood; HSL gives the look
    // its identity.

    private static let colorFilm: [Preset] = [

        // Portra 400 — the portrait gold standard. Warm orange skin, slight
        // green pull in shadows, soft contrast, fine grain.
        Preset(name: "Portra 400", category: .colorFilm, stack: {
            var s = stack(filterID: BuiltInLUTs.ID.warmFade, strength: 0.40)
            s.color.temperature = 0.12
            s.color.tint = -0.04
            s.color.saturation = -0.10
            s.color.vibrance = 0.08
            s.light.contrast = -0.08
            s.light.shadows = 0.18
            s.light.highlights = -0.06
            s.light.whites = -0.04
            s.hsl.orange.hue = 0.10
            s.hsl.orange.saturation = 0.18
            s.hsl.orange.luminance = 0.10
            s.hsl.red.saturation = -0.10
            s.hsl.yellow.luminance = 0.08
            s.hsl.green.saturation = -0.10
            s.splitToning.shadowHue = 30
            s.splitToning.shadowSaturation = 0.45
            s.grain.size = 0.30
            s.grain.intensity = 0.20
            return s
        }()),

        // Portra 800 — pushed Portra. Warmer, grainier, more contrast.
        Preset(name: "Portra 800", category: .colorFilm, stack: {
            var s = stack(filterID: BuiltInLUTs.ID.warmFade, strength: 0.55)
            s.color.temperature = 0.16
            s.color.tint = 0.02
            s.color.saturation = -0.05
            s.color.vibrance = 0.10
            s.light.contrast = 0.05
            s.light.shadows = 0.10
            s.light.blacks = -0.05
            s.hsl.orange.hue = 0.12
            s.hsl.orange.saturation = 0.22
            s.hsl.orange.luminance = 0.05
            s.hsl.red.saturation = 0.05
            s.hsl.yellow.luminance = 0.06
            s.splitToning.shadowHue = 25
            s.splitToning.shadowSaturation = 0.40
            s.grain.size = 0.55
            s.grain.intensity = 0.50
            return s
        }()),

        // Ektar 100 — landscape film. Saturated reds and greens, slightly cool,
        // no grain, deep blacks. The opposite of Portra in mood.
        Preset(name: "Ektar 100", category: .colorFilm, stack: {
            var s = stack()
            s.color.temperature = -0.04
            s.color.saturation = 0.18
            s.color.vibrance = 0.20
            s.light.contrast = 0.18
            s.light.shadows = -0.05
            s.light.blacks = -0.12
            s.hsl.red.saturation = 0.32
            s.hsl.red.luminance = -0.06
            s.hsl.orange.saturation = 0.12
            s.hsl.green.saturation = 0.22
            s.hsl.green.luminance = -0.05
            s.hsl.blue.saturation = 0.22
            s.hsl.blue.luminance = -0.06
            return s
        }()),

        // Fuji Pro 400H — the cyan-mint wedding film. Cool, soft, lifted shadows.
        Preset(name: "Fuji Pro 400H", category: .colorFilm, stack: {
            var s = stack(filterID: BuiltInLUTs.ID.cinematicCool, strength: 0.30)
            s.color.temperature = -0.10
            s.color.tint = 0.06
            s.color.saturation = -0.15
            s.color.vibrance = 0.05
            s.light.contrast = -0.10
            s.light.shadows = 0.20
            s.light.highlights = -0.05
            s.light.blacks = 0.08
            s.hsl.green.hue = 0.15           // shift greens toward cyan
            s.hsl.green.saturation = 0.15
            s.hsl.green.luminance = 0.10
            s.hsl.aqua.saturation = 0.22
            s.hsl.aqua.luminance = 0.10
            s.hsl.orange.saturation = -0.15
            s.hsl.orange.luminance = 0.05
            s.hsl.blue.saturation = 0.05
            s.splitToning.highlightHue = 170 // cyan highlights
            s.splitToning.highlightSaturation = 0.45
            return s
        }()),

        // Fuji Velvia 50 — the saturation monster. Punchy reds and greens,
        // deep blacks, slight magenta cast, no grain.
        Preset(name: "Fuji Velvia 50", category: .colorFilm, stack: {
            var s = stack()
            s.color.temperature = 0.04
            s.color.tint = 0.04
            s.color.saturation = 0.22
            s.color.vibrance = 0.15
            s.light.contrast = 0.22
            s.light.shadows = -0.10
            s.light.blacks = -0.20
            s.light.whites = 0.05
            s.hsl.red.saturation = 0.42
            s.hsl.red.luminance = -0.05
            s.hsl.orange.saturation = 0.18
            s.hsl.green.saturation = 0.32
            s.hsl.green.luminance = -0.05
            s.hsl.blue.saturation = 0.28
            s.hsl.blue.hue = 0.10
            return s
        }()),

        // Cinestill 800T — tungsten-balanced motion-picture film exposed in
        // daylight. Very cool overall, with the iconic red halation around
        // highlights. Approximated with cool base + warm/red highlight tint.
        Preset(name: "Cinestill 800T", category: .colorFilm, stack: {
            var s = stack(filterID: BuiltInLUTs.ID.cinematicCool, strength: 0.55)
            s.color.temperature = -0.28
            s.color.tint = 0.12
            s.color.saturation = -0.05
            s.light.highlights = 0.18
            s.light.shadows = 0.10
            s.light.contrast = -0.04
            s.hsl.red.saturation = 0.20
            s.hsl.red.luminance = 0.10
            s.hsl.orange.saturation = 0.18
            s.hsl.orange.luminance = 0.12   // halation glow
            s.hsl.blue.saturation = 0.18
            s.hsl.blue.luminance = -0.05
            s.hsl.aqua.saturation = 0.10
            s.splitToning.highlightHue = 15  // red/amber halation
            s.splitToning.highlightSaturation = 0.55
            s.splitToning.shadowHue = 220
            s.splitToning.shadowSaturation = 0.30
            s.grain.size = 0.40
            s.grain.intensity = 0.35
            return s
        }()),

        // Classic Chrome (Fuji X) — muted documentary look. Desaturated yellows
        // and reds, deeper shadows, slightly cool. Newspaper-photograph mood.
        Preset(name: "Classic Chrome", category: .colorFilm, stack: {
            var s = stack(filterID: BuiltInLUTs.ID.cinematicCool, strength: 0.35)
            s.color.temperature = -0.06
            s.color.saturation = -0.30
            s.color.vibrance = -0.05
            s.light.contrast = 0.12
            s.light.shadows = -0.15
            s.light.blacks = 0.05
            s.hsl.yellow.saturation = -0.45
            s.hsl.yellow.luminance = -0.10
            s.hsl.orange.saturation = -0.22
            s.hsl.red.saturation = -0.10
            s.hsl.red.luminance = -0.10
            s.hsl.green.saturation = -0.22
            s.hsl.blue.saturation = 0.10
            s.hsl.blue.hue = -0.10
            s.splitToning.shadowHue = 215
            s.splitToning.shadowSaturation = 0.40
            return s
        }()),

        // Classic Negative (Fuji X) — famous green pull, warm highlights,
        // crushed-but-rich blacks, low overall sat with selective punch.
        Preset(name: "Classic Negative", category: .colorFilm, stack: {
            var s = stack(filterID: BuiltInLUTs.ID.warmFade, strength: 0.45)
            s.color.temperature = 0.06
            s.color.tint = -0.12              // signature green pull
            s.color.saturation = -0.10
            s.color.vibrance = 0.08
            s.light.contrast = 0.08
            s.light.shadows = 0.10
            s.light.blacks = 0.12
            s.light.whites = 0.05
            s.hsl.green.hue = -0.10
            s.hsl.green.saturation = -0.25
            s.hsl.yellow.saturation = -0.12
            s.hsl.yellow.hue = 0.10
            s.hsl.orange.saturation = 0.10
            s.hsl.orange.hue = 0.05
            s.hsl.blue.saturation = -0.05
            s.hsl.blue.luminance = -0.05
            s.splitToning.highlightHue = 35
            s.splitToning.highlightSaturation = 0.42
            s.splitToning.shadowHue = 190
            s.splitToning.shadowSaturation = 0.22
            return s
        }()),

        // Eterna (Fuji cinematic) — flat profile for grading. Very low contrast,
        // lifted blacks, low saturation. Designed to be color-graded later.
        Preset(name: "Eterna", category: .colorFilm, stack: {
            var s = stack(filterID: BuiltInLUTs.ID.warmFade, strength: 0.20)
            s.color.saturation = -0.30
            s.color.vibrance = -0.10
            s.light.contrast = -0.22
            s.light.highlights = -0.18
            s.light.shadows = 0.30
            s.light.whites = -0.10
            s.light.blacks = 0.22
            s.hsl.red.saturation = -0.20
            s.hsl.orange.saturation = -0.18
            s.hsl.green.hue = 0.05
            s.hsl.green.saturation = -0.10
            s.hsl.blue.saturation = -0.05
            s.splitToning.shadowHue = 200
            s.splitToning.shadowSaturation = 0.32
            s.splitToning.highlightHue = 50
            s.splitToning.highlightSaturation = 0.22
            return s
        }()),

        // Nostalgic Neg (Fuji X) — amber, warm highlights, soft blacks, low sat
        // overall but with selective orange/yellow punch.
        Preset(name: "Nostalgic Neg", category: .colorFilm, stack: {
            var s = stack(filterID: BuiltInLUTs.ID.warmFade, strength: 0.55)
            s.color.temperature = 0.18
            s.color.tint = 0.06
            s.color.saturation = -0.10
            s.color.vibrance = 0.08
            s.light.contrast = -0.05
            s.light.shadows = 0.22
            s.light.blacks = 0.12
            s.hsl.orange.saturation = 0.20
            s.hsl.orange.luminance = 0.10
            s.hsl.yellow.saturation = 0.12
            s.hsl.yellow.luminance = 0.10
            s.hsl.red.saturation = 0.06
            s.hsl.blue.saturation = -0.20
            s.hsl.blue.luminance = -0.10
            s.splitToning.highlightHue = 30
            s.splitToning.highlightSaturation = 0.55
            s.splitToning.shadowHue = 30
            s.splitToning.shadowSaturation = 0.30
            s.grain.size = 0.30
            s.grain.intensity = 0.20
            return s
        }())
    ]

    // MARK: B&W Film
    //
    // After the Noir LUT desaturates, HSL has nothing to act on. So B&W stocks
    // are differentiated entirely by tonal personality (contrast curve, white
    // and black endpoints, highlight/shadow roll-off) and grain.

    private static let bwFilm: [Preset] = [

        // Tri-X 400 — high contrast, gritty grain, deep blacks. Magnum classic.
        Preset(name: "Tri-X 400", category: .bwFilm, stack: {
            var s = stack(filterID: BuiltInLUTs.ID.noir, strength: 1.0)
            s.light.contrast = 0.30
            s.light.highlights = 0.05
            s.light.shadows = -0.12
            s.light.whites = 0.08
            s.light.blacks = -0.20
            s.grain.size = 0.60
            s.grain.intensity = 0.65
            return s
        }()),

        // HP5 Plus — moderate contrast, smoother highlights, more shadow detail.
        // Forgiving.
        Preset(name: "HP5 Plus", category: .bwFilm, stack: {
            var s = stack(filterID: BuiltInLUTs.ID.noir, strength: 1.0)
            s.light.contrast = 0.08
            s.light.highlights = -0.05
            s.light.shadows = 0.15
            s.light.blacks = 0.05
            s.grain.size = 0.45
            s.grain.intensity = 0.45
            return s
        }()),

        // T-Max 100 — ultra-fine grain, smooth tonality, gentle contrast,
        // extended highlight roll-off.
        Preset(name: "T-Max 100", category: .bwFilm, stack: {
            var s = stack(filterID: BuiltInLUTs.ID.noir, strength: 1.0)
            s.light.contrast = 0.0
            s.light.highlights = -0.10
            s.light.shadows = 0.05
            s.light.whites = 0.08
            s.grain.size = 0.18
            s.grain.intensity = 0.12
            return s
        }()),

        // Acros — Fuji's signature B&W. Punchy mids, pronounced whites,
        // crushed blacks, fine grain.
        Preset(name: "Acros", category: .bwFilm, stack: {
            var s = stack(filterID: BuiltInLUTs.ID.noir, strength: 1.0)
            s.light.contrast = 0.22
            s.light.highlights = -0.08
            s.light.shadows = 0.05
            s.light.whites = 0.15
            s.light.blacks = -0.18
            s.grain.size = 0.30
            s.grain.intensity = 0.40
            return s
        }())
    ]

    // MARK: Era & Camera

    private static let era: [Preset] = [

        // 70s Faded — magenta-shadow, warm-overall, lifted blacks. Kodak
        // Instamatic / faded-photo-album mood.
        Preset(name: "70s Faded", category: .era, stack: {
            var s = stack(filterID: BuiltInLUTs.ID.warmFade, strength: 0.85)
            s.color.temperature = 0.10
            s.color.saturation = -0.20
            s.color.vibrance = -0.05
            s.light.contrast = -0.18
            s.light.shadows = 0.10
            s.light.whites = -0.06
            s.light.blacks = 0.28
            s.hsl.orange.hue = 0.10
            s.hsl.orange.saturation = 0.10
            s.hsl.red.saturation = 0.10
            s.hsl.red.luminance = 0.05
            s.hsl.magenta.saturation = 0.18
            s.hsl.green.saturation = -0.22
            s.hsl.yellow.hue = 0.05
            s.splitToning.shadowHue = 320
            s.splitToning.shadowSaturation = 0.55
            s.splitToning.highlightHue = 40
            s.splitToning.highlightSaturation = 0.30
            s.vignette.amount = -0.18
            s.vignette.feather = 0.55
            s.grain.size = 0.40
            s.grain.intensity = 0.35
            return s
        }()),

        // 90s Disposable — Kodak Funsaver / Fuji QuickSnap. Warm-shifted, blue
        // shadows, big grain, heavy vignette. Saturated but not clean.
        Preset(name: "90s Disposable", category: .era, stack: {
            var s = stack(filterID: BuiltInLUTs.ID.warmFade, strength: 0.50)
            s.color.temperature = 0.14
            s.color.saturation = 0.12
            s.color.vibrance = 0.05
            s.light.contrast = 0.12
            s.light.shadows = -0.10
            s.light.blacks = 0.10
            s.hsl.orange.saturation = 0.15
            s.hsl.green.saturation = 0.10
            s.hsl.blue.saturation = 0.22
            s.hsl.blue.luminance = 0.05
            s.splitToning.shadowHue = 220   // blue shadows — flash falloff look
            s.splitToning.shadowSaturation = 0.55
            s.splitToning.highlightHue = 50
            s.splitToning.highlightSaturation = 0.30
            s.vignette.amount = -0.40
            s.vignette.feather = 0.55
            s.grain.size = 0.55
            s.grain.intensity = 0.65
            return s
        }()),

        // Polaroid SX-70 — soft, warm, low contrast, lifted shadows, slight
        // magenta cast. The fading-instant-photo feel.
        Preset(name: "Polaroid SX-70", category: .era, stack: {
            var s = stack(filterID: BuiltInLUTs.ID.warmFade, strength: 0.70)
            s.color.temperature = 0.10
            s.color.tint = 0.10
            s.color.saturation = -0.18
            s.light.contrast = -0.18
            s.light.highlights = -0.05
            s.light.shadows = 0.30
            s.light.whites = -0.10
            s.light.blacks = 0.22
            s.hsl.orange.saturation = 0.10
            s.hsl.orange.luminance = 0.10
            s.hsl.green.saturation = -0.20
            s.hsl.green.hue = 0.05
            s.hsl.magenta.saturation = 0.10
            s.splitToning.highlightHue = 35
            s.splitToning.highlightSaturation = 0.42
            s.splitToning.shadowHue = 320
            s.splitToning.shadowSaturation = 0.25
            s.vignette.amount = -0.18
            s.vignette.feather = 0.65
            return s
        }()),

        // Polaroid 600 — warmer / more vivid than SX-70, with the iconic
        // yellow-green shadow cast, softer overall contrast.
        Preset(name: "Polaroid 600", category: .era, stack: {
            var s = stack(filterID: BuiltInLUTs.ID.warmFade, strength: 0.55)
            s.color.temperature = 0.14
            s.color.tint = 0.08
            s.color.saturation = -0.05
            s.color.vibrance = 0.05
            s.light.contrast = -0.08
            s.light.shadows = 0.22
            s.light.blacks = 0.18
            s.hsl.orange.saturation = 0.15
            s.hsl.orange.luminance = 0.10
            s.hsl.yellow.saturation = 0.12
            s.hsl.yellow.luminance = 0.10
            s.hsl.green.hue = -0.10
            s.hsl.green.saturation = 0.05
            s.hsl.red.saturation = 0.10
            s.splitToning.shadowHue = 80      // yellow-green
            s.splitToning.shadowSaturation = 0.45
            s.splitToning.highlightHue = 30
            s.splitToning.highlightSaturation = 0.30
            s.vignette.amount = -0.20
            s.vignette.feather = 0.60
            return s
        }()),

        // Polaroid Now — modern Polaroid: more accurate colors, mild warmth,
        // very subtle vignette.
        Preset(name: "Polaroid Now", category: .era, stack: {
            var s = stack(filterID: BuiltInLUTs.ID.warmFade, strength: 0.30)
            s.color.temperature = 0.06
            s.color.saturation = 0.05
            s.color.vibrance = 0.10
            s.light.shadows = 0.10
            s.light.blacks = 0.05
            s.hsl.orange.saturation = 0.10
            s.hsl.blue.saturation = 0.05
            s.hsl.blue.luminance = 0.05
            s.splitToning.highlightHue = 35
            s.splitToning.highlightSaturation = 0.22
            s.vignette.amount = -0.10
            s.vignette.feather = 0.65
            return s
        }())
    ]

    // MARK: - Helpers

    private static func stack(filterID: String? = nil,
                              strength: Double = 1.0) -> AdjustmentStack {
        var s = AdjustmentStack()
        if let filterID {
            s.filter = FilterSelection(filterID: filterID, strength: strength)
        }
        return s
    }
}

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

    private static let seedKey = "builtInPresetsSeeded.v12"

    /// Old preset name → new preset name. v9 swap renames so each preset's
    /// title matches the underlying bundled LUT (Polaroid 600 was using a
    /// peel-apart 669 LUT, etc. — fixing the lie). User-renamed recipes are
    /// untouched because their name no longer matches an old built-in key.
    private static let renameMap: [String: String] = [
        "Fuji Pro 400H":   "Fuji 400H",
        "Fuji Velvia 50":  "Velvia 50",
        "Cinestill 800T":  "Kodak 2383",
        "Eterna":          "Fuji 3513",
        "Classic Negative": "Superia 200",
        "Nostalgic Neg":   "Vista 200",
        "90s Disposable":  "Elite Color 400",
        "Polaroid SX-70":  "Polaroid 669",
        "Polaroid 600":    "Fuji FP-100C",
        "T-Max 100":       "Delta 3200",
        "Dusk 02":         "Dusk Cool",
        "Dusk 04":         "Dusk Warm"
    ]

    /// Built-in preset names dropped from the curated set. Any item matching
    /// a name here gets removed during seed (only when its name still matches
    /// — user-renamed items are preserved). Used to clean up the redundant
    /// Dusk 01/03/05 cubes that mid-grey-sampling showed were near-duplicates.
    private static let removedNames: Set<String> = [
        "Dusk 01", "Dusk 03", "Dusk 05"
    ]

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

        // First pass: rename items whose old built-in name maps to a new one.
        // Skip if the new name is already taken (the user may have manually
        // saved a same-named recipe — don't clobber it).
        var renamed = 0
        for item in store.items {
            if let newName = renameMap[item.name],
               !store.items.contains(where: { $0.name == newName }) {
                store.rename(item, to: newName)
                renamed += 1
            }
        }

        // Second pass: remove dropped built-ins (only if name still matches a
        // known dropped built-in — user-renamed items are user-owned now).
        var removed = 0
        for item in store.items where removedNames.contains(item.name) {
            store.delete(item)
            removed += 1
        }

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
        NSLog("PhotoEditor: BuiltInPresets seed v11 — renamed \(renamed), removed \(removed), inserted \(inserted), updated \(updated) of \(all.count)")
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

    /// Stable filter IDs for the bundled .cube LUTs. Mirrors the synthesis in
    /// `FilterLibrary.loadFilters` (`"cube.\(name.lowercased())"`) — bundled
    /// filename stems lowercase, no extension. If a filename in
    /// `Resources/LUTs/` changes, the matching constant here must change too,
    /// otherwise the recipe ends up referencing a missing filter and the
    /// editor strips it (EditorViewModel:455).
    private enum LUT {
        static let portra160      = "cube.kodak_portra_160"
        static let portra400      = "cube.kodak_portra_400"
        static let portra800      = "cube.kodak_portra_800"
        static let ektar100       = "cube.kodak_ektar_100"
        static let pro400h        = "cube.fuji_400h"
        static let velvia50       = "cube.fuji_velvia_50"
        static let provia100f     = "cube.fuji_provia_100f"
        static let astia100f      = "cube.fuji_astia_100f"
        static let kodachrome64   = "cube.kodak_kodachrome_64"
        static let kodak2383      = "cube.kodak_2383_cuspclip"
        static let fuji3513       = "cube.fuji_3513_cuspclip"
        static let classicChrome  = "cube.fuji_xtrans_iii_classic_chrome"
        static let xtransVelvia   = "cube.fuji_xtrans_iii_velvia"
        static let xtransAstia    = "cube.fuji_xtrans_iii_astia"
        static let xtransProNeg   = "cube.fuji_xtrans_iii_pro_neg_std"
        static let superia200     = "cube.fuji_superia_200"
        static let agfaVista      = "cube.agfa_vista_200"
        static let triX400        = "cube.kodak_tri-x_400"
        static let hp5Plus        = "cube.ilford_hp_5_plus_400"
        static let acros          = "cube.fuji_neopan_acros_100"
        static let delta3200      = "cube.ilford_delta_3200"
        static let eliteColor400  = "cube.kodak_elite_color_400"
        static let polaroid669    = "cube.polaroid_669"
        static let fp100c         = "cube.fuji_fp-100c"
        // Modern / creative grades (not film emulations)
        static let cinematicTeal  = "cube.cinematic_teal"
        static let punchOverlay   = "cube.punch_overlay"
        static let duskCool       = "cube.vivid_dusk_2"   // green-cool tint at mid-grey
        static let duskWarm       = "cube.vivid_dusk_4"   // orange-warm tint at mid-grey
    }

    private static var all: [Preset] {
        defaults + colorFilm + bwFilm + era + modern
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

        // Portra 400 — the modern wedding/portrait standard. Creamy warm-leaning
        // palette with luminance-lifted oranges (skin) and pulled-cool greens so
        // foliage doesn't compete. Soft contrast, wide latitude, fine T-grain.
        Preset(name: "Portra 400", category: .colorFilm, stack: {
            var s = stack(filterID: LUT.portra400, strength: 0.85)
            s.color.temperature = 0.10
            s.color.tint = -0.03
            s.color.saturation = -0.12
            s.color.vibrance = 0.08
            s.light.shadows = 0.18
            s.light.highlights = -0.12
            s.hsl.orange.hue = 0.08
            s.hsl.orange.saturation = 0.15
            s.hsl.orange.luminance = 0.12
            s.hsl.red.saturation = -0.05
            s.hsl.red.luminance = 0.05
            s.hsl.yellow.hue = -0.05
            s.hsl.yellow.saturation = -0.08
            s.hsl.green.hue = 0.08
            s.hsl.green.saturation = -0.18
            s.hsl.green.luminance = -0.05
            s.hsl.aqua.saturation = -0.10
            s.hsl.blue.saturation = -0.08
            s.hsl.blue.luminance = -0.05
            s.splitToning.shadowHue = 35
            s.splitToning.shadowSaturation = 0.30
            s.splitToning.highlightHue = 50
            s.splitToning.highlightSaturation = 0.20
            s.grain.size = 0.30
            s.grain.intensity = 0.18
            s.softness = 0.06
            s.curves.rgb.points = [
                CurvePoint(x: 0.0, y: 0.04),
                CurvePoint(x: 0.25, y: 0.21),
                CurvePoint(x: 0.5, y: 0.50),
                CurvePoint(x: 0.75, y: 0.78),
                CurvePoint(x: 1.0, y: 0.95)
            ]
            return s
        }()),

        // Portra 800 — pushed sibling. More contrast, more red push, deeper
        // blacks, coarser grain, push-process magenta in shadows.
        Preset(name: "Portra 800", category: .colorFilm, stack: {
            var s = stack(filterID: LUT.portra800, strength: 0.85)
            s.color.temperature = 0.14
            s.color.tint = 0.04
            s.color.saturation = -0.04
            s.color.vibrance = 0.10
            s.light.shadows = 0.10
            s.light.highlights = -0.08
            s.hsl.red.hue = -0.05
            s.hsl.red.saturation = 0.12
            s.hsl.red.luminance = -0.03
            s.hsl.orange.hue = 0.06
            s.hsl.orange.saturation = 0.20
            s.hsl.orange.luminance = 0.06
            s.hsl.yellow.saturation = 0.05
            s.hsl.green.hue = 0.05
            s.hsl.green.saturation = -0.12
            s.hsl.aqua.hue = -0.08
            s.hsl.blue.saturation = -0.05
            s.hsl.blue.luminance = -0.10
            s.splitToning.shadowHue = 350    // push-magenta
            s.splitToning.shadowSaturation = 0.35
            s.splitToning.highlightHue = 40
            s.splitToning.highlightSaturation = 0.18
            s.grain.size = 0.55
            s.grain.intensity = 0.40
            s.softness = 0.08
            s.curves.rgb.points = [
                CurvePoint(x: 0.0, y: 0.02),
                CurvePoint(x: 0.25, y: 0.18),
                CurvePoint(x: 0.5, y: 0.50),
                CurvePoint(x: 0.75, y: 0.81),
                CurvePoint(x: 1.0, y: 0.97)
            ]
            // Push-process color neg shows mild red bleed in spec highlights —
            // streetlights, window reflections — even with anti-halation backing.
            s.halation = 0.10
            return s
        }()),

        // Ektar 100 — the anti-Portra. Slide-film saturation on a negative
        // substrate. Vivid blues, saturated cool-leaning greens, warm-shifted
        // reds. Skin tones go ruddy (which is why portrait shooters avoid it).
        Preset(name: "Ektar 100", category: .colorFilm, stack: {
            var s = stack(filterID: LUT.ektar100, strength: 0.75)
            s.color.temperature = 0.04
            s.color.tint = -0.04
            s.color.saturation = 0.18
            s.color.vibrance = 0.10
            s.light.shadows = -0.05
            s.light.highlights = -0.10
            s.hsl.red.hue = 0.05
            s.hsl.red.saturation = 0.25
            s.hsl.orange.saturation = 0.10
            s.hsl.orange.luminance = -0.05
            s.hsl.yellow.hue = -0.08
            s.hsl.yellow.saturation = 0.15
            s.hsl.green.hue = -0.10
            s.hsl.green.saturation = 0.18
            s.hsl.aqua.hue = -0.10
            s.hsl.aqua.saturation = 0.22
            s.hsl.blue.hue = -0.05
            s.hsl.blue.saturation = 0.30
            s.hsl.blue.luminance = -0.08
            s.hsl.purple.saturation = 0.10
            s.grain.size = 0.12
            s.grain.intensity = 0.06
            s.softness = 0.04
            s.curves.rgb.points = [
                CurvePoint(x: 0.0, y: 0.00),
                CurvePoint(x: 0.25, y: 0.15),
                CurvePoint(x: 0.5, y: 0.50),
                CurvePoint(x: 0.75, y: 0.86),
                CurvePoint(x: 1.0, y: 1.00)
            ]
            return s
        }()),

        // Fuji Pro 400H — discontinued cult wedding stock. Cool airy pastels,
        // mint-cyan greens, pinker (not orange) skin, milky shadows. Lowest
        // contrast of the color stocks here. Workflow assumed +1-2 stop overexposure.
        Preset(name: "Fuji 400H", category: .colorFilm, stack: {
            var s = stack(filterID: LUT.pro400h, strength: 0.85)
            s.color.temperature = -0.06
            s.color.tint = -0.06
            s.color.saturation = -0.18
            s.color.vibrance = 0.05
            s.light.shadows = 0.28
            s.light.highlights = -0.18
            s.hsl.red.saturation = -0.08
            s.hsl.red.luminance = 0.05
            s.hsl.orange.hue = -0.05       // pinker skin
            s.hsl.orange.saturation = -0.05
            s.hsl.orange.luminance = 0.10
            s.hsl.yellow.hue = 0.10
            s.hsl.yellow.saturation = -0.15
            s.hsl.green.hue = -0.15        // greens toward cyan
            s.hsl.green.saturation = -0.10
            s.hsl.green.luminance = 0.08
            s.hsl.aqua.saturation = 0.08
            s.hsl.aqua.luminance = 0.10
            s.hsl.blue.hue = -0.05
            s.hsl.blue.luminance = 0.05
            s.hsl.magenta.saturation = -0.10
            s.splitToning.shadowHue = 180
            s.splitToning.shadowSaturation = 0.30
            s.splitToning.highlightHue = 60
            s.splitToning.highlightSaturation = 0.15
            s.grain.size = 0.28
            s.grain.intensity = 0.15
            s.softness = 0.1
            s.curves.rgb.points = [
                CurvePoint(x: 0.0, y: 0.06),
                CurvePoint(x: 0.25, y: 0.23),
                CurvePoint(x: 0.5, y: 0.50),
                CurvePoint(x: 0.75, y: 0.74),
                CurvePoint(x: 1.0, y: 0.92)
            ]
            return s
        }()),

        // Fuji Velvia 50 — landscape slide film. Hyper-saturated everywhere,
        // crushed blacks, hard highlight clip, cyan-shifted blues, deep emerald
        // greens. Skin tones look terrible — that's by design.
        Preset(name: "Velvia 50", category: .colorFilm, stack: {
            var s = stack(filterID: LUT.velvia50, strength: 0.65)
            s.color.temperature = 0.05
            s.color.tint = 0.03
            s.color.saturation = 0.32
            s.color.vibrance = 0.15
            s.light.shadows = -0.18
            s.light.highlights = -0.05
            s.hsl.red.hue = -0.05
            s.hsl.red.saturation = 0.35
            s.hsl.red.luminance = -0.05
            s.hsl.orange.saturation = 0.20
            s.hsl.yellow.hue = -0.10
            s.hsl.yellow.saturation = 0.20
            s.hsl.green.hue = 0.05
            s.hsl.green.saturation = 0.30
            s.hsl.green.luminance = -0.10
            s.hsl.aqua.hue = -0.15
            s.hsl.aqua.saturation = 0.25
            s.hsl.blue.hue = -0.10
            s.hsl.blue.saturation = 0.30
            s.hsl.blue.luminance = -0.10
            s.hsl.purple.saturation = 0.20
            s.hsl.magenta.saturation = 0.20
            s.vignette.amount = -0.08
            s.vignette.feather = 0.6
            s.grain.size = 0.05
            s.grain.intensity = 0.03
            s.softness = 0.03
            s.curves.rgb.points = [
                CurvePoint(x: 0.0, y: 0.00),
                CurvePoint(x: 0.25, y: 0.10),
                CurvePoint(x: 0.5, y: 0.50),
                CurvePoint(x: 0.75, y: 0.92),
                CurvePoint(x: 1.0, y: 1.00)
            ]
            return s
        }()),

        // Cinestill 800T — Vision3 500T with the remjet anti-halation removed.
        // Tungsten-balanced (cool in daylight), with red halation around
        // highlights and warm tungsten glow on light sources. True bloom needs
        // a per-pixel pass — split-tone + lifted reds get most of the way there.
        Preset(name: "Kodak 2383", category: .colorFilm, stack: {
            var s = stack(filterID: LUT.kodak2383, strength: 0.7)
            s.color.temperature = -0.18
            s.color.tint = -0.04
            s.color.saturation = -0.05
            s.color.vibrance = 0.05
            s.light.shadows = 0.20
            s.light.highlights = 0.05
            s.hsl.red.hue = 0.04
            s.hsl.red.saturation = 0.18
            s.hsl.red.luminance = 0.10
            s.hsl.orange.saturation = 0.15
            s.hsl.orange.luminance = 0.12  // halation glow
            s.hsl.yellow.saturation = -0.08
            s.hsl.green.hue = -0.10
            s.hsl.green.saturation = -0.15
            s.hsl.aqua.hue = -0.08
            s.hsl.aqua.saturation = 0.12
            s.hsl.aqua.luminance = -0.05
            s.hsl.blue.hue = -0.05
            s.hsl.blue.saturation = 0.10
            s.hsl.blue.luminance = -0.10
            s.splitToning.shadowHue = 200
            s.splitToning.shadowSaturation = 0.45
            s.splitToning.highlightHue = 20  // red/amber halation
            s.splitToning.highlightSaturation = 0.30
            s.grain.size = 0.60
            s.grain.intensity = 0.42
            s.softness = 0.12
            s.curves.rgb.points = [
                CurvePoint(x: 0.0, y: 0.10),
                CurvePoint(x: 0.25, y: 0.24),
                CurvePoint(x: 0.5, y: 0.50),
                CurvePoint(x: 0.75, y: 0.76),
                CurvePoint(x: 1.0, y: 0.94)
            ]
            s.halation = 0.65
            return s
        }()),

        // Classic Chrome (Fuji X) — Kodachrome-inspired editorial look. Muted
        // with a SPECIFIC move: yellows pulled olive (not just desaturated),
        // blue shadows, flat midtones, contrasty extremes. Skin reads reportage,
        // not flattering.
        Preset(name: "Classic Chrome", category: .colorFilm, stack: {
            var s = stack(filterID: LUT.classicChrome, strength: 0.9)
            s.color.temperature = -0.04
            s.color.tint = -0.02
            s.color.saturation = -0.15
            s.color.vibrance = -0.05
            s.light.shadows = -0.05
            s.light.highlights = -0.05
            s.hsl.red.saturation = -0.10
            s.hsl.red.luminance = -0.05
            s.hsl.orange.hue = -0.10
            s.hsl.orange.saturation = -0.15
            s.hsl.orange.luminance = -0.08
            s.hsl.yellow.hue = -0.18        // signature olive pull
            s.hsl.yellow.saturation = -0.20
            s.hsl.yellow.luminance = -0.10
            s.hsl.green.hue = -0.05
            s.hsl.green.saturation = -0.10
            s.hsl.aqua.saturation = 0.05
            s.hsl.blue.saturation = 0.08
            s.hsl.blue.luminance = -0.05
            s.hsl.purple.saturation = -0.05
            s.splitToning.shadowHue = 210
            s.splitToning.shadowSaturation = 0.35
            s.splitToning.highlightHue = 40
            s.splitToning.highlightSaturation = 0.10
            s.softness = 0.05
            s.curves.rgb.points = [
                CurvePoint(x: 0.0, y: 0.00),
                CurvePoint(x: 0.25, y: 0.18),
                CurvePoint(x: 0.5, y: 0.50),
                CurvePoint(x: 0.75, y: 0.82),
                CurvePoint(x: 1.0, y: 0.96)
            ]
            return s
        }()),

        // Classic Negative (Fuji X) — Fujicolor Superia simulation. Green pull
        // in shadows, slight cyan in midtones (the "supermarket photo lab"
        // signature), more saturation and contrast than Classic Chrome.
        Preset(name: "Superia 200", category: .colorFilm, stack: {
            var s = stack(filterID: LUT.superia200, strength: 0.8)
            s.color.temperature = -0.03
            s.color.tint = -0.05
            s.color.saturation = 0.08
            s.color.vibrance = 0.10
            s.light.shadows = -0.08
            s.light.highlights = -0.05
            s.hsl.red.hue = 0.06
            s.hsl.red.saturation = 0.10
            s.hsl.orange.hue = 0.05
            s.hsl.orange.saturation = 0.12
            s.hsl.orange.luminance = -0.05
            s.hsl.yellow.hue = 0.08
            s.hsl.yellow.saturation = 0.05
            s.hsl.green.hue = -0.10
            s.hsl.green.saturation = -0.05
            s.hsl.green.luminance = -0.08
            s.hsl.aqua.hue = -0.12
            s.hsl.aqua.saturation = 0.10
            s.hsl.blue.hue = -0.08
            s.hsl.blue.saturation = 0.12
            s.hsl.blue.luminance = -0.10
            s.hsl.purple.hue = 0.05
            s.splitToning.shadowHue = 140   // green-shadow signature
            s.splitToning.shadowSaturation = 0.35
            s.splitToning.highlightHue = 30
            s.splitToning.highlightSaturation = 0.15
            s.grain.size = 0.35
            s.grain.intensity = 0.20
            s.softness = 0.08
            s.curves.rgb.points = [
                CurvePoint(x: 0.0, y: 0.02),
                CurvePoint(x: 0.25, y: 0.18),
                CurvePoint(x: 0.5, y: 0.50),
                CurvePoint(x: 0.75, y: 0.82),
                CurvePoint(x: 1.0, y: 0.97)
            ]
            return s
        }()),

        // Eterna — Fuji's cinematic flat profile (motion-picture stock 250D).
        // Lifted milky blacks, uniformly desaturated by ~30%, gentle highlight
        // roll-off. Designed as a grading base, not a finished look.
        Preset(name: "Fuji 3513", category: .colorFilm, stack: {
            var s = stack(filterID: LUT.fuji3513, strength: 0.6)
            s.color.temperature = -0.04
            s.color.saturation = -0.25
            s.color.vibrance = -0.10
            s.light.shadows = 0.25
            s.light.highlights = -0.18
            s.hsl.red.saturation = -0.08
            s.hsl.orange.saturation = -0.10
            s.hsl.yellow.saturation = -0.10
            s.hsl.green.saturation = -0.12
            s.hsl.aqua.saturation = -0.05
            s.hsl.blue.saturation = -0.05
            s.hsl.purple.saturation = -0.08
            s.hsl.magenta.saturation = -0.08
            s.splitToning.shadowHue = 200
            s.splitToning.shadowSaturation = 0.25
            s.splitToning.highlightHue = 35
            s.splitToning.highlightSaturation = 0.10
            s.grain.size = 0.20
            s.grain.intensity = 0.10
            s.softness = 0.1
            s.curves.rgb.points = [
                CurvePoint(x: 0.0, y: 0.12),
                CurvePoint(x: 0.25, y: 0.30),
                CurvePoint(x: 0.5, y: 0.50),
                CurvePoint(x: 0.75, y: 0.70),
                CurvePoint(x: 1.0, y: 0.88)
            ]
            return s
        }()),

        // Nostalgic Neg (Fuji X / GFX) — modeled on 1970s American New Color
        // (Eggleston, Shore). Amber/honey highlights, brick-terracotta reds,
        // honey yellows, brown-purple shadows. The OPPOSITE of Classic Negative
        // (which is green-shadow vivid) — Nostalgic Neg is amber-shadow faded.
        Preset(name: "Vista 200", category: .colorFilm, stack: {
            var s = stack(filterID: LUT.agfaVista, strength: 0.8)
            s.color.temperature = 0.16
            s.color.tint = 0.05
            s.color.saturation = -0.10
            s.color.vibrance = 0.05
            s.light.shadows = 0.18
            s.light.highlights = -0.10
            s.hsl.red.hue = 0.08
            s.hsl.red.saturation = -0.05
            s.hsl.red.luminance = -0.05
            s.hsl.orange.hue = 0.10
            s.hsl.orange.saturation = 0.10
            s.hsl.orange.luminance = 0.08
            s.hsl.yellow.hue = 0.12
            s.hsl.yellow.saturation = 0.15
            s.hsl.yellow.luminance = 0.10
            s.hsl.green.hue = 0.15
            s.hsl.green.saturation = -0.15
            s.hsl.aqua.saturation = -0.15
            s.hsl.blue.saturation = -0.18
            s.hsl.blue.luminance = -0.05
            s.hsl.purple.hue = 0.10
            s.hsl.magenta.hue = 0.05
            s.splitToning.shadowHue = 25
            s.splitToning.shadowSaturation = 0.40
            s.splitToning.highlightHue = 45
            s.splitToning.highlightSaturation = 0.35
            s.grain.size = 0.30
            s.grain.intensity = 0.15
            s.softness = 0.08
            s.curves.rgb.points = [
                CurvePoint(x: 0.0, y: 0.10),
                CurvePoint(x: 0.25, y: 0.26),
                CurvePoint(x: 0.5, y: 0.50),
                CurvePoint(x: 0.75, y: 0.74),
                CurvePoint(x: 1.0, y: 0.92)
            ]
            return s
        }()),

        // Portra 160 — finest-grain Portra. Cleanest skin tones, lowest
        // contrast of the family, slightly cooler than 400. Wedding /
        // editorial portrait standard for studio-light work.
        Preset(name: "Portra 160", category: .colorFilm, stack: {
            var s = stack(filterID: LUT.portra160, strength: 0.85)
            s.color.saturation = -0.08
            s.color.vibrance = 0.05
            s.light.shadows = 0.12
            s.light.highlights = -0.08
            s.hsl.orange.luminance = 0.08
            s.hsl.green.saturation = -0.10
            s.grain.size = 0.20
            s.grain.intensity = 0.10
            s.softness = 0.04
            return s
        }()),

        // Provia 100F — Fuji's neutral slide film. Accurate color, balanced
        // contrast, no editorial pulls. The "default reference" of the slide
        // family. Nothing exaggerated, nothing missing.
        Preset(name: "Provia 100F", category: .colorFilm, stack: {
            var s = stack(filterID: LUT.provia100f, strength: 0.85)
            s.color.vibrance = 0.05
            s.light.highlights = -0.05
            s.grain.size = 0.10
            s.grain.intensity = 0.05
            return s
        }()),

        // Astia 100F — discontinued Fuji portrait slide. Soft pastel palette,
        // lifted blacks, lower saturation than Provia. Skin reads gentle —
        // the slide film for portrait shooters who wouldn't touch Velvia.
        Preset(name: "Astia 100F", category: .colorFilm, stack: {
            var s = stack(filterID: LUT.astia100f, strength: 0.85)
            s.color.saturation = -0.10
            s.light.shadows = 0.18
            s.light.highlights = -0.08
            s.hsl.orange.luminance = 0.08
            s.grain.size = 0.12
            s.grain.intensity = 0.06
            s.softness = 0.06
            return s
        }()),

        // Kodachrome 64 — the legend. Dense saturated reds, warm-amber bias,
        // crushed shadows, archetypal mid-century editorial. National
        // Geographic / Steve McCurry color signature.
        Preset(name: "Kodachrome 64", category: .colorFilm, stack: {
            var s = stack(filterID: LUT.kodachrome64, strength: 0.85)
            s.color.temperature = 0.06
            s.color.saturation = 0.08
            s.color.vibrance = 0.10
            s.light.shadows = -0.12
            s.light.highlights = -0.08
            s.hsl.red.saturation = 0.18
            s.hsl.orange.saturation = 0.12
            s.hsl.blue.saturation = 0.15
            s.grain.size = 0.18
            s.grain.intensity = 0.12
            s.curves.rgb.points = [
                CurvePoint(x: 0.0, y: 0.00),
                CurvePoint(x: 0.25, y: 0.16),
                CurvePoint(x: 0.5, y: 0.50),
                CurvePoint(x: 0.75, y: 0.84),
                CurvePoint(x: 1.0, y: 0.98)
            ]
            return s
        }()),

        // X-Trans Velvia — Fuji's vivid landscape sim. Saturated greens and
        // blues, bumped contrast, dense shadows. Don't shoot people on it.
        Preset(name: "X-Trans Velvia", category: .colorFilm, stack: {
            var s = stack(filterID: LUT.xtransVelvia, strength: 0.9)
            s.color.saturation = 0.15
            s.color.vibrance = 0.10
            s.light.shadows = -0.10
            s.hsl.green.saturation = 0.18
            s.hsl.blue.saturation = 0.18
            return s
        }()),

        // X-Trans Astia — Fuji's soft portrait sim. Reduced saturation,
        // gentle skin, lifted shadows. Pairs well with overcast / window
        // light.
        Preset(name: "X-Trans Astia", category: .colorFilm, stack: {
            var s = stack(filterID: LUT.xtransAstia, strength: 0.9)
            s.color.saturation = -0.08
            s.light.shadows = 0.15
            s.light.highlights = -0.08
            s.hsl.orange.luminance = 0.06
            s.softness = 0.05
            return s
        }()),

        // Pro Neg Std — Fuji's flat color-negative sim. Faithful neutral
        // skin, low saturation, low contrast. Designed as a grading base
        // for studio / commercial portraiture.
        Preset(name: "Pro Neg Std", category: .colorFilm, stack: {
            var s = stack(filterID: LUT.xtransProNeg, strength: 0.9)
            s.color.saturation = -0.12
            s.color.vibrance = 0.05
            s.light.shadows = 0.10
            return s
        }())
    ]

    // MARK: B&W Film
    //
    // After the Noir LUT desaturates, HSL has nothing to act on. So B&W stocks
    // are differentiated entirely by tonal personality (contrast curve, white
    // and black endpoints, highlight/shadow roll-off) and grain.

    private static let bwFilm: [Preset] = [

        // Tri-X 400 — the photojournalism archetype since 1954. Coarse
        // irregular cubic-grain (RMS ~17), assertive contrast, firm shoulder
        // that resists blowing out under push processing. Punchy not creamy.
        Preset(name: "Tri-X 400", category: .bwFilm, stack: {
            var s = stack(filterID: LUT.triX400, strength: 1.0)
            s.light.highlights = -0.08          // firm shoulder
            s.light.shadows = -0.05
            s.sharpness = 0.45
            s.grain.size = 0.70
            s.grain.intensity = 0.72
            s.softness = 0.05
            s.curves.rgb.points = [
                CurvePoint(x: 0.0, y: 0.00),
                CurvePoint(x: 0.25, y: 0.15),
                CurvePoint(x: 0.5, y: 0.50),
                CurvePoint(x: 0.75, y: 0.85),
                CurvePoint(x: 1.0, y: 0.99)
            ]
            return s
        }()),

        // HP5 Plus — Tri-X's softer competitor. Straighter, gentler curve,
        // lifted shadows that retain detail, very soft highlight roll-off.
        // Painterly, forgiving, even-distributed grain.
        Preset(name: "HP5 Plus", category: .bwFilm, stack: {
            var s = stack(filterID: LUT.hp5Plus, strength: 1.0)
            s.light.highlights = 0.08           // soft roll-off
            s.light.shadows = 0.10
            s.sharpness = 0.35
            s.grain.size = 0.55
            s.grain.intensity = 0.55
            s.softness = 0.1
            s.curves.rgb.points = [
                CurvePoint(x: 0.0, y: 0.05),
                CurvePoint(x: 0.25, y: 0.22),
                CurvePoint(x: 0.5, y: 0.50),
                CurvePoint(x: 0.75, y: 0.78),
                CurvePoint(x: 1.0, y: 0.94)
            ]
            return s
        }()),

        // Delta 3200 — Ilford's iconic high-ISO B&W. Coarse cubic grain (RMS
        // ~17 at box speed, more when pushed), assertive contrast, deep
        // shadows, controlled but bright highlights. Reportage / available-
        // light look — graphic, gritty, unmistakable.
        Preset(name: "Delta 3200", category: .bwFilm, stack: {
            var s = stack(filterID: LUT.delta3200, strength: 1.0)
            s.light.highlights = -0.05
            s.light.shadows = -0.10
            s.sharpness = 0.40
            s.grain.size = 0.85
            s.grain.intensity = 0.85
            s.softness = 0.06
            s.curves.rgb.points = [
                CurvePoint(x: 0.0, y: 0.00),
                CurvePoint(x: 0.25, y: 0.13),
                CurvePoint(x: 0.5, y: 0.50),
                CurvePoint(x: 0.75, y: 0.87),
                CurvePoint(x: 1.0, y: 1.00)
            ]
            // Pushed B&W with bright spec highlights (streetlights, signage)
            // shows a faint glow around blown areas — partly halation through
            // the thin emulsion, partly diffraction in fast lenses.
            s.halation = 0.10
            return s
        }()),

        // Acros 100/II — finest grain of any conventional B&W (RMS ~7),
        // legendary reciprocity for long exposures. Deep Fuji-density blacks,
        // dramatic but controlled highlights, architecturally crisp.
        Preset(name: "Acros", category: .bwFilm, stack: {
            var s = stack(filterID: LUT.acros, strength: 1.0)
            s.light.highlights = -0.04
            s.light.shadows = -0.08
            s.sharpness = 0.65
            s.grain.size = 0.20
            s.grain.intensity = 0.22
            s.softness = 0.04
            s.curves.rgb.points = [
                CurvePoint(x: 0.0, y: 0.00),
                CurvePoint(x: 0.25, y: 0.18),
                CurvePoint(x: 0.5, y: 0.50),
                CurvePoint(x: 0.75, y: 0.82),
                CurvePoint(x: 1.0, y: 0.97)
            ]
            return s
        }())
    ]

    // MARK: Era & Camera

    private static let era: [Preset] = [

        // 90s Disposable — Funsaver/QuickSnap aesthetic. Foreground hot-warm
        // from on-camera flash, background falls off cool-blue (flash can't
        // reach + tungsten ambient interpreted as blue). Drugstore minilab
        // pushed warm-saturated. Coarse grain, hard plastic-lens vignette.
        Preset(name: "Elite Color 400", category: .era, stack: {
            var s = stack(filterID: LUT.eliteColor400, strength: 0.65)
            s.color.temperature = 0.08
            s.color.tint = -0.05
            s.color.saturation = 0.18
            s.color.vibrance = 0.20
            s.light.shadows = -0.15
            s.light.highlights = -0.05
            s.hsl.red.saturation = 0.20
            s.hsl.orange.hue = 0.05
            s.hsl.orange.saturation = 0.25
            s.hsl.yellow.hue = -0.05
            s.hsl.green.hue = -0.10
            s.hsl.green.saturation = 0.20
            s.hsl.aqua.hue = 0.05
            s.hsl.blue.saturation = 0.30
            s.hsl.blue.luminance = -0.10
            s.splitToning.shadowHue = 220       // blue shadows (flash falloff)
            s.splitToning.shadowSaturation = 0.65
            s.splitToning.highlightHue = 35
            s.splitToning.highlightSaturation = 0.35
            s.vignette.amount = -0.40           // hard mechanical vignette
            s.vignette.feather = 0.45
            s.grain.size = 0.65
            s.grain.intensity = 0.55
            s.softness = 0.3
            s.curves.rgb.points = [
                CurvePoint(x: 0.0, y: 0.04),
                CurvePoint(x: 0.25, y: 0.20),
                CurvePoint(x: 0.5, y: 0.50),
                CurvePoint(x: 0.75, y: 0.82),
                CurvePoint(x: 1.0, y: 0.96)
            ]
            // Disposable cameras shoot with on-camera flash directly into bulbs,
            // streetlights, retroreflective surfaces — minilab prints show
            // visible red bloom around those highlights. Part of the look.
            s.halation = 0.18
            return s
        }()),

        // Polaroid SX-70 (1972) — narrowest tonal range of any consumer film.
        // Dreamy washed pastels, lowest contrast, magenta-pink shadow drift,
        // slight cyan in upper midtones. Print surface adds barely-visible
        // grain. Even illumination across frame.
        Preset(name: "Polaroid 669", category: .era, stack: {
            var s = stack(filterID: LUT.polaroid669, strength: 0.7)
            s.color.temperature = 0.06
            s.color.tint = 0.14
            s.color.saturation = -0.30
            s.color.vibrance = -0.05
            s.light.shadows = 0.45
            s.light.highlights = -0.20
            s.hsl.red.hue = -0.10
            s.hsl.red.saturation = -0.15
            s.hsl.orange.saturation = -0.20
            s.hsl.yellow.saturation = -0.25
            s.hsl.green.hue = -0.08
            s.hsl.green.saturation = -0.30
            s.hsl.aqua.saturation = -0.20
            s.hsl.blue.hue = -0.10
            s.hsl.blue.saturation = -0.25
            s.splitToning.shadowHue = 310       // pinker than 70s Faded's 320
            s.splitToning.shadowSaturation = 0.60
            s.splitToning.highlightHue = 195    // SX-70 cyan-highlight quirk
            s.splitToning.highlightSaturation = 0.25
            s.vignette.amount = -0.10
            s.vignette.feather = 0.85
            s.grain.size = 0.40
            s.grain.intensity = 0.15
            s.softness = 0.4
            s.curves.rgb.points = [
                CurvePoint(x: 0.0, y: 0.30),
                CurvePoint(x: 0.25, y: 0.40),
                CurvePoint(x: 0.5, y: 0.50),
                CurvePoint(x: 0.75, y: 0.62),
                CurvePoint(x: 1.0, y: 0.74)
            ]
            s.halation = 0.18
            return s
        }()),

        // Polaroid 600 (1981) — warmer, more saturated, more contrasty than
        // SX-70. Signature yellow-green olive shadow shift. Cream whites.
        // Greens push toward yellow (foliage looks autumnal). The "80s family
        // photo" warmth most people picture when they hear "Polaroid."
        Preset(name: "Fuji FP-100C", category: .era, stack: {
            var s = stack(filterID: LUT.fp100c, strength: 0.8)
            s.color.temperature = 0.18
            s.color.tint = -0.04
            s.color.saturation = -0.05
            s.color.vibrance = 0.10
            s.light.shadows = 0.30
            s.light.highlights = -0.10
            s.hsl.red.saturation = 0.15
            s.hsl.orange.hue = -0.05
            s.hsl.orange.saturation = 0.10
            s.hsl.yellow.hue = -0.08
            s.hsl.yellow.saturation = 0.15
            s.hsl.green.hue = -0.20             // greens toward yellow
            s.hsl.green.saturation = -0.10
            s.hsl.green.luminance = -0.10
            s.hsl.aqua.saturation = -0.20
            s.hsl.blue.saturation = -0.15
            s.splitToning.shadowHue = 75        // yellow-green olive
            s.splitToning.shadowSaturation = 0.50
            s.splitToning.highlightHue = 45
            s.splitToning.highlightSaturation = 0.35
            s.vignette.amount = -0.15
            s.vignette.feather = 0.80
            s.grain.size = 0.45
            s.grain.intensity = 0.20
            s.softness = 0.32
            s.curves.rgb.points = [
                CurvePoint(x: 0.0, y: 0.22),
                CurvePoint(x: 0.25, y: 0.36),
                CurvePoint(x: 0.5, y: 0.50),
                CurvePoint(x: 0.75, y: 0.66),
                CurvePoint(x: 1.0, y: 0.84)
            ]
            s.halation = 0.12
            return s
        }())
    ]

    // MARK: Modern
    //
    // Creative grades, not film emulations. The LUT carries the look — recipes
    // here are thin (light vibrance / contrast polish) so the LUT's authored
    // intent dominates. Punch Overlay was authored as a low-opacity overlay
    // (40-60% in After Effects), so its strength stays low.

    private static let modern: [Preset] = [

        // Cinematic Teal — orange-skin / teal-shadow Hollywood grade. Lifts
        // and cools shadows, warms midtones. Looks great on outdoor portraits
        // and travel; reads heavy on neutral product shots.
        Preset(name: "Cinematic Teal", category: .modern, stack: {
            var s = stack(filterID: LUT.cinematicTeal, strength: 0.85)
            s.color.vibrance = 0.05
            s.light.shadows = 0.05
            s.light.highlights = -0.05
            // Subtle warm bloom around highlights — the cinema-grade signature
            // most teal/orange looks pair with print-stock halation.
            s.halation = 0.08
            return s
        }()),

        // Punch Overlay — contrast + saturation booster designed as an
        // overlay. Half-strength so it adds zip without crushing.
        Preset(name: "Punch", category: .modern, stack: {
            var s = stack(filterID: LUT.punchOverlay, strength: 0.5)
            s.color.vibrance = 0.05
            return s
        }()),

        // Dusk Cool — green-cool twilight wash (Vivid LUTs #2). Mid-grey
        // shifts toward cyan-green; pulls reds warmer; lifts shadows.
        Preset(name: "Dusk Cool", category: .modern, stack: {
            var s = stack(filterID: LUT.duskCool, strength: 1.0)
            s.color.vibrance = 0.05
            s.light.shadows = 0.10
            s.light.highlights = -0.05
            return s
        }()),

        // Dusk Warm — orange/amber sunset wash (Vivid LUTs #4). Mid-grey
        // shifts toward warm-orange; bumps reds and yellows; gentle
        // shoulder so highlights stay readable.
        Preset(name: "Dusk Warm", category: .modern, stack: {
            var s = stack(filterID: LUT.duskWarm, strength: 1.0)
            s.color.vibrance = 0.05
            s.light.shadows = 0.08
            s.light.highlights = -0.08
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

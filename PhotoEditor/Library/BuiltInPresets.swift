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

    private static let seedKey = "builtInPresetsSeeded.v5"

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

        // Portra 400 — the modern wedding/portrait standard. Creamy warm-leaning
        // palette with luminance-lifted oranges (skin) and pulled-cool greens so
        // foliage doesn't compete. Soft contrast, wide latitude, fine T-grain.
        Preset(name: "Portra 400", category: .colorFilm, stack: {
            var s = stack(filterID: BuiltInLUTs.ID.warmFade, strength: 0.35)
            s.color.temperature = 0.10
            s.color.tint = -0.03
            s.color.saturation = -0.12
            s.color.vibrance = 0.08
            s.light.contrast = -0.10
            s.light.shadows = 0.18
            s.light.highlights = -0.12
            s.light.blacks = 0.08          // lifted (Lightroom convention)
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
            return s
        }()),

        // Portra 800 — pushed sibling. More contrast, more red push, deeper
        // blacks, coarser grain, push-process magenta in shadows.
        Preset(name: "Portra 800", category: .colorFilm, stack: {
            var s = stack(filterID: BuiltInLUTs.ID.warmFade, strength: 0.30)
            s.color.temperature = 0.14
            s.color.tint = 0.04
            s.color.saturation = -0.04
            s.color.vibrance = 0.10
            s.light.contrast = 0.08
            s.light.shadows = 0.10
            s.light.highlights = -0.08
            s.light.blacks = -0.10         // crushed
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
            return s
        }()),

        // Ektar 100 — the anti-Portra. Slide-film saturation on a negative
        // substrate. Vivid blues, saturated cool-leaning greens, warm-shifted
        // reds. Skin tones go ruddy (which is why portrait shooters avoid it).
        Preset(name: "Ektar 100", category: .colorFilm, stack: {
            var s = stack()
            s.color.temperature = 0.04
            s.color.tint = -0.04
            s.color.saturation = 0.18
            s.color.vibrance = 0.10
            s.light.contrast = 0.18
            s.light.shadows = -0.05
            s.light.highlights = -0.10
            s.light.blacks = -0.15         // deep
            s.light.whites = 0.05
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
            return s
        }()),

        // Fuji Pro 400H — discontinued cult wedding stock. Cool airy pastels,
        // mint-cyan greens, pinker (not orange) skin, milky shadows. Lowest
        // contrast of the color stocks here. Workflow assumed +1-2 stop overexposure.
        Preset(name: "Fuji Pro 400H", category: .colorFilm, stack: {
            var s = stack(filterID: BuiltInLUTs.ID.warmFade, strength: 0.25)
            s.color.temperature = -0.06
            s.color.tint = -0.06
            s.color.saturation = -0.18
            s.color.vibrance = 0.05
            s.light.contrast = -0.18
            s.light.shadows = 0.28
            s.light.highlights = -0.18
            s.light.blacks = 0.18          // milky shadows
            s.light.whites = -0.05
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
            return s
        }()),

        // Fuji Velvia 50 — landscape slide film. Hyper-saturated everywhere,
        // crushed blacks, hard highlight clip, cyan-shifted blues, deep emerald
        // greens. Skin tones look terrible — that's by design.
        Preset(name: "Fuji Velvia 50", category: .colorFilm, stack: {
            var s = stack()
            s.color.temperature = 0.05
            s.color.tint = 0.03
            s.color.saturation = 0.32
            s.color.vibrance = 0.15
            s.light.contrast = 0.30
            s.light.shadows = -0.18
            s.light.highlights = -0.05
            s.light.blacks = -0.25         // crushed
            s.light.whites = 0.10
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
            return s
        }()),

        // Cinestill 800T — Vision3 500T with the remjet anti-halation removed.
        // Tungsten-balanced (cool in daylight), with red halation around
        // highlights and warm tungsten glow on light sources. True bloom needs
        // a per-pixel pass — split-tone + lifted reds get most of the way there.
        Preset(name: "Cinestill 800T", category: .colorFilm, stack: {
            var s = stack(filterID: BuiltInLUTs.ID.cinematicCool, strength: 0.55)
            s.color.temperature = -0.18
            s.color.tint = -0.04
            s.color.saturation = -0.05
            s.color.vibrance = 0.05
            s.light.contrast = -0.08
            s.light.shadows = 0.20
            s.light.highlights = 0.05
            s.light.blacks = 0.20          // lifted cinema black
            s.light.whites = 0.05
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
            return s
        }()),

        // Classic Chrome (Fuji X) — Kodachrome-inspired editorial look. Muted
        // with a SPECIFIC move: yellows pulled olive (not just desaturated),
        // blue shadows, flat midtones, contrasty extremes. Skin reads reportage,
        // not flattering.
        Preset(name: "Classic Chrome", category: .colorFilm, stack: {
            var s = stack()
            s.color.temperature = -0.04
            s.color.tint = -0.02
            s.color.saturation = -0.15
            s.color.vibrance = -0.05
            s.light.contrast = 0.15
            s.light.shadows = -0.05
            s.light.highlights = -0.05
            s.light.blacks = -0.10
            s.light.whites = -0.05
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
            return s
        }()),

        // Classic Negative (Fuji X) — Fujicolor Superia simulation. Green pull
        // in shadows, slight cyan in midtones (the "supermarket photo lab"
        // signature), more saturation and contrast than Classic Chrome.
        Preset(name: "Classic Negative", category: .colorFilm, stack: {
            var s = stack()
            s.color.temperature = -0.03
            s.color.tint = -0.05
            s.color.saturation = 0.08
            s.color.vibrance = 0.10
            s.light.contrast = 0.20
            s.light.shadows = -0.08
            s.light.highlights = -0.05
            s.light.blacks = -0.12         // crushed-but-rich
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
            return s
        }()),

        // Eterna — Fuji's cinematic flat profile (motion-picture stock 250D).
        // Lifted milky blacks, uniformly desaturated by ~30%, gentle highlight
        // roll-off. Designed as a grading base, not a finished look.
        Preset(name: "Eterna", category: .colorFilm, stack: {
            var s = stack(filterID: BuiltInLUTs.ID.cinematicCool, strength: 0.30)
            s.color.temperature = -0.04
            s.color.saturation = -0.25
            s.color.vibrance = -0.10
            s.light.contrast = -0.25
            s.light.shadows = 0.25
            s.light.highlights = -0.18
            s.light.blacks = 0.25          // milky lifted
            s.light.whites = -0.10
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
            return s
        }()),

        // Nostalgic Neg (Fuji X / GFX) — modeled on 1970s American New Color
        // (Eggleston, Shore). Amber/honey highlights, brick-terracotta reds,
        // honey yellows, brown-purple shadows. The OPPOSITE of Classic Negative
        // (which is green-shadow vivid) — Nostalgic Neg is amber-shadow faded.
        Preset(name: "Nostalgic Neg", category: .colorFilm, stack: {
            var s = stack(filterID: BuiltInLUTs.ID.warmFade, strength: 0.55)
            s.color.temperature = 0.16
            s.color.tint = 0.05
            s.color.saturation = -0.10
            s.color.vibrance = 0.05
            s.light.contrast = -0.12
            s.light.shadows = 0.18
            s.light.highlights = -0.10
            s.light.blacks = 0.15          // soft lifted
            s.light.whites = -0.05
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
            var s = stack(filterID: BuiltInLUTs.ID.noir, strength: 1.0)
            s.light.contrast = 0.32
            s.light.highlights = -0.08          // firm shoulder
            s.light.shadows = -0.05
            s.light.whites = 0.10
            s.light.blacks = -0.22              // deep but not crushed
            s.sharpness = 0.45
            s.grain.size = 0.70
            s.grain.intensity = 0.72
            return s
        }()),

        // HP5 Plus — Tri-X's softer competitor. Straighter, gentler curve,
        // lifted shadows that retain detail, very soft highlight roll-off.
        // Painterly, forgiving, even-distributed grain.
        Preset(name: "HP5 Plus", category: .bwFilm, stack: {
            var s = stack(filterID: BuiltInLUTs.ID.noir, strength: 1.0)
            s.light.contrast = 0.12
            s.light.highlights = 0.08           // soft roll-off
            s.light.shadows = 0.10
            s.light.whites = 0.04
            s.light.blacks = 0.10               // lifted
            s.sharpness = 0.35
            s.grain.size = 0.55
            s.grain.intensity = 0.55
            return s
        }()),

        // T-Max 100 — Kodak T-grain (tabular) emulsion. Exceptionally fine
        // tight grain (RMS ~8), long linear curve, near-clinical sharpness,
        // ~200 lp/mm resolution. Smooth, controlled, modern.
        Preset(name: "T-Max 100", category: .bwFilm, stack: {
            var s = stack(filterID: BuiltInLUTs.ID.noir, strength: 1.0)
            s.light.contrast = 0.18
            s.light.highlights = 0.02
            s.light.shadows = 0.04
            s.light.whites = 0.12
            s.light.blacks = 0.15               // controlled mid-deep
            s.sharpness = 0.70                  // clinical micro-detail
            s.grain.size = 0.25
            s.grain.intensity = 0.28
            return s
        }()),

        // Acros 100/II — finest grain of any conventional B&W (RMS ~7),
        // legendary reciprocity for long exposures. Deep Fuji-density blacks,
        // dramatic but controlled highlights, architecturally crisp.
        Preset(name: "Acros", category: .bwFilm, stack: {
            var s = stack(filterID: BuiltInLUTs.ID.noir, strength: 1.0)
            s.light.contrast = 0.24
            s.light.highlights = -0.04
            s.light.shadows = -0.08
            s.light.whites = 0.14
            s.light.blacks = -0.26              // deepest, Fuji density
            s.sharpness = 0.65
            s.grain.size = 0.20
            s.grain.intensity = 0.22
            return s
        }())
    ]

    // MARK: Era & Camera

    private static let era: [Preset] = [

        // 70s Faded — chromogenic dye-fade signature. Kodacolor-era prints
        // lose cyan/yellow faster than magenta over decades, so old prints
        // drift warm-pink with rusty magenta shadows; paper base yellows; black
        // point lifts as oxidized dyes can't reach pure black.
        Preset(name: "70s Faded", category: .era, stack: {
            var s = stack(filterID: BuiltInLUTs.ID.warmFade, strength: 0.80)
            s.color.temperature = 0.12
            s.color.tint = 0.10
            s.color.saturation = -0.22
            s.color.vibrance = -0.10
            s.light.contrast = -0.30
            s.light.shadows = 0.35
            s.light.highlights = -0.10
            s.light.blacks = 0.55                // strong lift (dyes never reach black)
            s.light.whites = -0.15
            s.hsl.red.hue = -0.15
            s.hsl.red.saturation = -0.15
            s.hsl.orange.saturation = -0.10
            s.hsl.yellow.hue = -0.10
            s.hsl.yellow.saturation = -0.20
            s.hsl.aqua.saturation = -0.30
            s.hsl.blue.saturation = -0.35       // blues fade fastest
            s.splitToning.shadowHue = 320       // magenta-rust
            s.splitToning.shadowSaturation = 0.55
            s.splitToning.highlightHue = 50      // yellowed paper
            s.splitToning.highlightSaturation = 0.30
            s.vignette.amount = -0.18
            s.vignette.feather = 0.75
            s.grain.size = 0.55
            s.grain.intensity = 0.32
            return s
        }()),

        // 90s Disposable — Funsaver/QuickSnap aesthetic. Foreground hot-warm
        // from on-camera flash, background falls off cool-blue (flash can't
        // reach + tungsten ambient interpreted as blue). Drugstore minilab
        // pushed warm-saturated. Coarse grain, hard plastic-lens vignette.
        Preset(name: "90s Disposable", category: .era, stack: {
            var s = stack(filterID: BuiltInLUTs.ID.warmFade, strength: 0.30)
            s.color.temperature = 0.08
            s.color.tint = -0.05
            s.color.saturation = 0.18
            s.color.vibrance = 0.20
            s.light.contrast = 0.18
            s.light.shadows = -0.15
            s.light.highlights = -0.05
            s.light.blacks = -0.10               // contrasty
            s.light.whites = 0.10
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
            return s
        }()),

        // Polaroid SX-70 (1972) — narrowest tonal range of any consumer film.
        // Dreamy washed pastels, lowest contrast, magenta-pink shadow drift,
        // slight cyan in upper midtones. Print surface adds barely-visible
        // grain. Even illumination across frame.
        Preset(name: "Polaroid SX-70", category: .era, stack: {
            var s = stack(filterID: BuiltInLUTs.ID.warmFade, strength: 0.55)
            s.color.temperature = 0.06
            s.color.tint = 0.14
            s.color.saturation = -0.30
            s.color.vibrance = -0.05
            s.light.contrast = -0.40            // most extreme of the 5
            s.light.shadows = 0.45
            s.light.highlights = -0.20
            s.light.blacks = 0.60                // most lifted
            s.light.whites = -0.20
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
            return s
        }()),

        // Polaroid 600 (1981) — warmer, more saturated, more contrasty than
        // SX-70. Signature yellow-green olive shadow shift. Cream whites.
        // Greens push toward yellow (foliage looks autumnal). The "80s family
        // photo" warmth most people picture when they hear "Polaroid."
        Preset(name: "Polaroid 600", category: .era, stack: {
            var s = stack(filterID: BuiltInLUTs.ID.warmFade, strength: 0.65)
            s.color.temperature = 0.18
            s.color.tint = -0.04
            s.color.saturation = -0.05
            s.color.vibrance = 0.10
            s.light.contrast = -0.20
            s.light.shadows = 0.30
            s.light.highlights = -0.10
            s.light.blacks = 0.40                // lifted
            s.light.whites = -0.05
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
            return s
        }()),

        // Polaroid Now (post-2017 Impossible/Polaroid reformulation). Cleaner
        // than vintage 600 — heavy color shifts removed, contrast moderate-low,
        // mild warmth, soft vignette. Recognizable as Polaroid by softness and
        // lifted blacks rather than aggressive color cast.
        Preset(name: "Polaroid Now", category: .era, stack: {
            var s = stack(filterID: BuiltInLUTs.ID.warmFade, strength: 0.35)
            s.color.temperature = 0.08
            s.color.tint = 0.02
            s.color.saturation = -0.05
            s.color.vibrance = 0.05
            s.light.contrast = -0.12
            s.light.shadows = 0.20
            s.light.highlights = -0.05
            s.light.blacks = 0.25                // mildly lifted
            s.hsl.orange.saturation = 0.05
            s.hsl.yellow.hue = -0.04
            s.hsl.green.hue = -0.06
            s.hsl.aqua.saturation = -0.10
            s.hsl.blue.saturation = -0.08
            s.splitToning.shadowHue = 40         // soft amber, not olive
            s.splitToning.shadowSaturation = 0.25
            s.splitToning.highlightHue = 45
            s.splitToning.highlightSaturation = 0.20
            s.vignette.amount = -0.12
            s.vignette.feather = 0.85
            s.grain.size = 0.35
            s.grain.intensity = 0.10
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

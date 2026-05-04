// BuiltInPresets.swift
// Curated starter recipes seeded into RecipeStore on first launch.
//
// Idempotency: a UserDefaults flag (`builtInPresetsSeeded.v1`) prevents re-seeding.
// Bumping the suffix in `seedKey` (e.g. v2) re-seeds — but does NOT delete user
// edits to existing built-in rows, so prefer adding new presets in a new key.
//
// Preset values are tuned in -1...+1 normalized space matching AdjustmentStack
// (PipelineBuilder maps these to EV / CIFilter inputs at render time).

import Foundation

enum BuiltInPresets {

    private static let seedKey = "builtInPresetsSeeded.v1"

    /// Insert all built-in presets if they haven't been seeded yet.
    /// Safe to call on every launch — no-op after the first successful run.
    @MainActor
    static func seedIfNeeded(store: RecipeStore,
                             defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: seedKey) else { return }
        for preset in all {
            store.save(name: preset.name,
                       stack: preset.stack,
                       thumbnail: nil,
                       category: preset.category)
        }
        defaults.set(true, forKey: seedKey)
    }

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

    private static let colorFilm: [Preset] = [
        Preset(name: "Portra 400", category: .colorFilm, stack: {
            var s = stack(filterID: BuiltInLUTs.ID.warmFade, strength: 0.5)
            s.color.temperature = 0.08
            s.color.tint = 0.04
            s.color.saturation = -0.05
            s.color.vibrance = 0.10
            s.light.shadows = 0.15
            s.light.contrast = -0.04
            return s
        }()),

        Preset(name: "Portra 800", category: .colorFilm, stack: {
            var s = stack(filterID: BuiltInLUTs.ID.warmFade, strength: 0.6)
            s.color.temperature = 0.12
            s.color.tint = 0.06
            s.color.saturation = -0.10
            s.light.contrast = 0.05
            s.grain.size = 0.45
            s.grain.intensity = 0.40
            return s
        }()),

        Preset(name: "Ektar 100", category: .colorFilm, stack: {
            var s = stack()
            s.color.saturation = 0.20
            s.color.vibrance = 0.15
            s.color.temperature = 0.04
            s.light.contrast = 0.10
            s.light.blacks = -0.05
            return s
        }()),

        Preset(name: "Fuji Pro 400H", category: .colorFilm, stack: {
            var s = stack()
            s.color.temperature = -0.06
            s.color.tint = 0.08
            s.color.saturation = -0.05
            s.light.shadows = 0.12
            s.light.blacks = 0.08
            return s
        }()),

        Preset(name: "Fuji Velvia 50", category: .colorFilm, stack: {
            var s = stack()
            s.color.saturation = 0.30
            s.color.vibrance = 0.20
            s.light.contrast = 0.15
            s.light.shadows = -0.10
            s.light.blacks = -0.08
            return s
        }()),

        Preset(name: "Cinestill 800T", category: .colorFilm, stack: {
            var s = stack(filterID: BuiltInLUTs.ID.cinematicCool, strength: 0.6)
            s.color.temperature = -0.20
            s.color.tint = 0.10
            s.light.highlights = 0.15
            s.light.shadows = 0.10
            s.splitToning.highlightHue = 30
            s.splitToning.highlightSaturation = 0.25
            s.grain.size = 0.40
            s.grain.intensity = 0.35
            return s
        }())
    ]

    // MARK: B&W Film

    private static let bwFilm: [Preset] = [
        Preset(name: "Tri-X 400", category: .bwFilm, stack: {
            var s = stack(filterID: BuiltInLUTs.ID.noir, strength: 1.0)
            s.light.contrast = 0.20
            s.light.shadows = -0.10
            s.light.blacks = -0.10
            s.grain.size = 0.55
            s.grain.intensity = 0.55
            return s
        }()),

        Preset(name: "HP5 Plus", category: .bwFilm, stack: {
            var s = stack(filterID: BuiltInLUTs.ID.noir, strength: 1.0)
            s.light.contrast = 0.10
            s.light.blacks = 0.10
            s.grain.size = 0.45
            s.grain.intensity = 0.45
            return s
        }()),

        Preset(name: "T-Max 100", category: .bwFilm, stack: {
            var s = stack(filterID: BuiltInLUTs.ID.noir, strength: 1.0)
            s.light.contrast = 0.05
            s.grain.size = 0.20
            s.grain.intensity = 0.15
            return s
        }())
    ]

    // MARK: Era & Camera

    private static let era: [Preset] = [
        Preset(name: "70s Faded", category: .era, stack: {
            var s = stack(filterID: BuiltInLUTs.ID.warmFade, strength: 0.85)
            s.color.saturation = -0.15
            s.light.blacks = 0.20
            s.light.contrast = -0.10
            s.splitToning.shadowHue = 320           // magenta shadows
            s.splitToning.shadowSaturation = 0.20
            s.grain.size = 0.30
            s.grain.intensity = 0.25
            return s
        }()),

        Preset(name: "90s Disposable", category: .era, stack: {
            var s = stack()
            s.color.temperature = 0.10
            s.color.saturation = 0.10
            s.color.tint = -0.04
            s.light.contrast = 0.08
            s.splitToning.shadowHue = 220           // blue cast in shadows
            s.splitToning.shadowSaturation = 0.15
            s.vignette.amount = -0.30
            s.vignette.feather = 0.55
            s.grain.size = 0.50
            s.grain.intensity = 0.50
            return s
        }()),

        Preset(name: "Polaroid SX-70", category: .era, stack: {
            var s = stack(filterID: BuiltInLUTs.ID.warmFade, strength: 0.7)
            s.color.tint = 0.10
            s.light.shadows = 0.25
            s.light.contrast = -0.10
            s.light.blacks = 0.15
            s.vignette.amount = -0.18
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

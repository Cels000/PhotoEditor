// RecipeCategory.swift
// Grouping for the Recipes sheet. User-saved recipes have no category and
// surface in their own "My Recipes" section. Built-in presets are tagged at
// seed time so the UI can render collapsible sections without a separate
// lookup table.

import Foundation

enum RecipeCategory: String, CaseIterable, Identifiable {
    case `default`     = "default"
    case colorFilm     = "color_film"
    case bwFilm        = "bw_film"
    case era           = "era"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .default:    return "Default"
        case .colorFilm:  return "Color Film"
        case .bwFilm:     return "B&W Film"
        case .era:        return "Era & Camera"
        }
    }
}

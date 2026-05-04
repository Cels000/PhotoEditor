import Foundation

enum EditorPanelTab: String, CaseIterable, Identifiable {
    case looks, light, color, hsl, curves, effects, crop
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .looks:   return "Looks"
        case .light:   return "Light"
        case .color:   return "Color"
        case .hsl:     return "HSL"
        case .curves:  return "Curves"
        case .effects: return "Effects"
        case .crop:    return "Crop"
        }
    }
    var systemImage: String {
        switch self {
        case .looks:   return "wand.and.stars"
        case .light:   return "sun.max"
        case .color:   return "paintpalette"
        case .hsl:     return "circle.hexagongrid.fill"
        case .curves:  return "scribble.variable"
        case .effects: return "sparkles"
        case .crop:    return "crop.rotate"
        }
    }
}

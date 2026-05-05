import Foundation

/// Carousel slot. Either the synthetic ORIGINAL entry (no LUT, identity
/// stack) or a real RecipeItem from RecipeStore. Wraps both in one value type
/// so the view-model and carousel UI don't branch on type everywhere.
enum CameraSlot: Identifiable, Hashable {
    case original
    case recipe(RecipeItem)

    static let originalID = "__original__"

    var id: String {
        switch self {
        case .original:           return Self.originalID
        case .recipe(let r):      return r.id.uuidString
        }
    }

    var displayName: String {
        switch self {
        case .original:           return "ORIGINAL"
        case .recipe(let r):      return r.name
        }
    }

    /// Full stack baked into the captured Library item. ORIGINAL → identity.
    var stack: AdjustmentStack {
        switch self {
        case .original:           return .identity
        case .recipe(let r):      return r.adjustmentStack
        }
    }

    /// Just the LUT portion — what the live preview applies per frame.
    var filterSelection: FilterSelection? {
        switch self {
        case .original:           return nil
        case .recipe(let r):      return r.adjustmentStack.filter
        }
    }

    /// Build the carousel-order list: ORIGINAL first, then recipes in the
    /// order RecipeStore presents them (sortOrder ascending).
    static func build(from recipes: [RecipeItem]) -> [CameraSlot] {
        [.original] + recipes.map { .recipe($0) }
    }

    var isOriginal: Bool {
        if case .original = self { return true }
        return false
    }

    var category: RecipeCategory? {
        switch self {
        case .original:        return nil
        case .recipe(let r):   return BuiltInPresets.category(forName: r.name)
        }
    }

    /// "COLOR FILM" / "MY RECIPES" / etc. nil for `.original` so the caller
    /// renders only the name half with no separator.
    var categoryDisplayName: String? {
        switch self {
        case .original:
            return nil
        case .recipe(let r):
            if let cat = BuiltInPresets.category(forName: r.name) {
                return cat.displayName.uppercased()
            }
            return "MY RECIPES"
        }
    }
}

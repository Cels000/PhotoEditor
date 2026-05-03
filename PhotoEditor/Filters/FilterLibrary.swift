import Foundation
import Observation

/// Read-mostly catalog of all filters available to the editor.
/// Built-ins (procedural) merge with any `.cube` files bundled under
/// `Resources/LUTs/`. Favorites are persisted to UserDefaults.
///
/// FILTER-01: catalog
/// FILTER-04: favorites first, persisted across app restart
/// FILTER-05: stable String IDs (FilterSelection.filterID compatible)
@Observable
final class FilterLibrary {

    // MARK: - Published state

    /// All filters in load order (built-ins first, then bundled .cube files
    /// in filename order). NOT favorites-ordered — see `orderedFilters`.
    private(set) var filters: [Filter] = []

    /// Set of filter IDs marked favorite. Mutated via `toggleFavorite(_:)`.
    private(set) var favorites: Set<String> = []

    // MARK: - Constants

    static let favoritesUserDefaultsKey = "filter.favorites"
    static let bundledLUTSubdirectory = "LUTs"

    // MARK: - Init

    init(userDefaults: UserDefaults = .standard, bundle: Bundle = .main) {
        self.userDefaults = userDefaults
        self.bundle = bundle
        self.favorites = Self.loadFavorites(from: userDefaults)
        self.filters = Self.loadFilters(bundle: bundle)
    }

    private let userDefaults: UserDefaults
    private let bundle: Bundle

    // MARK: - Public API

    /// Filters reordered: favorites first (in their original load order),
    /// then non-favorites (also in load order). The "Original" identity
    /// filter always sorts first regardless of favorite state.
    var orderedFilters: [Filter] {
        let identityID = BuiltInLUTs.ID.identity
        var identity: [Filter] = []
        var favs: [Filter] = []
        var rest: [Filter] = []
        for f in filters {
            if f.id == identityID { identity.append(f) }
            else if favorites.contains(f.id) { favs.append(f) }
            else { rest.append(f) }
        }
        return identity + favs + rest
    }

    func filter(withID id: String) -> Filter? {
        filters.first(where: { $0.id == id })
    }

    func isFavorite(_ id: String) -> Bool { favorites.contains(id) }

    func toggleFavorite(_ id: String) {
        if favorites.contains(id) { favorites.remove(id) }
        else { favorites.insert(id) }
        userDefaults.set(Array(favorites), forKey: Self.favoritesUserDefaultsKey)
    }

    // MARK: - Loading

    private static func loadFavorites(from defaults: UserDefaults) -> Set<String> {
        guard let arr = defaults.array(forKey: favoritesUserDefaultsKey) as? [String] else {
            return []
        }
        return Set(arr)
    }

    private static func loadFilters(bundle: Bundle) -> [Filter] {
        var result: [Filter] = []

        // Built-ins first
        for d in BuiltInLUTs.all {
            result.append(
                Filter(id: d.id, displayName: d.displayName, category: d.category,
                       kind: .builtIn(make: d.make))
            )
        }

        // Bundled .cube files in Resources/LUTs/
        if let baseURL = bundle.url(forResource: bundledLUTSubdirectory, withExtension: nil),
           let urls = try? FileManager.default.contentsOfDirectory(
               at: baseURL,
               includingPropertiesForKeys: nil,
               options: [.skipsHiddenFiles]) {
            let cubeURLs = urls.filter { $0.pathExtension.lowercased() == "cube" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            for url in cubeURLs {
                let name = url.deletingPathExtension().lastPathComponent
                let stableID = "cube.\(name.lowercased())"
                result.append(
                    Filter(id: stableID,
                           displayName: name,
                           category: .film,
                           kind: .cubeFile(url: url))
                )
            }
        }

        return result
    }
}

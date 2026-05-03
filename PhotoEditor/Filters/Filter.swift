import Foundation

/// A user-facing filter — either procedurally generated (built-in)
/// or loaded from a bundled `.cube` file.
///
/// `id` is a stable String. Renaming `displayName` does NOT change
/// the ID, preserving Recipe references (FILTER-05).
struct Filter: Identifiable, Equatable {

    enum Kind: Equatable {
        case builtIn(make: () -> ColorCubeData)
        case cubeFile(url: URL)

        static func == (lhs: Kind, rhs: Kind) -> Bool {
            switch (lhs, rhs) {
            case (.builtIn, .builtIn): return true   // identity by enclosing Filter.id
            case let (.cubeFile(a), .cubeFile(b)): return a == b
            default: return false
            }
        }
    }

    let id: String
    let displayName: String
    let category: BuiltInLUTs.Category
    let kind: Kind

    /// Lazy-loaded cube data. Class-backed so the cache survives Filter copies.
    private let cache: CubeCache

    init(id: String, displayName: String, category: BuiltInLUTs.Category, kind: Kind) {
        self.id = id
        self.displayName = displayName
        self.category = category
        self.kind = kind
        self.cache = CubeCache()
    }

    /// Returns the cube, building/parsing on first access. nil if a `.cube` file
    /// fails to parse (caller should treat as "no filter applied" gracefully).
    func cube() -> ColorCubeData? {
        if let cached = cache.value { return cached }
        let built: ColorCubeData?
        switch kind {
        case .builtIn(let make): built = make()
        case .cubeFile(let url):
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            built = CubeParser.parse(text: text)
        }
        cache.value = built
        return built
    }

    static func == (lhs: Filter, rhs: Filter) -> Bool {
        lhs.id == rhs.id && lhs.displayName == rhs.displayName && lhs.category == rhs.category
    }
}

/// Reference-typed cache so `cube()` memoization survives value-type copies.
private final class CubeCache {
    var value: ColorCubeData?
}

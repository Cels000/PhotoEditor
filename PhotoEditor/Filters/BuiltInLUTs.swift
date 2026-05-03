import Foundation
import simd

/// Procedurally-generated starter LUTs. These are PLACEHOLDERS for visual
/// variety while the app ships without artist `.cube` files. The "real"
/// aesthetic arrives when 64-point `.cube` files are dropped into the
/// `Resources/LUTs/` bundle directory.
///
/// Each factory returns a fully-constructed 64-point `ColorCubeData`.
/// All transforms operate in the cube's normalized 0...1 RGB space and
/// are interpreted by Phase 02-05's `CIColorCubeWithColorSpace` in
/// linear sRGB working space (matches RenderEngine config from Phase 1).
enum BuiltInLUTs {

    /// Stable identifiers — DO NOT CHANGE. Recipes (Phase 6) reference these.
    enum ID {
        static let identity        = "builtin.identity"
        static let warmFade        = "builtin.warm_fade"
        static let cinematicCool   = "builtin.cinematic_cool"
        static let noir            = "builtin.noir"
        static let sepia           = "builtin.sepia"
    }

    struct Descriptor {
        let id: String
        let displayName: String
        let category: Category
        let make: () -> ColorCubeData
    }

    enum Category: String {
        case film, portrait, bw, cinematic
    }

    static let all: [Descriptor] = [
        .init(id: ID.identity,      displayName: "Original",   category: .film,      make: identity),
        .init(id: ID.warmFade,      displayName: "Warm Fade",  category: .film,      make: warmFade),
        .init(id: ID.cinematicCool, displayName: "Cool Cine",  category: .cinematic, make: cinematicCool),
        .init(id: ID.noir,          displayName: "Noir B&W",   category: .bw,        make: noir),
        .init(id: ID.sepia,         displayName: "Sepia",      category: .film,      make: sepia)
    ]

    // MARK: - Factories

    static func identity() -> ColorCubeData { ColorCubeData.identity() }

    static func warmFade() -> ColorCubeData {
        build { r, g, b in
            // Warm shift + lifted blacks (faded film look)
            let r2 = min(1.0, r * 1.05 + 0.04)
            let g2 = g * 0.98 + 0.02
            let b2 = b * 0.92 + 0.04
            return (r2, g2, b2)
        }
    }

    static func cinematicCool() -> ColorCubeData {
        build { r, g, b in
            // Teal shadows, slight orange highlights — classic cinematic
            let lift: Float = 0.05
            let shadowWeight = max(0, 1 - r - g) * 0.3
            let r2 = min(1.0, r * 1.03 + (r > 0.6 ? 0.04 : 0))
            let g2 = min(1.0, g + shadowWeight * lift * 0.5)
            let b2 = min(1.0, b * 1.06 + shadowWeight * lift)
            return (r2, g2, b2)
        }
    }

    static func noir() -> ColorCubeData {
        build { r, g, b in
            // Rec. 709 luma → high contrast B&W
            let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
            let contrasted = ((y - 0.5) * 1.35) + 0.5
            let v = max(0, min(1, contrasted))
            return (v, v, v)
        }
    }

    static func sepia() -> ColorCubeData {
        build { r, g, b in
            let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
            return (min(1, y * 1.07 + 0.08),
                    min(1, y * 0.95 + 0.03),
                    min(1, y * 0.74))
        }
    }

    // MARK: - Build helper

    /// Iterates 64^3 voxels in the canonical sweep order (R fastest, then G, then B)
    /// and applies `transform` to each input RGB triplet, producing a ColorCubeData.
    private static func build(_ transform: (Float, Float, Float) -> (Float, Float, Float)) -> ColorCubeData {
        let n = ColorCubeData.dimension
        var triplets = [Float]()
        triplets.reserveCapacity(n * n * n * 3)
        for b in 0..<n {
            let bf = Float(b) / Float(n - 1)
            for g in 0..<n {
                let gf = Float(g) / Float(n - 1)
                for r in 0..<n {
                    let rf = Float(r) / Float(n - 1)
                    let (r2, g2, b2) = transform(rf, gf, bf)
                    triplets.append(r2)
                    triplets.append(g2)
                    triplets.append(b2)
                }
            }
        }
        // Force-unwrap is safe — count is exactly 64^3 * 3 by construction.
        return ColorCubeData(rgbTriplets: triplets)!
    }
}

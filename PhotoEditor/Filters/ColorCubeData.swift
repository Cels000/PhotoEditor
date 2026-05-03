import Foundation

/// Validated 64-point color cube payload for `CIColorCubeWithColorSpace`.
/// Always 64x64x64 with RGBA float quadruplets, alpha = 1.0.
/// Build via `init(floats:)` (preferred) or `ColorCubeData.identity()`.
struct ColorCubeData: Equatable {

    /// Cube dimension. Always 64 in this app — Apple accepts {4,16,64,256};
    /// we ship 64 (see PITFALLS.md #2).
    static let dimension: Int = 64

    /// Raw bytes ready to hand to `CIColorCubeWithColorSpace.cubeData`.
    /// Length == dimension^3 * 4 (RGBA) * MemoryLayout<Float>.size.
    let rawData: Data

    /// Designated initializer. Accepts a flat array of `dimension^3 * 4` floats
    /// in RGBA order, sweeping R fastest, then G, then B (Resolve `.cube` order).
    /// Returns nil if `floats.count` is wrong or any alpha != 1.0.
    init?(floats: [Float]) {
        let expected = ColorCubeData.dimension * ColorCubeData.dimension * ColorCubeData.dimension * 4
        guard floats.count == expected else { return nil }
        // Validate alpha channel (every 4th float)
        var i = 3
        while i < floats.count {
            if floats[i] != 1.0 { return nil }
            i += 4
        }
        self.rawData = floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// Convenience: build from RGB-only triplets (length == dimension^3 * 3).
    /// Appends alpha = 1.0 to every voxel. Returns nil on wrong length.
    init?(rgbTriplets: [Float]) {
        let voxels = ColorCubeData.dimension * ColorCubeData.dimension * ColorCubeData.dimension
        guard rgbTriplets.count == voxels * 3 else { return nil }
        var rgba = [Float]()
        rgba.reserveCapacity(voxels * 4)
        var i = 0
        while i < rgbTriplets.count {
            rgba.append(rgbTriplets[i])
            rgba.append(rgbTriplets[i + 1])
            rgba.append(rgbTriplets[i + 2])
            rgba.append(1.0)
            i += 3
        }
        self.init(floats: rgba)
    }

    /// Identity LUT — output = input for every voxel.
    /// Used by tests (PITFALLS.md #2 warns to test identity round-trip).
    static func identity() -> ColorCubeData {
        let n = dimension
        var floats = [Float]()
        floats.reserveCapacity(n * n * n * 4)
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    floats.append(Float(r) / Float(n - 1))
                    floats.append(Float(g) / Float(n - 1))
                    floats.append(Float(b) / Float(n - 1))
                    floats.append(1.0)
                }
            }
        }
        // Force-unwrap is safe — we just constructed exactly the right length.
        return ColorCubeData(floats: floats)!
    }
}

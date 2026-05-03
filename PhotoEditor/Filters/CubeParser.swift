import Foundation

/// Pure-Swift parser for the standard Resolve `.cube` 3D LUT format.
/// Output is always a 64-point `ColorCubeData` — smaller cubes are
/// trilinearly resampled.
enum CubeParser {

    enum Error: Swift.Error {
        case missingSize
        case invalidSize(Int)
        case wrongTripletCount(expected: Int, got: Int)
        case malformedNumber(String)
        case constructionFailed
    }

    /// Returns the parsed cube, or nil if input is malformed.
    /// Logs the specific Error to stderr for diagnostics.
    static func parse(text: String) -> ColorCubeData? {
        do {
            return try parseThrowing(text: text)
        } catch {
            FileHandle.standardError.write(Data("CubeParser: \(error)\n".utf8))
            return nil
        }
    }

    static func parseThrowing(text: String) throws -> ColorCubeData {
        var size: Int? = nil
        var domainMin: (Float, Float, Float) = (0, 0, 0)
        var domainMax: (Float, Float, Float) = (1, 1, 1)
        var triplets: [Float] = []

        for rawLine in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("TITLE") { continue }
            if line.hasPrefix("LUT_3D_SIZE") {
                let tokens = line.split(separator: " ")
                guard tokens.count >= 2, let s = Int(tokens[1]) else { throw Error.missingSize }
                size = s
                continue
            }
            if line.hasPrefix("LUT_1D_SIZE") {
                throw Error.invalidSize(0) // 1D LUTs not supported
            }
            if line.hasPrefix("DOMAIN_MIN") {
                let parts = parseFloats(line.dropFirst("DOMAIN_MIN".count))
                if parts.count == 3 { domainMin = (parts[0], parts[1], parts[2]) }
                continue
            }
            if line.hasPrefix("DOMAIN_MAX") {
                let parts = parseFloats(line.dropFirst("DOMAIN_MAX".count))
                if parts.count == 3 { domainMax = (parts[0], parts[1], parts[2]) }
                continue
            }
            // Data line: three space-separated floats
            let parts = parseFloats(Substring(line))
            if parts.count == 3 {
                triplets.append(contentsOf: parts)
            } else if !parts.isEmpty {
                throw Error.malformedNumber(line)
            }
        }

        guard let s = size else { throw Error.missingSize }
        guard [16, 32, 33, 64].contains(s) else { throw Error.invalidSize(s) }
        let expectedTriplets = s * s * s * 3
        guard triplets.count == expectedTriplets else {
            throw Error.wrongTripletCount(expected: expectedTriplets, got: triplets.count)
        }

        // Normalize domain to 0...1
        let normalized = normalizeDomain(triplets: triplets, min: domainMin, max: domainMax)

        // Resample to 64 if needed
        let final64: [Float]
        if s == 64 {
            final64 = normalized
        } else {
            final64 = resampleTrilinear(rgb: normalized, fromSize: s, toSize: 64)
        }

        guard let cube = ColorCubeData(rgbTriplets: final64) else {
            throw Error.constructionFailed
        }
        return cube
    }

    // MARK: - Helpers

    private static func parseFloats(_ s: Substring) -> [Float] {
        s.split(whereSeparator: { $0 == " " || $0 == "\t" })
            .compactMap { Float($0) }
    }

    private static func normalizeDomain(triplets: [Float],
                                        min lo: (Float, Float, Float),
                                        max hi: (Float, Float, Float)) -> [Float] {
        if lo == (0, 0, 0) && hi == (1, 1, 1) { return triplets }
        var out = triplets
        let dr = hi.0 - lo.0, dg = hi.1 - lo.1, db = hi.2 - lo.2
        var i = 0
        while i < out.count {
            out[i]     = (out[i]     - lo.0) / dr
            out[i + 1] = (out[i + 1] - lo.1) / dg
            out[i + 2] = (out[i + 2] - lo.2) / db
            i += 3
        }
        return out
    }

    /// Trilinear resample. Input is RGB-only (length == fromSize^3 * 3),
    /// output is RGB-only (length == toSize^3 * 3).
    /// Data layout: R-fastest sweep (index = ((b * s + g) * s + r) * 3)
    /// This matches Resolve's `.cube` data layout AND ColorCubeData.identity()'s sweep order.
    static func resampleTrilinear(rgb input: [Float], fromSize: Int, toSize: Int) -> [Float] {
        let s = fromSize, t = toSize
        var out = [Float](repeating: 0, count: t * t * t * 3)

        @inline(__always) func sample(_ ri: Int, _ gi: Int, _ bi: Int) -> (Float, Float, Float) {
            let idx = ((bi * s + gi) * s + ri) * 3
            return (input[idx], input[idx + 1], input[idx + 2])
        }

        for bo in 0..<t {
            let bf = Float(bo) / Float(t - 1) * Float(s - 1)
            let b0 = Int(bf.rounded(.down)), b1 = min(b0 + 1, s - 1)
            let bt = bf - Float(b0)
            for go in 0..<t {
                let gf = Float(go) / Float(t - 1) * Float(s - 1)
                let g0 = Int(gf.rounded(.down)), g1 = min(g0 + 1, s - 1)
                let gt = gf - Float(g0)
                for ro in 0..<t {
                    let rf = Float(ro) / Float(t - 1) * Float(s - 1)
                    let r0 = Int(rf.rounded(.down)), r1 = min(r0 + 1, s - 1)
                    let rt = rf - Float(r0)

                    let c000 = sample(r0, g0, b0)
                    let c100 = sample(r1, g0, b0)
                    let c010 = sample(r0, g1, b0)
                    let c110 = sample(r1, g1, b0)
                    let c001 = sample(r0, g0, b1)
                    let c101 = sample(r1, g0, b1)
                    let c011 = sample(r0, g1, b1)
                    let c111 = sample(r1, g1, b1)

                    func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
                    func lerp3(_ a: (Float, Float, Float), _ b: (Float, Float, Float), _ t: Float) -> (Float, Float, Float) {
                        (lerp(a.0, b.0, t), lerp(a.1, b.1, t), lerp(a.2, b.2, t))
                    }

                    let c00 = lerp3(c000, c100, rt)
                    let c10 = lerp3(c010, c110, rt)
                    let c01 = lerp3(c001, c101, rt)
                    let c11 = lerp3(c011, c111, rt)
                    let c0  = lerp3(c00, c10, gt)
                    let c1  = lerp3(c01, c11, gt)
                    let c   = lerp3(c0, c1, bt)

                    let outIdx = ((bo * t + go) * t + ro) * 3
                    out[outIdx]     = c.0
                    out[outIdx + 1] = c.1
                    out[outIdx + 2] = c.2
                }
            }
        }
        return out
    }
}

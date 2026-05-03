import XCTest
@testable import PhotoEditor

final class CubeParserTests: XCTestCase {

    // Helper: build a size-point identity .cube text (R-fastest sweep)
    private func identityCubeText(size: Int) -> String {
        var lines: [String] = []
        lines.append("# Test identity LUT")
        lines.append("TITLE \"Identity\"")
        lines.append("LUT_3D_SIZE \(size)")
        lines.append("DOMAIN_MIN 0.0 0.0 0.0")
        lines.append("DOMAIN_MAX 1.0 1.0 1.0")
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    let rf = Float(r) / Float(size - 1)
                    let gf = Float(g) / Float(size - 1)
                    let bf = Float(b) / Float(size - 1)
                    lines.append("\(rf) \(gf) \(bf)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    func testIdentity64Roundtrip() throws {
        let text = identityCubeText(size: 64)
        let parsed = try XCTUnwrap(CubeParser.parse(text: text))
        XCTAssertEqual(parsed, ColorCubeData.identity())
    }

    func test33To64Resample() throws {
        let text = identityCubeText(size: 33)
        let parsed = try XCTUnwrap(CubeParser.parse(text: text))
        // Corner: black voxel (0,0,0) should be ~0; white voxel (63,63,63) should be ~1.
        let bytes = parsed.rawData
        let floats = bytes.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        XCTAssertEqual(floats[0], 0.0, accuracy: 1.0/255.0)
        XCTAssertEqual(floats[1], 0.0, accuracy: 1.0/255.0)
        XCTAssertEqual(floats[2], 0.0, accuracy: 1.0/255.0)
        let lastVoxel = floats.count - 4
        XCTAssertEqual(floats[lastVoxel],     1.0, accuracy: 1.0/255.0)
        XCTAssertEqual(floats[lastVoxel + 1], 1.0, accuracy: 1.0/255.0)
        XCTAssertEqual(floats[lastVoxel + 2], 1.0, accuracy: 1.0/255.0)
    }

    func testRejectsInvalidSize() {
        let text = "LUT_3D_SIZE 17\n"
        XCTAssertNil(CubeParser.parse(text: text))
    }

    func testHandlesCommentsAndTitle() throws {
        let text = identityCubeText(size: 16)
        let parsed = try XCTUnwrap(CubeParser.parse(text: text))
        XCTAssertEqual(parsed.rawData.count, 64 * 64 * 64 * 4 * MemoryLayout<Float>.size)
    }

    func testDomainMinMax() throws {
        // Build a 16-point cube where data values span 0..0.5 but DOMAIN_MAX=0.5
        // so they should normalize to 0..1.
        let size = 16
        var lines: [String] = []
        lines.append("LUT_3D_SIZE \(size)")
        lines.append("DOMAIN_MIN 0.0 0.0 0.0")
        lines.append("DOMAIN_MAX 0.5 0.5 0.5")
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    let rf = Float(r) / Float(size - 1) * 0.5
                    let gf = Float(g) / Float(size - 1) * 0.5
                    let bf = Float(b) / Float(size - 1) * 0.5
                    lines.append("\(rf) \(gf) \(bf)")
                }
            }
        }
        let parsed = try XCTUnwrap(CubeParser.parse(text: lines.joined(separator: "\n")))
        let floats = parsed.rawData.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        let last = floats.count - 4
        XCTAssertEqual(floats[last], 1.0, accuracy: 1.0/255.0)
    }

    func testMalformedReturnsNil() {
        XCTAssertNil(CubeParser.parse(text: "garbage garbage garbage"))
    }
}

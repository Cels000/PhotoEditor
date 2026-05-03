// RecipeFileIO.swift
// PhotoEditor
//
// Pure namespace for encoding/decoding ExportedRecipe to/from a file URL.
// Used by plan 06-05 (share via UIActivityViewController) and plan 06-06
// (handle .onOpenURL import).
// RECIPE-04.

import Foundation

enum RecipeFileIOError: Error {
    case encodeFailed
    case decodeFailed
    case writeFailed
    case readFailed
}

enum RecipeFileIO {

    /// Encode `doc` to JSON Data. Pretty-printed for human readability — recipes
    /// are small (< 8 KB without thumbnail) so size cost is negligible.
    static func encode(_ doc: ExportedRecipe) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            return try encoder.encode(doc)
        } catch {
            throw RecipeFileIOError.encodeFailed
        }
    }

    /// Decode JSON Data into ExportedRecipe.
    static func decode(_ data: Data) throws -> ExportedRecipe {
        do {
            return try JSONDecoder().decode(ExportedRecipe.self, from: data)
        } catch {
            throw RecipeFileIOError.decodeFailed
        }
    }

    /// Write `doc` to a temp file with .photorecipe extension and return the URL.
    /// Caller (share-sheet flow) is responsible for cleanup or letting the temp dir
    /// reclaim it. Filename is sanitized from doc.name + UUID suffix to ensure uniqueness.
    static func writeTempFile(_ doc: ExportedRecipe) throws -> URL {
        let data = try encode(doc)
        let safeName = doc.name
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined(separator: "_")
        let baseName = safeName.isEmpty ? "Recipe" : safeName
        let filename = "\(baseName)-\(UUID().uuidString.prefix(8)).\(ExportedRecipe.fileExtension)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw RecipeFileIOError.writeFailed
        }
        return url
    }

    /// Read a .photorecipe file from a URL and decode it.
    /// Caller should verify the URL has the expected extension before calling.
    static func read(from url: URL) throws -> ExportedRecipe {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw RecipeFileIOError.readFailed
        }
        return try decode(data)
    }
}

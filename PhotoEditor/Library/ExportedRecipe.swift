// ExportedRecipe.swift
// PhotoEditor
//
// On-disk document format for sharing a Recipe outside the app.
// File extension: .photorecipe   (UTI: com.photoeditor.recipe — registered in Info.plist by plan 06-04)
// Body: JSON Codable. Forward-compat: all fields are added with defaults so older
// app versions can decode newer files (unknown fields are ignored by JSONDecoder).
// RECIPE-04.

import Foundation

struct ExportedRecipe: Codable, Equatable {
    /// Document schema (independent of AdjustmentStack.schemaVersion).
    /// Bump this only when the wrapper layout changes incompatibly.
    var schemaVersion: Int = 1
    var name: String = ""
    var stack: AdjustmentStack = .identity
    var thumbnailJPEGBase64: String? = nil

    static let fileExtension = "photorecipe"
    static let uti = "com.photoeditor.recipe"
    static let currentSchemaVersion = 1
}

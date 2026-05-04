// EditDocument.swift
// PhotoEditor
//
// Top-level edit state. Wraps two AdjustmentStacks (subject + background) and an
// optional SubjectMask. When `mask == nil`, `subjectStack` is the canonical stack
// and `backgroundStack` is unused. When `mask != nil`, both stacks are independent
// and composited via the SubjectMaskStore-provided mask.
//
// schemaVersion 2: introduces dual stacks. Loading a legacy v1 stackData blob is
// handled by `EditDocument.migrating(fromLegacyStackData:)`.

import Foundation

struct SubjectMask: Codable, Equatable {
    var feather: Double = 0                  // 0...1; gaussian blur scalar
    var invert: Bool = false                 // pure mask flip
    var excludedInstances: Set<Int> = []     // indices into Vision's perInstance array
}

struct EditDocument: Codable, Equatable {
    var schemaVersion: Int = 2
    var subjectStack: AdjustmentStack = .identity
    var backgroundStack: AdjustmentStack = .identity
    var mask: SubjectMask? = nil

    static let identity = EditDocument()
}

extension EditDocument {
    /// Decode legacy v1 `AdjustmentStack` JSON and lift to a v2 EditDocument.
    /// Both stacks start identical to the legacy stack; mask is nil.
    static func migrating(fromLegacyStackData data: Data) throws -> EditDocument {
        let legacy = try JSONDecoder().decode(AdjustmentStack.self, from: data)
        return EditDocument(
            schemaVersion: 2,
            subjectStack: legacy,
            backgroundStack: legacy,
            mask: nil
        )
    }
}

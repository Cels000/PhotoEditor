// PhotoEditor/Editor/MaskScope.swift
//
// Active scope for slider writes when the document has a SubjectMask attached.
// `subject` and `background` route writes to one stack; `full` mirror-writes
// both. Outside masked mode the scope is unused — single-stack mode always
// writes to subjectStack (and mirrors to backgroundStack to keep them in sync
// for clean mask-enable later).

import Foundation

enum MaskScope: String, Codable, Equatable {
    case subject
    case full
    case background
}

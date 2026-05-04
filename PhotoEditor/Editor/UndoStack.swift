import Foundation

/// Linear undo/redo over EditDocument snapshots.
/// Capacity-capped (~100) to bound memory; EditDocument is small (~600B with two stacks)
/// so 100 = ~60KB.
struct UndoStack {
    private(set) var history: [EditDocument] = []
    private(set) var cursor: Int = -1
    let capacity: Int

    init(capacity: Int = 100) {
        self.capacity = capacity
    }

    var canUndo: Bool { cursor > 0 }
    var canRedo: Bool { cursor >= 0 && cursor < history.count - 1 }

    mutating func push(_ doc: EditDocument) {
        if cursor < history.count - 1 {
            history.removeSubrange((cursor + 1)..<history.count)
        }
        if let top = history.last, top == doc { return }
        history.append(doc)
        if history.count > capacity {
            history.removeFirst(history.count - capacity)
        }
        cursor = history.count - 1
    }

    mutating func seed(_ doc: EditDocument) {
        history = [doc]
        cursor = 0
    }

    mutating func undo() -> EditDocument? {
        guard canUndo else { return nil }
        cursor -= 1
        return history[cursor]
    }

    mutating func redo() -> EditDocument? {
        guard canRedo else { return nil }
        cursor += 1
        return history[cursor]
    }

    mutating func clear(seed: EditDocument) {
        history = [seed]
        cursor = 0
    }
}

import Foundation

/// Linear undo/redo over AdjustmentStack snapshots.
/// Capacity-capped (~100) to bound memory; AdjustmentStack is ~300B so 100 = ~30KB.
struct UndoStack {
    private(set) var history: [AdjustmentStack] = []
    private(set) var cursor: Int = -1
    let capacity: Int

    init(capacity: Int = 100) {
        self.capacity = capacity
    }

    var canUndo: Bool { cursor > 0 }
    var canRedo: Bool { cursor >= 0 && cursor < history.count - 1 }

    /// Push a snapshot. Drops any redo-future after the cursor and trims history if at capacity.
    mutating func push(_ stack: AdjustmentStack) {
        // Drop redo future.
        if cursor < history.count - 1 {
            history.removeSubrange((cursor + 1)..<history.count)
        }
        // Coalesce: skip push if equal to current top.
        if let top = history.last, top == stack { return }
        history.append(stack)
        if history.count > capacity {
            history.removeFirst(history.count - capacity)
        }
        cursor = history.count - 1
    }

    /// Initialize the stack with the current state (cursor = 0).
    mutating func seed(_ stack: AdjustmentStack) {
        history = [stack]
        cursor = 0
    }

    mutating func undo() -> AdjustmentStack? {
        guard canUndo else { return nil }
        cursor -= 1
        return history[cursor]
    }

    mutating func redo() -> AdjustmentStack? {
        guard canRedo else { return nil }
        cursor += 1
        return history[cursor]
    }

    mutating func clear(seed: AdjustmentStack) {
        history = [seed]
        cursor = 0
    }
}

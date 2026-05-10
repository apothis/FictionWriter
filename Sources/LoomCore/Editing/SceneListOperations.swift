import Foundation

/// Pure-data primitives for sidebar reorder/insert/delete operations.
/// Centralised here so SidebarController can call them and tests can
/// drive them without any AppKit machinery.
///
/// All operations are non-mutating: they return a new array. Callers
/// assign back to the canonical store (`Manuscript.orphanedSceneIds` or
/// `.trashedSceneIds`).
public enum SceneListOperations {

    /// Move the element at `from` to position `to`. Out-of-range indices
    /// or same-position no-ops return the input unchanged. Sidebar drag-
    /// rearrange and the right-click "Move up / down" menu items both
    /// route through this.
    public static func move(_ ids: [UUID], from: Int, to: Int) -> [UUID] {
        guard from >= 0, from < ids.count, to >= 0, to < ids.count else { return ids }
        if from == to { return ids }
        var result = ids
        let element = result.remove(at: from)
        result.insert(element, at: to)
        return result
    }

    /// Remove every occurrence of `id`. (UUIDs are unique by construction
    /// so "occurrences" is at most one, but the implementation is
    /// defensive.) Absent ids return the input unchanged.
    public static func delete(_ id: UUID, from ids: [UUID]) -> [UUID] {
        ids.filter { $0 != id }
    }

    /// Insert `id` at `index`, clamping out-of-range indices into
    /// `[0, ids.count]`. The "add at end" path uses `index == ids.count`.
    public static func insert(_ id: UUID, at index: Int, into ids: [UUID]) -> [UUID] {
        let clamped = max(0, min(index, ids.count))
        var result = ids
        result.insert(id, at: clamped)
        return result
    }
}

import Foundation

/// Conditional lorebook activation — a scene-window gate.
///
/// A `LorebookEntry` with `activateFromSceneId` / `activateUntilSceneId`
/// set activates (subject to its normal constant/keyed rules) only
/// when the current scene falls within that window of the manuscript
/// order. The canonical use case is plot-reveal lore: an entry
/// describing a twist must not leak into scenes written before the
/// reveal.
///
/// The gate fails open — if the current scene can't be positioned in
/// `flatSceneIds`, or a referenced bound is unknown, the entry is
/// allowed. Silently dropping lore would be the worse failure.
public enum LorebookSceneGate {

    public static func allows(
        _ entry: LorebookEntry,
        currentSceneId: UUID?,
        flatSceneIds: [UUID]
    ) -> Bool {
        guard entry.activateFromSceneId != nil || entry.activateUntilSceneId != nil else {
            return true
        }
        guard let currentSceneId,
              let current = flatSceneIds.firstIndex(of: currentSceneId) else {
            return true
        }
        if let from = entry.activateFromSceneId,
           let fromIdx = flatSceneIds.firstIndex(of: from),
           current < fromIdx {
            return false
        }
        if let until = entry.activateUntilSceneId,
           let untilIdx = flatSceneIds.firstIndex(of: until),
           current > untilIdx {
            return false
        }
        return true
    }
}

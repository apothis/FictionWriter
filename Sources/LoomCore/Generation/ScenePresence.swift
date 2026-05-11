import Foundation

/// Pure-data resolver: was character C present in scene S?
/// Phase 4 #7 sub-task 6 — feeds `LedgerKnowledge` (which derives
/// the KNOWS / DOES NOT KNOW split for the `[KNOWLEDGE-LEDGER]`
/// prompt layer via per-scene exposure).
///
/// "Present" is any one of:
/// - `scene.pov == characterId` (POV is definitive).
/// - The character's id has at least one mention recorded in the
///   `MentionIndex` for this scene (i.e. an `@`-reference resolved
///   to this entity).
/// - The character's name OR any alias appears as a whole word in
///   the scene's prose (case-insensitive). This is the common-case
///   path because most fiction prose doesn't use `@`-references.
///
/// All three are "yes" signals; any match returns true.
public enum ScenePresence {
    public static func isPresent(
        characterId: UUID,
        in scene: Scene,
        character: Character,
        mentions: MentionIndex
    ) -> Bool {
        if scene.pov == characterId { return true }
        if mentions.count(for: characterId, in: scene.id) > 0 { return true }
        let lower = scene.prose.lowercased()
        let keys = [character.name] + character.aliases
        return WholeWordMatcher.anyMatch(keys: keys, in: lower)
    }
}

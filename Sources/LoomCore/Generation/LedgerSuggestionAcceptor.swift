import Foundation

/// Pure-data acceptor for a `LedgerSuggestion`. Phase 4 #7 sub-task 5
/// entry point: takes a character + a pending suggestion, returns the
/// character with the suggestion's `KnownFact` appended to
/// `knownFactsBySceneId[sourceSceneId]`. The caller (typically
/// AppState.acceptLedgerSuggestion) writes the result back through
/// `ProjectSession.updateCharacter(_:)` so the project is dirtied
/// and the auto-save fires.
///
/// `Character.knownFactsBySceneId` is `[UUID: [KnownFact]]` — keyed
/// on the scene the facts were extracted from. A suggestion whose
/// `fact.sourceSceneId` is nil (pre-story knowledge) can't be keyed
/// into the map at all; in that case the acceptor returns the input
/// unchanged. Sub-task 3's diff always stamps a non-nil sourceSceneId,
/// so this is purely defensive against future callers.
public enum LedgerSuggestionAcceptor {
    public static func apply(
        _ suggestion: LedgerSuggestion,
        to character: Character
    ) -> Character {
        guard let sceneId = suggestion.fact.sourceSceneId else {
            return character
        }
        var updated = character
        var bucket = updated.knownFactsBySceneId[sceneId] ?? []
        bucket.append(suggestion.fact)
        updated.knownFactsBySceneId[sceneId] = bucket
        return updated
    }
}

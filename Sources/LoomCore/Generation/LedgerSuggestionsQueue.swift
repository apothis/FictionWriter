import Foundation

/// In-memory queue of pending `LedgerSuggestion`s, keyed by character.
/// Phase 4 #7 sub-task 3 — populated from extraction results via
/// `LedgerDiff.diff(...)`; consumed by the Bible-inspector chip
/// (sub-task 4) which shows the count + per-fact accept/reject UI.
///
/// Intentionally ephemeral. If the user dismisses the app with
/// pending suggestions, the next extraction (post-scene-edit) will
/// re-surface anything still missing from the bible — accepted
/// suggestions persist into `Character.knownFactsBySceneId`
/// (sub-task 5) so the dedup pass in `LedgerDiff` filters them out
/// next time around.
public final class LedgerSuggestionsQueue {
    private var byCharacter: [UUID: [LedgerSuggestion]] = [:]
    private var idToCharacter: [UUID: UUID] = [:]  // fact.id → characterId

    public init() {}

    /// Total suggestions across all characters.
    public var totalCount: Int {
        byCharacter.values.reduce(0) { $0 + $1.count }
    }

    /// Suggestions for a specific character, in insertion order.
    public func suggestions(forCharacter id: UUID) -> [LedgerSuggestion] {
        byCharacter[id] ?? []
    }

    /// All character ids that currently have at least one pending
    /// suggestion. Useful for the Bible-list badge ("3 suggestions
    /// across 2 characters").
    public var charactersWithSuggestions: [UUID] {
        byCharacter.keys.filter { (byCharacter[$0]?.isEmpty == false) }.map { $0 }
    }

    /// Append `suggestions` to their respective character buckets.
    /// Deduplicates by `fact.id` — re-adding an already-queued
    /// suggestion is a no-op so an over-eager extraction pass
    /// doesn't cause UI flicker.
    public func add(_ suggestions: [LedgerSuggestion]) {
        for s in suggestions {
            guard idToCharacter[s.fact.id] == nil else { continue }
            byCharacter[s.characterId, default: []].append(s)
            idToCharacter[s.fact.id] = s.characterId
        }
    }

    /// Drop the suggestion with the given `fact.id`. Used by the
    /// accept (after persistence lands in sub-task 5) and reject
    /// UI paths. No-op on unknown ids.
    public func remove(factId: UUID) {
        guard let characterId = idToCharacter.removeValue(forKey: factId) else { return }
        byCharacter[characterId]?.removeAll { $0.fact.id == factId }
        if byCharacter[characterId]?.isEmpty == true {
            byCharacter.removeValue(forKey: characterId)
        }
    }

    /// Drop every suggestion for a character (e.g. user deleted the
    /// character from the bible).
    public func clear(characterId: UUID) {
        guard let suggestions = byCharacter.removeValue(forKey: characterId) else { return }
        for s in suggestions {
            idToCharacter.removeValue(forKey: s.fact.id)
        }
    }

    /// Drop every queued suggestion. Used on project replace /
    /// app reset.
    public func clearAll() {
        byCharacter.removeAll()
        idToCharacter.removeAll()
    }
}

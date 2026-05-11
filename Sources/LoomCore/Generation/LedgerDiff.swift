import Foundation

/// A pending fact for the Bible-inspector Suggestions chip
/// (Phase 4 #7 sub-task 4). The diff stage (sub-task 3) produces
/// these from the post-scene extraction; the UI displays them
/// per-character; user accept persists `fact` into
/// `Character.knownFactsBySceneId` (sub-task 5).
///
/// `evidenceQuote` is the short quote the extractor pulled from
/// the scene prose — the §10.5 evidence-quote-validation filter
/// (sub-task 8) drops suggestions whose quote can't be located in
/// the scene, but for sub-task 3 we just carry it through.
public struct LedgerSuggestion: Equatable {
    public let characterId: UUID
    public var fact: KnownFact
    public let evidenceQuote: String

    public init(characterId: UUID, fact: KnownFact, evidenceQuote: String) {
        self.characterId = characterId
        self.fact = fact
        self.evidenceQuote = evidenceQuote
    }
}

/// Pure-data diff of an extraction result against the bible's
/// existing per-character ledger. Sub-task 3 entry point — the
/// coordinator (sub-task 2) calls into this from
/// `onExtractionComplete`, and the result feeds the Suggestions
/// queue + UI (sub-task 4).
public enum LedgerDiff {

    /// Resolve each extracted fact's `characterId` (a name OR alias
    /// string) against `bible.characters`, drop facts whose text
    /// already appears verbatim on the resolved character's ledger,
    /// and stamp survivors with `sourceSceneId` + `addedAt`.
    ///
    /// "Verbatim" here means case-insensitive after trimming
    /// leading/trailing whitespace — enough to catch the model
    /// re-emitting the same fact across passes. The §10.5
    /// embedding-based paraphrase collapse is sub-task 8.
    public static func diff(
        extracted: [LedgerExtraction.ExtractedFact],
        bible: Bible,
        sourceSceneId: UUID,
        now: Date = Date()
    ) -> [LedgerSuggestion] {
        // Build the alias→characterId resolver. Names + aliases are
        // both keys; case-insensitive matching via lowercased.
        var resolver: [String: UUID] = [:]
        for character in bible.characters {
            let normalizedName = normalize(character.name)
            if !normalizedName.isEmpty { resolver[normalizedName] = character.id }
            for alias in character.aliases {
                let normalizedAlias = normalize(alias)
                if !normalizedAlias.isEmpty { resolver[normalizedAlias] = character.id }
            }
        }

        // Build the per-character "known fact text" set so the
        // dedup check is O(1) per extracted fact.
        var existingByCharacter: [UUID: Set<String>] = [:]
        for character in bible.characters {
            var set: Set<String> = []
            for facts in character.knownFactsBySceneId.values {
                for fact in facts {
                    set.insert(normalize(fact.fact))
                }
            }
            existingByCharacter[character.id] = set
        }

        var out: [LedgerSuggestion] = []
        for ef in extracted {
            guard let characterId = resolver[normalize(ef.characterId)] else { continue }
            let normalizedText = normalize(ef.fact)
            if let existing = existingByCharacter[characterId], existing.contains(normalizedText) {
                continue
            }
            let persisted = KnownFact(
                id: UUID(),
                fact: ef.fact,
                sourceSceneId: sourceSceneId,
                certainty: mapCertainty(ef.certainty),
                addedAt: now
            )
            out.append(LedgerSuggestion(
                characterId: characterId,
                fact: persisted,
                evidenceQuote: ef.evidenceQuote
            ))
        }
        return out
    }

    /// `LedgerExtraction.Certainty` and `Certainty` (the bible-side
    /// type on KnownFact) have the same string raw values; this just
    /// bridges the type. Both enums declare the same four cases.
    private static func mapCertainty(_ c: LedgerExtraction.Certainty) -> Certainty {
        switch c {
        case .asserted: return .asserted
        case .suspected: return .suspected
        case .unknown: return .unknown
        case .mistaken: return .mistaken
        }
    }

    private static func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

import Foundation

/// Phase 4 #7 sub-task 8 — the three §10.5 production filters that
/// run between `LedgerDiff.diff` and `ledgerSuggestionsQueue.add`.
/// All three are pure-data passes over pre-computed embedding
/// vectors; the async embedding fetch + orchestration sits at the
/// AppState layer (so the filters themselves stay synchronous + TDD
/// tractable per the always-TDD memory contract).
///
/// **Fail-open contract.** Every filter is fail-open on missing
/// embeddings: if a suggestion's required vector isn't in the dict,
/// the filter keeps the suggestion. The orchestrator's contract is
/// to fetch every embedding before calling in; a missing key implies
/// an orchestrator bug, not adversarial input. Dropping silently in
/// that case would violate the NSFW content-neutrality directive
/// (HANDOFF §15.8 / LOOM_NSFW §3) — the user's accept/reject pass is
/// the authoritative content filter, not these embedding heuristics.
public enum LedgerFilters {
    /// Default cosine threshold for paraphrase-cluster dedup. 0.85
    /// per LOOM_LEDGER_SPIKE §10.5 #1; SillyTavern's chat-vectorisation
    /// floor is 0.55 with diminishing returns above 0.7 (LOOM_MEMORY
    /// §B2), so 0.85 is in the "definitely the same proposition"
    /// region without conflating loosely related facts.
    public static let defaultDedupThreshold: Double = 0.85

    /// Default cosine threshold for evidence-quote validation. 0.65
    /// matches the spike's `scoreByEmbedding(...)` default — the
    /// pre-registered "this is the same proposition in different
    /// words" threshold from the Round-3 calibration.
    public static let defaultEvidenceThreshold: Double = 0.65

    /// Default cosine threshold for the prompt-leakage filter. 0.85
    /// mirrors dedup — leaked prompt text should be a near-paraphrase
    /// of the instruction body to count as leakage.
    public static let defaultPromptLeakageThreshold: Double = 0.85

    /// Drop suggestions whose fact text is a paraphrase (cosine ≥
    /// threshold) of either:
    ///
    /// 1. An existing fact already in the resolved character's bible
    ///    ledger (`existingFactsByCharacter[characterId]`), OR
    /// 2. An earlier surviving suggestion for the same character in
    ///    this same batch (collapses intra-batch paraphrase clusters
    ///    by first-wins).
    ///
    /// Per-character scoped: a paraphrase on Mia doesn't filter the
    /// same-text fact on Anders. Order-preserving (first occurrence
    /// of any cluster is the representative).
    public static func deduplicate(
        suggestions: [LedgerSuggestion],
        existingFactsByCharacter: [UUID: [String]],
        embeddings: [String: [Float]],
        threshold: Double = defaultDedupThreshold
    ) -> [LedgerSuggestion] {
        var keptByCharacter: [UUID: [String]] = [:]
        var out: [LedgerSuggestion] = []

        for suggestion in suggestions {
            let text = suggestion.fact.fact
            guard let factVector = embeddings[text] else {
                // Fail open. Record the kept text so later siblings in
                // the same character group can still dedup against it
                // if their embeddings are present.
                out.append(suggestion)
                keptByCharacter[suggestion.characterId, default: []].append(text)
                continue
            }

            let existing = existingFactsByCharacter[suggestion.characterId] ?? []
            let kept = keptByCharacter[suggestion.characterId] ?? []
            let comparisons = existing + kept

            let isDupe = comparisons.contains { other in
                guard let otherVector = embeddings[other] else { return false }
                return LedgerExtraction.cosineSimilarity(factVector, otherVector) >= threshold
            }
            if isDupe { continue }

            out.append(suggestion)
            keptByCharacter[suggestion.characterId, default: []].append(text)
        }
        return out
    }

    /// Drop suggestions whose `evidenceQuote` has no scene sentence
    /// within `threshold` cosine. Catches the model lightly
    /// editorialising speech tags (e.g. emitting `"Mia asked, 'Who is
    /// it?'"` when the prose only has `"Who is it?"`). Fail-open on
    /// empty evidence (the diff carries `""` when the extractor
    /// omitted the field) and on missing evidence embedding.
    public static func validateEvidence(
        suggestions: [LedgerSuggestion],
        sceneSentences: [String],
        embeddings: [String: [Float]],
        threshold: Double = defaultEvidenceThreshold
    ) -> [LedgerSuggestion] {
        var out: [LedgerSuggestion] = []
        for suggestion in suggestions {
            let evidence = suggestion.evidenceQuote
            if evidence.isEmpty {
                out.append(suggestion)
                continue
            }
            guard let evidenceVector = embeddings[evidence] else {
                out.append(suggestion)
                continue
            }
            let hasMatch = sceneSentences.contains { sentence in
                guard let sentenceVector = embeddings[sentence] else { return false }
                return LedgerExtraction.cosineSimilarity(evidenceVector, sentenceVector) >= threshold
            }
            if hasMatch { out.append(suggestion) }
        }
        return out
    }

    /// Drop suggestions whose fact body cosine-matches the
    /// extraction prompt's instruction body above `threshold`.
    /// Catches the rare prompt-text echo documented in
    /// LOOM_LEDGER_SPIKE §9.2 — facts whose `fact` field literally
    /// contains a chunk of the §3.3 instruction text. Fail-open on
    /// missing fact embedding.
    public static func filterPromptLeakage(
        suggestions: [LedgerSuggestion],
        promptEmbedding: [Float],
        embeddings: [String: [Float]],
        threshold: Double = defaultPromptLeakageThreshold
    ) -> [LedgerSuggestion] {
        var out: [LedgerSuggestion] = []
        for suggestion in suggestions {
            let text = suggestion.fact.fact
            guard let factVector = embeddings[text] else {
                out.append(suggestion)
                continue
            }
            let cosine = LedgerExtraction.cosineSimilarity(factVector, promptEmbedding)
            if cosine >= threshold { continue }
            out.append(suggestion)
        }
        return out
    }
}

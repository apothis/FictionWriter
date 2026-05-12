import Foundation

/// Phase 4 #7 sub-task 8 — async orchestrator that chains the three
/// §10.5 production filters behind a single `KoboldEmbedding.embed`
/// batch call. Lives between `LedgerDiff.diff` and
/// `ledgerSuggestionsQueue.add`; the AppState wrapper hops to main
/// before touching the queue + notification so the pipeline itself
/// stays thread-agnostic.
///
/// The text batch in each call: every suggestion's fact body + each
/// non-empty `evidenceQuote` + every existing-bible fact text
/// (scoped to the affected characters) + every non-empty scene
/// sentence + the constant
/// `LedgerExtraction.extractionPromptInstruction`. The embed result
/// is a `[text: vector]` dict that all three filters consume.
///
/// Fail-soft contract — if any of these go sideways, the pipeline
/// returns the input list unchanged so the user still sees the
/// candidates:
///
/// 1. Embed call errors out (network failure, server cold, etc.).
/// 2. Embed returns a vector array whose length doesn't match the
///    requested text array (positional alignment broken).
///
/// The result carries per-filter drop counts so AppState can log a
/// breakdown — without this, `filter-dropped=K/N` in the log is
/// opaque about which of the three filters did the work, making
/// behaviour diagnosis on live runs (where the same prose can
/// produce 1 drop one day and 16 the next due to extractor sampling
/// variance) impossible without re-runs.
public struct LedgerFilterPipelineResult: Equatable {
    /// Survivors after all three filters.
    public let suggestions: [LedgerSuggestion]
    /// How many suggestions the dedup filter removed.
    public let dedupDropped: Int
    /// How many the evidence-quote validation removed (post-dedup).
    public let evidenceDropped: Int
    /// How many the prompt-leakage filter removed (post-evidence).
    public let leakageDropped: Int

    public init(
        suggestions: [LedgerSuggestion],
        dedupDropped: Int,
        evidenceDropped: Int,
        leakageDropped: Int
    ) {
        self.suggestions = suggestions
        self.dedupDropped = dedupDropped
        self.evidenceDropped = evidenceDropped
        self.leakageDropped = leakageDropped
    }
}

public enum LedgerFilterPipeline {

    public static func apply(
        embedder: KoboldEmbedding,
        suggestions: [LedgerSuggestion],
        existingFactsByCharacter: [UUID: [String]],
        sceneSentences: [String],
        completion: @escaping (LedgerFilterPipelineResult) -> Void
    ) {
        guard !suggestions.isEmpty else {
            completion(LedgerFilterPipelineResult(
                suggestions: [], dedupDropped: 0, evidenceDropped: 0, leakageDropped: 0
            ))
            return
        }

        var texts: Set<String> = []
        for suggestion in suggestions {
            texts.insert(suggestion.fact.fact)
            if !suggestion.evidenceQuote.isEmpty {
                texts.insert(suggestion.evidenceQuote)
            }
        }
        for (_, facts) in existingFactsByCharacter {
            for fact in facts { texts.insert(fact) }
        }
        for sentence in sceneSentences where !sentence.isEmpty {
            texts.insert(sentence)
        }
        texts.insert(LedgerExtraction.extractionPromptInstruction)

        let textArray = Array(texts)

        embedder.embed(texts: textArray) { result in
            switch result {
            case .failure:
                // Fail-soft: input list, no drops.
                completion(LedgerFilterPipelineResult(
                    suggestions: suggestions,
                    dedupDropped: 0, evidenceDropped: 0, leakageDropped: 0
                ))
            case .success(let vectors):
                guard vectors.count == textArray.count else {
                    completion(LedgerFilterPipelineResult(
                        suggestions: suggestions,
                        dedupDropped: 0, evidenceDropped: 0, leakageDropped: 0
                    ))
                    return
                }
                let embeddings = Dictionary(uniqueKeysWithValues: zip(textArray, vectors))

                let postDedup = LedgerFilters.deduplicate(
                    suggestions: suggestions,
                    existingFactsByCharacter: existingFactsByCharacter,
                    embeddings: embeddings
                )
                let postEvidence = LedgerFilters.validateEvidence(
                    suggestions: postDedup,
                    sceneSentences: sceneSentences,
                    embeddings: embeddings
                )
                let final: [LedgerSuggestion]
                if let promptVector = embeddings[LedgerExtraction.extractionPromptInstruction] {
                    final = LedgerFilters.filterPromptLeakage(
                        suggestions: postEvidence,
                        promptEmbedding: promptVector,
                        embeddings: embeddings
                    )
                } else {
                    final = postEvidence
                }
                completion(LedgerFilterPipelineResult(
                    suggestions: final,
                    dedupDropped: suggestions.count - postDedup.count,
                    evidenceDropped: postDedup.count - postEvidence.count,
                    leakageDropped: postEvidence.count - final.count
                ))
            }
        }
    }
}

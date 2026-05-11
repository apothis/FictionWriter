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
public enum LedgerFilterPipeline {

    public static func apply(
        embedder: KoboldEmbedding,
        suggestions: [LedgerSuggestion],
        existingFactsByCharacter: [UUID: [String]],
        sceneSentences: [String],
        completion: @escaping ([LedgerSuggestion]) -> Void
    ) {
        guard !suggestions.isEmpty else {
            completion([])
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
                completion(suggestions)
            case .success(let vectors):
                guard vectors.count == textArray.count else {
                    completion(suggestions)
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
                completion(final)
            }
        }
    }
}

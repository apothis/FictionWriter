import Foundation

/// Continuity Audit (L10) — Phase B, the production claim extractor.
///
/// Wraps an `OllamaCallProvider` and turns one scene's prose into
/// typed `ContinuityAudit.Claim`s.
///
/// **Runs unconstrained — no `format` schema.** Ollama's
/// schema-constrained sampling flakes ~50% on gemma4_2b (a degenerate
/// non-terminating buffer → empty content; HANDOFF §15.19, commits
/// `b6c7a97` / `d4df07e`). The newer discovery extractors abandoned
/// the schema for this reason; continuity extraction follows suit —
/// the field names are pinned in the prompt and `parseClaims` is
/// tolerant (JSONL, array, or chatty preamble all parse).
///
/// Guards, mirroring `OllamaLedgerExtractor` / `OllamaBeatExtractor`:
///
/// - **Scene-aware token budget** — `budgetForSceneWords`.
/// - **Retry on a degenerate result** — empty content, an unparseable
///   response, or zero claims is re-rolled once with a doubled budget.
public final class OllamaContinuityExtractor {
    private let provider: OllamaCallProvider

    public init(provider: OllamaCallProvider) {
        self.provider = provider
    }

    public convenience init(client: OllamaClient) {
        self.init(provider: client)
    }

    /// Extract claims for one scene. `sceneId` is stamped onto every
    /// parsed claim as `sourceSceneId`.
    public func extract(
        scenePose: String,
        sceneId: String,
        completion: @escaping (Result<[ContinuityAudit.Claim], Error>) -> Void
    ) {
        let prompt = ContinuityAudit.buildExtractionPrompt(scenePose: scenePose)
        let budget = OllamaLedgerExtractor.budgetForSceneWords(WordCount.count(scenePose))
        callWithRetry(
            prompt: prompt,
            options: OllamaChatOptions(numPredict: budget),
            sceneId: sceneId,
            attemptsRemaining: 1,
            completion: completion
        )
    }

    private func callWithRetry(
        prompt: String,
        options: OllamaChatOptions,
        sceneId: String,
        attemptsRemaining: Int,
        completion: @escaping (Result<[ContinuityAudit.Claim], Error>) -> Void
    ) {
        // Strong self-capture — the URLSession callback must keep the
        // extractor alive (the OllamaLedgerExtractor lifetime lesson).
        // Empty `schema` → unconstrained generation (see the type doc).
        provider.call(prompt: prompt, schema: [:], options: options) { result in
            switch result {
            case .failure(let e):
                DebugLog.shared.write("[continuity] extraction transport failed: \(e)")
                completion(.failure(e))
            case .success(let raw):
                let claims = (try? ContinuityAudit.parseClaims(raw, sourceSceneId: sceneId)) ?? []
                // Re-roll once on any degenerate result — empty
                // content, unparseable text, or zero claims (a real
                // scene yields some). The doubled budget also covers
                // the length-cap case.
                if claims.isEmpty, attemptsRemaining > 0 {
                    let bumped = min(8192, options.numPredict * 2)
                    DebugLog.shared.write("[continuity] degenerate extraction — re-roll num_predict=\(bumped)")
                    self.callWithRetry(
                        prompt: prompt,
                        options: OllamaChatOptions(
                            temperature: options.temperature,
                            numPredict: bumped,
                            repeatPenalty: options.repeatPenalty),
                        sceneId: sceneId,
                        attemptsRemaining: attemptsRemaining - 1,
                        completion: completion)
                    return
                }
                completion(.success(claims))
            }
        }
    }
}

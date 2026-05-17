import Foundation

/// Continuity Audit (L10) — Phase B, the production claim extractor.
///
/// Wraps an `OllamaCallProvider` and turns one scene's prose into
/// typed `ContinuityAudit.Claim`s. Deliberately mirrors
/// `OllamaLedgerExtractor` rather than re-deriving the hard-won
/// guards:
///
/// - **Scene-aware token budget** — reuses
///   `OllamaLedgerExtractor.budgetForSceneWords`.
/// - **Retry-on-empty** — a schema-constrained call that returns empty
///   content (`done_reason: length`) is retried once with a doubled
///   `num_predict`. The Phase A spike runner skipped this, which is
///   why one scene returned zero claims.
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
        let schema = ContinuityAudit.extractionJSONSchema()
        let budget = OllamaLedgerExtractor.budgetForSceneWords(WordCount.count(scenePose))
        callWithRetry(
            prompt: prompt,
            schema: schema,
            options: OllamaChatOptions(numPredict: budget),
            sceneId: sceneId,
            attemptsRemaining: 1,
            completion: completion
        )
    }

    private func callWithRetry(
        prompt: String,
        schema: [String: Any],
        options: OllamaChatOptions,
        sceneId: String,
        attemptsRemaining: Int,
        completion: @escaping (Result<[ContinuityAudit.Claim], Error>) -> Void
    ) {
        // Strong self-capture — the URLSession callback must keep the
        // extractor alive (the OllamaLedgerExtractor lifetime lesson).
        provider.call(prompt: prompt, schema: schema, options: options) { result in
            switch result {
            case .success(let raw):
                if raw.isEmpty, attemptsRemaining > 0 {
                    let bumped = min(8192, options.numPredict * 2)
                    DebugLog.shared.write("[continuity] empty extraction — retry num_predict=\(bumped)")
                    self.callWithRetry(
                        prompt: prompt, schema: schema,
                        options: OllamaChatOptions(
                            temperature: options.temperature,
                            numPredict: bumped,
                            repeatPenalty: options.repeatPenalty),
                        sceneId: sceneId,
                        attemptsRemaining: attemptsRemaining - 1,
                        completion: completion)
                    return
                }
                do {
                    completion(.success(try ContinuityAudit.parseClaims(raw, sourceSceneId: sceneId)))
                } catch {
                    DebugLog.shared.write("[continuity] claim parse failed: \(error)")
                    completion(.failure(error))
                }
            case .failure(let e):
                DebugLog.shared.write("[continuity] extraction transport failed: \(e)")
                completion(.failure(e))
            }
        }
    }
}

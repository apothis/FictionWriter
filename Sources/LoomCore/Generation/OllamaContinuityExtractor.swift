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
/// **Two stages.** Stage 1 extracts claims (high recall). Stage 2
/// re-classifies each claim's `type` in a focused, scene-scoped call —
/// the Goetia/gemma A/B (HANDOFF §15.37) showed typing is overloaded
/// when one call also does recall, JSON, and quoting (the Claimify
/// finding). Stage 2 fails open: a typing error keeps the stage-1
/// best-effort types rather than aborting.
///
/// Guards, mirroring `OllamaLedgerExtractor` / `OllamaBeatExtractor`:
///
/// - **Scene-aware token budget** — `budgetForSceneWords`.
/// - **Retry on a degenerate stage-1 result** — empty content, an
///   unparseable response, or zero claims is re-rolled once with a
///   doubled budget.
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
            attemptsRemaining: 1
        ) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let e):
                completion(.failure(e))
            case .success(let claims):
                guard !claims.isEmpty else { completion(.success([])); return }
                self.applyTyping(scenePose: scenePose, claims: claims, completion: completion)
            }
        }
    }

    /// Stage 2 — re-classify each claim's `type` with a focused
    /// scene-scoped call. Fails open: a typing error or transport
    /// failure keeps the stage-1 types.
    private func applyTyping(
        scenePose: String,
        claims: [ContinuityAudit.Claim],
        completion: @escaping (Result<[ContinuityAudit.Claim], Error>) -> Void
    ) {
        let prompt = ContinuityAudit.buildTypingPrompt(scenePose: scenePose, claims: claims)
        let budget = max(512, claims.count * 24)
        provider.call(
            prompt: prompt, schema: [:], options: OllamaChatOptions(numPredict: budget)
        ) { result in
            switch result {
            case .failure(let e):
                DebugLog.shared.write("[continuity] typing stage failed: \(e) — keeping stage-1 types")
                completion(.success(claims))
            case .success(let raw):
                let types = ContinuityAudit.parseTypes(raw, count: claims.count)
                let retyped = claims.enumerated().map { i, c -> ContinuityAudit.Claim in
                    guard let t = types[i] else { return c }
                    var c2 = c
                    c2.type = t
                    return c2
                }
                completion(.success(retyped))
            }
        }
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

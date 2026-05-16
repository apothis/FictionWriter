import Foundation

/// Phase 9 entity-discovery — production async wrapper around the
/// six-stage pipeline (Stages A2 + B + C + D + post-Stage-D dedup,
/// per LOOM_ENTITY_DISCOVERY_SPIKE §3.1). Mirrors
/// `OllamaLedgerExtractor`'s shape: `OllamaCallProvider` injection,
/// completion-handler API, all orchestration tested without HTTP via
/// stub providers.
///
/// One `extract` call produces the full set of `ProposedEntity`
/// values for a scene, with `sourceSceneId` bound to the caller's
/// scene UUID so the Bible Workspace can resolve scene titles
/// correctly when the snapshot renders.
public protocol EntityDiscoveryExtractor {
    func extract(
        scenePose: String,
        sceneId: UUID,
        knownEntityNames: [String],
        existingEntities: [EntityDedupEngine.ExistingEntity],
        embedder: EmbeddingClient?,
        completion: @escaping (Result<[EntityDiscovery.ProposedEntity], Error>) -> Void
    )
}

public final class OllamaEntityDiscoveryExtractor: EntityDiscoveryExtractor {
    private let provider: OllamaCallProvider

    public init(provider: OllamaCallProvider) {
        self.provider = provider
    }

    public convenience init(client: OllamaClient) {
        self.init(provider: client)
    }

    public func extract(
        scenePose: String,
        sceneId: UUID,
        knownEntityNames: [String],
        existingEntities: [EntityDedupEngine.ExistingEntity],
        embedder: EmbeddingClient?,
        completion: @escaping (Result<[EntityDiscovery.ProposedEntity], Error>) -> Void
    ) {
        // Stage A2: candidate generation via Ollama. Expand known-
        // names with proper-noun tokens (Fix 4) so the post-filter
        // catches surname-split candidates.
        let expandedKnown = EntityDiscovery.expandKnownNamesWithTokens(knownEntityNames)
        // Line-list prompt, not a JSON array — a small model reliably
        // emits `kind | surface | quote` lines but flakes on nested
        // JSON syntax (verified live 2026-05-16). Parsed by
        // `parseCandidateLines`.
        let prompt = EntityDiscovery.buildCandidateListPrompt(
            scenePose: scenePose,
            knownEntityNames: expandedKnown
        )
        // Empty schema = unconstrained generation. Ollama's
        // format-constrained mode flakes ~50% into a non-terminating
        // buffer that hits num_predict and returns empty content
        // (verified live 2026-05-16). The prompt pins the field names
        // instead; `parseCandidates` tolerates synonym keys.
        let schema: [String: Any] = [:]
        // num_predict 4096 — the unconstrained candidate array reaches
        // ~2000 tokens on a dense scene; 4096 gives headroom so it
        // completes rather than truncating. Truncation is recoverable
        // (per-object parse), but a clean full array is better.
        let options = OllamaChatOptions(numPredict: 4096)
        callStageA2WithRetry(
            prompt: prompt,
            schema: schema,
            options: options,
            attemptsRemaining: 1,
            scenePose: scenePose,
            sceneId: sceneId,
            expandedKnown: expandedKnown,
            existingEntities: existingEntities,
            embedder: embedder,
            completion: completion
        )
    }

    private func callStageA2WithRetry(
        prompt: String,
        schema: [String: Any],
        options: OllamaChatOptions,
        attemptsRemaining: Int,
        scenePose: String,
        sceneId: UUID,
        expandedKnown: [String],
        existingEntities: [EntityDedupEngine.ExistingEntity],
        embedder: EmbeddingClient?,
        completion: @escaping (Result<[EntityDiscovery.ProposedEntity], Error>) -> Void
    ) {
        provider.call(prompt: prompt, schema: schema, options: options) { [provider] result in
            switch result {
            case .failure(let err):
                completion(.failure(err))
            case .success(let raw):
                let candidates = EntityDiscovery.parseCandidateLines(raw)
                // Zero candidates from a scene of prose is almost
                // always a derail (empty response, refusal, prose,
                // wrong format) rather than a genuine entity-free
                // scene — fiction always has at least one character.
                // Re-roll once; a persistent zero is a failure so the
                // caller can re-fire later rather than bank an empty.
                if candidates.isEmpty, attemptsRemaining > 0 {
                    DebugLog.shared.write("[proposals] Stage A2 produced no candidates — retrying once")
                    self.callStageA2WithRetry(
                        prompt: prompt,
                        schema: schema,
                        options: options,
                        attemptsRemaining: attemptsRemaining - 1,
                        scenePose: scenePose,
                        sceneId: sceneId,
                        expandedKnown: expandedKnown,
                        existingEntities: existingEntities,
                        embedder: embedder,
                        completion: completion
                    )
                    return
                }
                if candidates.isEmpty {
                    DebugLog.shared.write("[proposals] Stage A2 produced no candidates after retries")
                    completion(.failure(EntityDiscovery.ParseError.noParseableCandidates))
                    return
                }
                DebugLog.shared.write("[proposals] Stage A2 parsed \(candidates.count) candidates: \(candidates.map(\.surface))")
                // Stage B + dedup + recurrence filtering — pure-data,
                // can run synchronously here.
                let filtered = EntityDiscoveryPipeline.applyFilters(
                    candidates: candidates,
                    scenePose: scenePose,
                    knownNames: expandedKnown,
                    existingEntities: existingEntities,
                    embedder: embedder
                )
                if filtered.isEmpty {
                    completion(.success([]))
                    return
                }
                // Stage D: normalisation — one Ollama call per
                // survivor.
                EntityDiscoveryPipeline.runStageD(
                    provider: provider,
                    survivors: filtered,
                    scenePose: scenePose,
                    sceneId: sceneId,
                    completion: completion
                )
            }
        }
    }
}

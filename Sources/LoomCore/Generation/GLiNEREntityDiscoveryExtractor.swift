import Foundation

/// Entity-discovery extractor with GLiNER as the detection step.
///
/// Same six-stage shape as `OllamaEntityDiscoveryExtractor`, but the
/// candidate-generation step (historically the generative Stage A2,
/// which derails and refuses on explicit prose) is GLiNER — a native
/// NER tagger. The LLM keeps only Stage D normalisation; the shared
/// filter + Stage D tail lives in `EntityDiscoveryPipeline`.
public final class GLiNEREntityDiscoveryExtractor: EntityDiscoveryExtractor {
    private let detector: EntityCandidateDetecting
    private let provider: OllamaCallProvider

    public init(detector: EntityCandidateDetecting, provider: OllamaCallProvider) {
        self.detector = detector
        self.provider = provider
    }

    public func extract(
        scenePose: String,
        sceneId: UUID,
        knownEntityNames: [String],
        existingEntities: [EntityDedupEngine.ExistingEntity],
        embedder: EmbeddingClient?,
        completion: @escaping (Result<[EntityDiscovery.ProposedEntity], Error>) -> Void
    ) {
        // Expand known-names with proper-noun tokens (Fix 4) so the
        // post-filter catches surname-split candidates.
        let expandedKnown = EntityDiscovery.expandKnownNamesWithTokens(knownEntityNames)
        detector.detectCandidates(in: scenePose) { [provider] result in
            switch result {
            case .failure(let err):
                completion(.failure(err))
            case .success(let candidates):
                DebugLog.shared.write("[proposals] GLiNER detected \(candidates.count) candidates: \(candidates.map(\.surface))")
                // Stage B/C + dedup + recurrence — pure-data.
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
                // Stage D: normalisation — one Ollama call per survivor.
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

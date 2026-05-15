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
        let prompt = EntityDiscovery.buildCandidateGenerationPrompt(
            scenePose: scenePose,
            knownEntityNames: expandedKnown
        )
        let schema = EntityDiscovery.candidateGenerationJSONSchema()
        let options = OllamaChatOptions(numPredict: 1024)

        provider.call(prompt: prompt, schema: schema, options: options) { [provider] result in
            switch result {
            case .failure(let err):
                completion(.failure(err))
            case .success(let raw):
                let candidates: [EntityDiscovery.Candidate]
                do {
                    candidates = try EntityDiscovery.parseCandidates(raw)
                } catch {
                    completion(.failure(error))
                    return
                }
                // Stage B + dedup + recurrence filtering — pure-data,
                // can run synchronously here.
                let filtered = Self.applyFilters(
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
                // survivor. Fan-out + collect with a counter; on
                // completion, post-Stage-D dedup + build
                // ProposedEntity values + invoke caller completion.
                Self.runStageD(
                    provider: provider,
                    survivors: filtered,
                    scenePose: scenePose,
                    sceneId: sceneId,
                    completion: completion
                )
            }
        }
    }

    private static func applyFilters(
        candidates: [EntityDiscovery.Candidate],
        scenePose: String,
        knownNames: [String],
        existingEntities: [EntityDedupEngine.ExistingEntity],
        embedder: EmbeddingClient?
    ) -> [EntityDiscovery.Candidate] {
        // Fix 1: known-entity filter.
        var out = EntityDiscovery.filterKnown(candidates, knownNames: knownNames)
        // Stage B: promotion gate (proper-noun + anatomy block-list).
        out = out.filter { EntityPromotionGate.evaluate(canonicalName: $0.surface) == .promote }
        // Fix 3: place-recurrence filter.
        out = out.filter {
            EntityDiscovery.passesPlaceRecurrence(
                surface: $0.surface, kind: $0.kind, scenePose: scenePose
            )
        }
        // Stage C: cosine dedup against existing bible entities,
        // if embedder available.
        if let embedder = embedder, !existingEntities.isEmpty {
            out = out.filter { c in
                let v = EntityDedupEngine.evaluate(
                    candidateName: c.surface,
                    candidateEvidenceQuote: c.firstSeenQuote,
                    existingEntities: existingEntities,
                    embedder: embedder
                )
                if case .mergesWith = v { return false }
                return true
            }
        }
        return out
    }

    private static func runStageD(
        provider: OllamaCallProvider,
        survivors: [EntityDiscovery.Candidate],
        scenePose: String,
        sceneId: UUID,
        completion: @escaping (Result<[EntityDiscovery.ProposedEntity], Error>) -> Void
    ) {
        let schema = EntityDiscovery.normalisationJSONSchema()
        let options = OllamaChatOptions(numPredict: 512)
        // Shared mutable state: results[i] = normalised or nil,
        // plus a counter to know when all are done. Wrapped in a
        // class so the closures can mutate via shared reference.
        final class Box {
            var results: [EntityDiscovery.NormalisedEntity?]
            var remaining: Int
            var fired: Bool = false
            init(count: Int) {
                self.results = Array(repeating: nil, count: count)
                self.remaining = count
            }
        }
        let box = Box(count: survivors.count)
        let lock = NSLock()

        for (i, c) in survivors.enumerated() {
            let prompt = EntityDiscovery.buildNormalisationPrompt(
                candidateSurface: c.surface,
                candidateKind: c.kind,
                firstSeenQuote: c.firstSeenQuote,
                scenePose: scenePose
            )
            provider.call(prompt: prompt, schema: schema, options: options) { result in
                var normalised: EntityDiscovery.NormalisedEntity?
                if case .success(let raw) = result {
                    normalised = try? EntityDiscovery.parseNormalisedEntity(raw)
                }
                lock.lock()
                box.results[i] = normalised
                box.remaining -= 1
                let done = box.remaining == 0 && !box.fired
                if done { box.fired = true }
                lock.unlock()
                if done {
                    let normalised = box.results.compactMap { $0 }
                    let deduped = EntityDiscovery.dedupByCanonicalName(normalised)
                    let proposals = deduped.map { n in
                        EntityDiscovery.ProposedEntity(
                            id: UUID(),
                            kind: n.kind,
                            canonicalName: n.canonicalName,
                            aliases: n.aliases,
                            oneLine: n.oneLine,
                            evidenceQuote: n.evidenceQuote,
                            sourceSceneId: sceneId,
                            confidence: 0.8
                        )
                    }
                    completion(.success(proposals))
                }
            }
        }
    }
}

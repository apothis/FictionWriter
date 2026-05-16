import Foundation

/// Entity-discovery pipeline stages downstream of candidate detection.
///
/// The discovery pipeline is: detect candidates → filter (Stage B/C +
/// dedup + recurrence) → normalise (Stage D) → ProposedEntity. The
/// *detection* step varies — GLiNER in production, the generative LLM
/// historically — but everything after it is shared. These stages live
/// here so each detector-specific extractor composes the same tail.
public enum EntityDiscoveryPipeline {
    /// Stage B/C + dedup + recurrence filtering — all pure-data, runs
    /// synchronously.
    public static func applyFilters(
        candidates: [EntityDiscovery.Candidate],
        scenePose: String,
        knownNames: [String],
        existingEntities: [EntityDedupEngine.ExistingEntity],
        embedder: EmbeddingClient?
    ) -> [EntityDiscovery.Candidate] {
        // Collapse duplicate mentions of the same entity before any
        // downstream work — each survivor costs a serialised Stage D
        // Ollama call.
        var out = EntityDiscovery.dedupCandidatesBySurface(candidates)
        DebugLog.shared.write("[proposals] after dedupBySurface: \(out.count) (\(out.map(\.surface)))")
        // Fix 1: known-entity filter.
        out = EntityDiscovery.filterKnown(out, knownNames: knownNames)
        DebugLog.shared.write("[proposals] after filterKnown: \(out.count) (\(out.map(\.surface)))")
        // Stage B: promotion gate (proper-noun + anatomy block-list).
        out = out.filter { EntityPromotionGate.evaluate(canonicalName: $0.surface) == .promote }
        DebugLog.shared.write("[proposals] after promotionGate: \(out.count) (\(out.map(\.surface)))")
        // Fix 3: place-recurrence filter.
        out = out.filter {
            EntityDiscovery.passesPlaceRecurrence(
                surface: $0.surface, kind: $0.kind, scenePose: scenePose
            )
        }
        DebugLog.shared.write("[proposals] after placeRecurrence: \(out.count) (\(out.map(\.surface)))")
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
            DebugLog.shared.write("[proposals] after cosineDedup: \(out.count) (\(out.map(\.surface)))")
        }
        return out
    }

    /// Stage D: normalisation — one Ollama call per survivor. Fan-out +
    /// collect with a counter; on completion, post-Stage-D dedup +
    /// build `ProposedEntity` values + invoke the caller's completion.
    public static func runStageD(
        provider: OllamaCallProvider,
        survivors: [EntityDiscovery.Candidate],
        scenePose: String,
        sceneId: UUID,
        completion: @escaping (Result<[EntityDiscovery.ProposedEntity], Error>) -> Void
    ) {
        let schema = EntityDiscovery.normalisationJSONSchema()
        // num_predict 2048 — load-bearing (see Stage A2 note). 512
        // capped before the normalisation object closed → empty
        // content → every survivor failed to normalise.
        let options = OllamaChatOptions(numPredict: 2048)
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
                switch result {
                case .success(let raw):
                    do {
                        normalised = try EntityDiscovery.parseNormalisedEntity(raw)
                    } catch {
                        // Stage D parse failures are otherwise silent
                        // (the survivor just vanishes from the batch).
                        DebugLog.shared.write("[proposals] Stage D parse failed for '\(c.surface)': \(error)")
                    }
                case .failure(let err):
                    DebugLog.shared.write("[proposals] Stage D call failed for '\(c.surface)': \(err)")
                }
                lock.lock()
                box.results[i] = normalised
                box.remaining -= 1
                let done = box.remaining == 0 && !box.fired
                if done { box.fired = true }
                lock.unlock()
                if done {
                    let normalised = box.results.compactMap { $0 }
                    DebugLog.shared.write("[proposals] Stage D: \(survivors.count) survivors → \(normalised.count) normalised")
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

import Foundation

/// Phase 10 — production async wrapper around relationship discovery.
///
/// Two-stage pairwise classification: stage 1 enumerates the character
/// pairs that co-occur in the scene; stage 2 asks the LLM one bounded
/// "what is A to B?" question per pair. This replaced a single open
/// "list every relationship" call, which a small model hallucinated
/// edges into and under-reported on dense prose (the GLiREL spike
/// confirmed no non-generative model does better zero-shot). Bounded
/// per-pair classification is the form a small model handles reliably.
///
/// `OllamaCallProvider` injection so orchestration is tested without
/// HTTP. One call per pair; a pair whose call fails or derails simply
/// contributes no edge rather than poisoning the whole scene.
public protocol RelationshipDiscoveryExtractor {
    func extract(
        scenePose: String,
        sceneId: UUID,
        characterNames: [String],
        completion: @escaping (Result<[RelationshipDiscovery.ProposedRelationship], Error>) -> Void
    )
}

public final class OllamaRelationshipDiscoveryExtractor: RelationshipDiscoveryExtractor {
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
        characterNames: [String],
        completion: @escaping (Result<[RelationshipDiscovery.ProposedRelationship], Error>) -> Void
    ) {
        // Stage 1 — enumerate the character pairs that co-occur in the
        // scene. Fewer than two, or no co-occurring pair, → no work.
        guard characterNames.count >= 2 else {
            completion(.success([]))
            return
        }
        let pairs = RelationshipDiscovery.candidatePairs(
            characterNames: characterNames, scenePose: scenePose
        )
        guard !pairs.isEmpty else {
            completion(.success([]))
            return
        }

        // Stage 2 — one bounded classification call per pair, fanned
        // out. num_predict 2048: the answer is one line, but gemma
        // emits a reasoning preamble first — a tight cap hits the
        // length limit with empty content before the answer lands
        // (the §15.19 pathology; verified live with a 256-token cap).
        let options = OllamaChatOptions(numPredict: 2048)
        // Shared collection state — one slot per pair plus a counter.
        final class Box {
            var edges: [[RelationshipDiscovery.ProposedRelationship]]
            var errors: [Error] = []
            var remaining: Int
            var fired = false
            init(count: Int) {
                edges = Array(repeating: [], count: count)
                remaining = count
            }
        }
        let box = Box(count: pairs.count)
        let lock = NSLock()

        for (i, pair) in pairs.enumerated() {
            let prompt = RelationshipDiscovery.buildPairClassificationPrompt(
                characterA: pair[0], characterB: pair[1], scenePose: scenePose
            )
            provider.call(prompt: prompt, schema: [:], options: options) { result in
                var parsed: [RelationshipDiscovery.ProposedRelationship] = []
                var failure: Error?
                switch result {
                case .success(let raw):
                    parsed = RelationshipDiscovery.parsePairClassification(
                        raw, characterA: pair[0], characterB: pair[1]
                    )
                case .failure(let err):
                    failure = err
                    DebugLog.shared.write("[relationships] pair \(pair[0])/\(pair[1]) call failed: \(err)")
                }
                lock.lock()
                box.edges[i] = parsed
                if let failure = failure { box.errors.append(failure) }
                box.remaining -= 1
                let done = box.remaining == 0 && !box.fired
                if done { box.fired = true }
                lock.unlock()
                if done {
                    let all = box.edges.flatMap { $0 }
                    // Only surface a failure when *every* pair errored
                    // (a total Ollama outage) — a partial failure just
                    // means a few missing edges.
                    if all.isEmpty, box.errors.count == pairs.count,
                       let first = box.errors.first {
                        completion(.failure(first))
                        return
                    }
                    DebugLog.shared.write("[relationships] \(pairs.count) pairs → \(all.count) edges")
                    completion(.success(RelationshipDiscovery.dedupRelationships(all)))
                }
            }
        }
    }
}

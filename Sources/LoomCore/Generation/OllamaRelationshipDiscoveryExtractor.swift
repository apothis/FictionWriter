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
/// Each pair is classified `votingRounds` times (self-consistency);
/// an edge survives only if a strict majority of rounds agree on it,
/// which drops gemma's unstable run-to-run edge invention.
///
/// `OllamaCallProvider` injection so orchestration is tested without
/// HTTP. A call that fails or derails simply contributes no vote
/// rather than poisoning the whole scene.
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
    private let votingRounds: Int

    /// `votingRounds` — self-consistency: each pair is classified this
    /// many times independently and only an edge a strict majority of
    /// rounds agree on survives. Default 1 (off): the §15.27 live probe
    /// showed voting drops gemma's *unstable* edge invention but not
    /// its *stable* mis-classifications, so at 3× the latency it buys
    /// recall, not precision. The machinery is kept for pairing with a
    /// precision lever; raise this to re-enable it.
    public init(provider: OllamaCallProvider, votingRounds: Int = 1) {
        self.provider = provider
        self.votingRounds = max(1, votingRounds)
    }

    public convenience init(client: OllamaClient, votingRounds: Int = 1) {
        self.init(provider: client, votingRounds: votingRounds)
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
        // Each pair is classified `rounds` times; an edge survives
        // only if a strict majority of rounds agree on it.
        let rounds = votingRounds
        let totalCalls = pairs.count * rounds
        // Shared collection state — one slot per (pair, round).
        final class Box {
            var runs: [[[RelationshipDiscovery.ProposedRelationship]]]
            var errors: [Error] = []
            var remaining: Int
            var fired = false
            init(pairCount: Int, rounds: Int) {
                runs = Array(
                    repeating: Array(repeating: [], count: rounds),
                    count: pairCount
                )
                remaining = pairCount * rounds
            }
        }
        let box = Box(pairCount: pairs.count, rounds: rounds)
        let lock = NSLock()

        for (i, pair) in pairs.enumerated() {
            let prompt = RelationshipDiscovery.buildPairClassificationPrompt(
                characterA: pair[0], characterB: pair[1], scenePose: scenePose
            )
            for round in 0..<rounds {
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
                        DebugLog.shared.write("[relationships] pair \(pair[0])/\(pair[1]) round \(round) call failed: \(err)")
                    }
                    lock.lock()
                    box.runs[i][round] = parsed
                    if let failure = failure { box.errors.append(failure) }
                    box.remaining -= 1
                    let done = box.remaining == 0 && !box.fired
                    if done { box.fired = true }
                    lock.unlock()
                    if done {
                        let all = box.runs.flatMap {
                            RelationshipDiscovery.voteOnPair($0)
                        }
                        // Only surface a failure when *every* call
                        // errored (a total Ollama outage) — a partial
                        // failure just means a few missing edges.
                        if all.isEmpty, box.errors.count == totalCalls,
                           let first = box.errors.first {
                            completion(.failure(first))
                            return
                        }
                        DebugLog.shared.write("[relationships] \(pairs.count) pairs ×\(rounds) rounds → \(all.count) edges")
                        completion(.success(RelationshipDiscovery.dedupRelationships(all)))
                    }
                }
            }
        }
    }
}

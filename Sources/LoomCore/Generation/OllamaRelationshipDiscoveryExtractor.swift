import Foundation

/// Phase 10 step 3 — production async wrapper around relationship
/// discovery. One Ollama call per scene: build the prompt, parse the
/// edges, dedup. Simpler than `OllamaEntityDiscoveryExtractor` (no
/// Stage D normalisation — the model's output *is* the proposal).
///
/// `OllamaCallProvider` injection so orchestration is tested without
/// HTTP. num_predict 2048 — the load-bearing JSON-Schema floor
/// (Phase 9 live-smoke: a smaller cap empties the response). One
/// retry on `noJSONArrayFound`, mirroring Stage A2.
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
        // A scene with fewer than two known characters cannot carry
        // a relationship — skip the call entirely.
        guard characterNames.count >= 2 else {
            completion(.success([]))
            return
        }
        // Line-list prompt, not a JSON array — a small model emits a
        // delimited line list far more reliably than nested JSON
        // (verified live 2026-05-16). Parsed by `parseRelationshipLines`.
        let prompt = RelationshipDiscovery.buildDiscoveryListPrompt(
            scenePose: scenePose,
            characterNames: characterNames
        )
        // Empty schema = unconstrained generation. num_predict 4096
        // gives the line list ample headroom.
        let schema: [String: Any] = [:]
        let options = OllamaChatOptions(numPredict: 4096)
        callWithRetry(
            prompt: prompt,
            schema: schema,
            options: options,
            characterNames: characterNames,
            attemptsRemaining: 1,
            completion: completion
        )
    }

    private func callWithRetry(
        prompt: String,
        schema: [String: Any],
        options: OllamaChatOptions,
        characterNames: [String],
        attemptsRemaining: Int,
        completion: @escaping (Result<[RelationshipDiscovery.ProposedRelationship], Error>) -> Void
    ) {
        provider.call(prompt: prompt, schema: schema, options: options) { result in
            switch result {
            case .failure(let err):
                completion(.failure(err))
            case .success(let raw):
                // Drop edges to hallucinated characters before the
                // empty-check, so an all-invented response re-rolls.
                let parsed = RelationshipDiscovery.filterToKnownCharacters(
                    RelationshipDiscovery.parseRelationshipLines(raw),
                    characterNames: characterNames
                )
                // A response with real content but no parseable lines
                // = the model derailed. Re-roll once. An empty result
                // from a trivially-empty response is a legitimate
                // no-relationship scene — reported as [].
                let rawHasContent = raw.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).count > 2
                if parsed.isEmpty, rawHasContent, attemptsRemaining > 0 {
                    DebugLog.shared.write("[relationships] no parseable relationship lines — retrying once")
                    self.callWithRetry(
                        prompt: prompt,
                        schema: schema,
                        options: options,
                        characterNames: characterNames,
                        attemptsRemaining: attemptsRemaining - 1,
                        completion: completion
                    )
                    return
                }
                completion(.success(RelationshipDiscovery.dedupRelationships(parsed)))
            }
        }
    }
}

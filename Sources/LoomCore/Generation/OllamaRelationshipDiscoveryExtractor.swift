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
        let prompt = RelationshipDiscovery.buildDiscoveryPrompt(
            scenePose: scenePose,
            characterNames: characterNames
        )
        let schema = RelationshipDiscovery.discoveryJSONSchema()
        let options = OllamaChatOptions(numPredict: 2048)
        callWithRetry(
            prompt: prompt,
            schema: schema,
            options: options,
            attemptsRemaining: 1,
            completion: completion
        )
    }

    private func callWithRetry(
        prompt: String,
        schema: [String: Any],
        options: OllamaChatOptions,
        attemptsRemaining: Int,
        completion: @escaping (Result<[RelationshipDiscovery.ProposedRelationship], Error>) -> Void
    ) {
        provider.call(prompt: prompt, schema: schema, options: options) { result in
            switch result {
            case .failure(let err):
                completion(.failure(err))
            case .success(let raw):
                do {
                    let parsed = try RelationshipDiscovery.parseRelationships(raw)
                    completion(.success(RelationshipDiscovery.dedupRelationships(parsed)))
                } catch EntityDiscovery.ParseError.noJSONArrayFound where attemptsRemaining > 0 {
                    DebugLog.shared.write("[relationships] parse failed (noJSONArrayFound) — retrying once")
                    self.callWithRetry(
                        prompt: prompt,
                        schema: schema,
                        options: options,
                        attemptsRemaining: attemptsRemaining - 1,
                        completion: completion
                    )
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }
}

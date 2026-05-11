import Foundation

/// Phase 4 #7 sub-task 2 — production `LedgerExtractor` adapter.
/// Wraps `OllamaClient` and the `LedgerExtraction` pure-data helpers
/// (prompt builder + JSON Schema + parser) into the protocol
/// `LedgerExtractionCoordinator` consumes.
///
/// Matches the spike runner's behaviour
/// (`Tools/LedgerSpike/main.swift:ollamaExtract`): builds the §3.3
/// extraction prompt against the bible's character list, asks Ollama
/// to constrain output to the `asserted`-only JSON Schema, parses
/// the response with the per-object fallback parser. `unknown` /
/// `mistaken` are NOT extracted (LOOM_STORY_BIBLE §3.5 + spike §8.3:
/// `unknown` is derived from per-character scene-exposure at query
/// time, `mistaken` is manual-authoring).
public final class OllamaLedgerExtractor: LedgerExtractor {
    private let client: OllamaClient

    public init(client: OllamaClient) {
        self.client = client
    }

    /// Convenience initializer used by AppState when constructing the
    /// extractor from the configured `ServerProfile`.
    public convenience init(baseURL: URL, model: String) {
        self.init(client: OllamaClient(baseURL: baseURL, model: model))
    }

    public func extract(
        scenePose: String,
        characters: [LedgerExtraction.CharacterRef],
        completion: @escaping (Result<[LedgerExtraction.ExtractedFact], Error>) -> Void
    ) {
        let prompt = LedgerExtraction.buildExtractionPrompt(
            characters: characters,
            scenePose: scenePose
        )
        let schema = LedgerExtraction.jsonSchema(
            certainties: [.asserted],
            characters: characters
        )
        client.extract(prompt: prompt, schema: schema) { result in
            switch result {
            case .success(let raw):
                do {
                    let facts = try LedgerExtraction.parseExtractedFacts(raw)
                    completion(.success(facts))
                } catch {
                    completion(.failure(error))
                }
            case .failure(let e):
                completion(.failure(e))
            }
        }
    }
}

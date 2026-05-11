import Foundation

/// Test-seam between `OllamaLedgerExtractor` and the network: lets
/// the retry-on-empty behaviour be pinned without an HTTP round-trip.
/// Production: `OllamaClient` conforms; tests inject a stub that
/// returns canned `Result<String, OllamaError>` sequences.
public protocol OllamaCallProvider {
    func call(
        prompt: String,
        schema: [String: Any],
        completion: @escaping (Result<String, OllamaError>) -> Void
    )
}

extension OllamaClient: OllamaCallProvider {
    public func call(
        prompt: String,
        schema: [String: Any],
        completion: @escaping (Result<String, OllamaError>) -> Void
    ) {
        self.extract(prompt: prompt, schema: schema, completion: completion)
    }
}

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
///
/// Retry behaviour: on an empty `message.content` response (the
/// model hit immediate-EOS under JSON-Schema constraint — sampling
/// or transient cold-load roll), retry the same call once before
/// surfacing the failure. Empirically rare (~1 in 10 calls on
/// gemma4_2b at temperature 0.3 in live testing) but visible to the
/// user when it happens because they get zero suggestions instead
/// of seven. Transport failures (`OllamaError.transport`, `.http`,
/// `.noBody`, etc.) are NOT retried — those need higher-level
/// intervention.
public final class OllamaLedgerExtractor: LedgerExtractor {
    private let provider: OllamaCallProvider

    public init(provider: OllamaCallProvider) {
        self.provider = provider
    }

    public convenience init(client: OllamaClient) {
        self.init(provider: client)
    }

    public convenience init(baseURL: URL, model: String) {
        self.init(provider: OllamaClient(baseURL: baseURL, model: model))
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
        callWithRetry(prompt: prompt, schema: schema, attemptsRemaining: 1, completion: completion)
    }

    private func callWithRetry(
        prompt: String,
        schema: [String: Any],
        attemptsRemaining: Int,
        completion: @escaping (Result<[LedgerExtraction.ExtractedFact], Error>) -> Void
    ) {
        // STRONG self capture is load-bearing. The coordinator's
        // extractorProvider closure constructs a fresh
        // OllamaLedgerExtractor per fire and assigns it to a local
        // that goes out of scope when fire() returns. With a weak
        // capture here, the URLSession callback fired into a
        // deallocated self, the `guard let self` bailed, and the
        // coordinator's onExtractionComplete never ran — silently
        // dropping the result (Phase4OllamaExtractorLifetimeTests).
        // Strong capture keeps self alive exactly as long as the
        // URLSession callback retains this closure, which is the
        // window we need.
        provider.call(prompt: prompt, schema: schema) { result in
            switch result {
            case .success(let raw):
                if raw.isEmpty, attemptsRemaining > 0 {
                    DebugLog.shared.write("[ledger] empty extraction response — retrying once")
                    self.callWithRetry(
                        prompt: prompt,
                        schema: schema,
                        attemptsRemaining: attemptsRemaining - 1,
                        completion: completion
                    )
                    return
                }
                do {
                    let facts = try LedgerExtraction.parseExtractedFacts(raw)
                    completion(.success(facts))
                } catch {
                    let snippet = raw.prefix(500).replacingOccurrences(of: "\n", with: "\\n")
                    DebugLog.shared.write("[ledger] parse failed: err=\(error) raw=\"\(snippet)\" len=\(raw.count)")
                    completion(.failure(error))
                }
            case .failure(let e):
                DebugLog.shared.write("[ledger] ollama transport failed: \(e)")
                completion(.failure(e))
            }
        }
    }
}

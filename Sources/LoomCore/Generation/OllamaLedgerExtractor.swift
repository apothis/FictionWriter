import Foundation

/// Test-seam between `OllamaLedgerExtractor` and the network: lets
/// the retry-on-empty + scene-aware budget behaviour be pinned
/// without an HTTP round-trip. Production: `OllamaClient` conforms;
/// tests inject a stub that returns canned
/// `Result<String, OllamaError>` sequences and records the
/// `OllamaChatOptions` it was called with so the auto-budget plumbing
/// is observable.
public protocol OllamaCallProvider {
    func call(
        prompt: String,
        schema: [String: Any],
        options: OllamaChatOptions,
        completion: @escaping (Result<String, OllamaError>) -> Void
    )
}

extension OllamaClient: OllamaCallProvider {
    public func call(
        prompt: String,
        schema: [String: Any],
        options: OllamaChatOptions,
        completion: @escaping (Result<String, OllamaError>) -> Void
    ) {
        self.extract(prompt: prompt, schema: schema, options: options, completion: completion)
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
/// Retry behaviour: on an empty `message.content` response, retry
/// once with `num_predict` doubled before surfacing the failure.
/// Empty content happens for two reasons under JSON-Schema mode:
/// (a) sampling / cold-load roll where the model hits immediate
/// EOS — rare, fixed by any retry; (b) `num_predict` cut the
/// schema-constrained buffer off before it closed, producing
/// `done_reason: length` with empty content (deterministic — same
/// call yields the same empty result, so the retry MUST bump the
/// budget to recover). The doubled-budget retry covers both cases
/// in one shot. The first-attempt budget is scaled per-scene by
/// `budgetForSceneWords(_:)`. Transport failures
/// (`OllamaError.transport`, `.http`, `.noBody`, etc.) are NOT
/// retried — those need higher-level intervention.
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

    /// Scene-aware `num_predict` budget — the model emits ~1 fact
    /// per ~14 scene-words at the §3.3 "be thorough" framing, each
    /// fact serialising to ~70 tokens of JSON, so the call needs
    /// roughly `8 * sceneWords` tokens of headroom to close the
    /// array. Floor `2048` covers short scenes (the live-verified
    /// safe minimum from 2026-05-12); cap `8192` keeps a runaway
    /// scene from monopolising the extractor.
    public static func budgetForSceneWords(_ wordCount: Int) -> Int {
        let scaled = wordCount * 8
        return min(8192, max(2048, scaled))
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
        let initialOptions = OllamaChatOptions(
            numPredict: Self.budgetForSceneWords(WordCount.count(scenePose))
        )
        callWithRetry(
            prompt: prompt,
            schema: schema,
            options: initialOptions,
            attemptsRemaining: 1,
            completion: completion
        )
    }

    private func callWithRetry(
        prompt: String,
        schema: [String: Any],
        options: OllamaChatOptions,
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
        provider.call(prompt: prompt, schema: schema, options: options) { result in
            switch result {
            case .success(let raw):
                if raw.isEmpty, attemptsRemaining > 0 {
                    // Empty content: either a transient sampling
                    // roll OR a deterministic num_predict cap. The
                    // retry doubles the budget so the cap case
                    // recovers; transient rolls also get a fresh
                    // sample.
                    let bumped = min(8192, options.numPredict * 2)
                    let retryOptions = OllamaChatOptions(
                        temperature: options.temperature,
                        numPredict: bumped,
                        repeatPenalty: options.repeatPenalty
                    )
                    DebugLog.shared.write("[ledger] empty extraction response — retrying with num_predict=\(bumped)")
                    self.callWithRetry(
                        prompt: prompt,
                        schema: schema,
                        options: retryOptions,
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

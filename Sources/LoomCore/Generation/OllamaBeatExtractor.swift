import Foundation

/// Phase 7.b.3 — production `BeatExtractor` adapter wrapping
/// `OllamaCallProvider`. Mirrors `OllamaLedgerExtractor` shape:
/// builds the Pass-A prompt + JSON Schema via `BeatExtraction`,
/// fires the call with a source-length-scaled `num_predict` budget,
/// retries once on empty content (deterministic budget-cap recovery).
/// Transport failures are NOT retried — they need higher-level
/// intervention, not budget tweaks.
///
/// Pinned in [`LOOM_SCENE_TEMPLATE.md`](../../../LOOM_SCENE_TEMPLATE.md) §7.1.
public final class OllamaBeatExtractor: BeatExtractor {
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

    /// Source-length-scaled `num_predict` budget. The Pass-A schema
    /// produces ~70 tokens per beat × 5–12 beats + ~50 tokens of
    /// character/setting metadata, so the call needs ~2× the source's
    /// own token count of headroom to close the JSON array cleanly.
    /// Floor `2048` covers short scenes; cap `8192` keeps a runaway
    /// scene from monopolising the extractor.
    public static func budgetForProse(_ sourceProse: String) -> Int {
        let wordCount = sourceProse.split(whereSeparator: { $0.isWhitespace }).count
        // Words ≈ tokens × 0.75 for English prose; double for headroom.
        let scaled = Int(Double(wordCount) * 2.7)
        return min(8192, max(2048, scaled))
    }

    public func extractSkeleton(
        from sourceProse: String,
        completion: @escaping (Result<ExtractedSceneSkeleton, Error>) -> Void
    ) {
        let prompt = BeatExtraction.buildExtractionPrompt(sourceProse: sourceProse)
        let schema = BeatExtraction.jsonSchema()
        let options = OllamaChatOptions(
            // Extraction wants deterministic JSON, not creative
            // variation. Tight sampler matches the LedgerSpike §sampler-
            // rationale + the spike runner's posture.
            temperature: 0.2,
            numPredict: Self.budgetForProse(sourceProse),
            repeatPenalty: 1.1
        )
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
        completion: @escaping (Result<ExtractedSceneSkeleton, Error>) -> Void
    ) {
        // STRONG self capture is load-bearing (per the Phase 4
        // OllamaLedgerExtractor lifetime test): the URLSession
        // callback retains this closure for the duration of the call;
        // capturing self strongly keeps the extractor alive exactly
        // as long as the callback needs it.
        provider.call(prompt: prompt, schema: schema, options: options) { result in
            switch result {
            case .success(let raw):
                if raw.isEmpty, attemptsRemaining > 0 {
                    // Empty content: either a transient sampling roll
                    // OR a deterministic num_predict cap. Bump the
                    // budget and retry — covers both cases in one shot.
                    let bumped = min(8192, options.numPredict * 2)
                    let retryOptions = OllamaChatOptions(
                        temperature: options.temperature,
                        numPredict: bumped,
                        repeatPenalty: options.repeatPenalty
                    )
                    DebugLog.shared.write("[template] empty extraction response — retrying with num_predict=\(bumped)")
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
                    let skeleton = try BeatExtraction.parseExtractedSkeleton(raw)
                    completion(.success(skeleton))
                } catch {
                    let snippet = raw.prefix(500).replacingOccurrences(of: "\n", with: "\\n")
                    DebugLog.shared.write("[template] parse failed: err=\(error) raw=\"\(snippet)\" len=\(raw.count)")
                    completion(.failure(error))
                }
            case .failure(let err):
                // Transport / HTTP / unexpected-shape errors are NOT
                // retried — they need higher-level intervention.
                completion(.failure(err))
            }
        }
    }
}

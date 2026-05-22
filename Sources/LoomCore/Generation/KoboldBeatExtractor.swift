import Foundation

/// Pass-A beat extraction on the **writer** model (KoboldCpp) using a
/// **GBNF grammar** for the structural constraint — the reliable
/// alternative to the Ollama `format`-schema path, which flakes
/// (LOOM_TECH_STACK §3) and, live 2026-05-22, produced a 97KB
/// off-schema body that failed to parse. GBNF guarantees well-formed,
/// on-shape JSON at the sampler level.
///
/// Mirrors `OllamaBeatExtractor`'s retry posture but routes through the
/// `KoboldGenerating` grammar variant:
/// - instruct-wraps the prompt (the writer's `/api/v1/generate` is raw
///   completion with no server-side chat template);
/// - constrains output with `BeatExtraction.gbnfGrammar()`;
/// - strips `<think>` blocks defensively (the writer may be a Thinking
///   model — the grammar should suppress them, but stripping is a cheap
///   guard either way);
/// - tolerant-parses, and retries once on an empty OR malformed roll
///   (both `noJSONObjectFound` and `decodingFailed`).
///
/// Transport failures are NOT retried — they need higher-level
/// intervention, not a re-roll.
public final class KoboldBeatExtractor: BeatExtractor {
    private let client: KoboldGenerating
    private let template: InstructTemplate
    private let baseParams: SamplerParams
    private let maxContextLength: Int
    private let useGrammar: Bool

    /// `useGrammar` defaults to **false** — Pass-A runs unconstrained.
    /// GBNF guarantees well-formed JSON but not *meaningful* structure:
    /// on a reasoning (Thinking) writer, forcing JSON from token 0
    /// suppresses the reasoning the model needs to assign sensible beat
    /// functions + word counts, and it emits valid-but-degenerate
    /// skeletons (live 2026-05-22: 26 beats all `arrival`, targetWords
    /// 0). Unconstrained lets the model think first; we strip the think
    /// block + tolerant-parse the JSON it emits after. Pass `useGrammar:
    /// true` for a non-thinking writer where the grammar's structural
    /// guarantee is a net win.
    public init(
        client: KoboldGenerating,
        template: InstructTemplate = .mistralV7,
        params: SamplerParams = .phase1Defaults,
        maxContextLength: Int = 8192,
        useGrammar: Bool = false
    ) {
        self.client = client
        self.template = template
        self.baseParams = params
        self.maxContextLength = maxContextLength
        self.useGrammar = useGrammar
    }

    /// Source-length-scaled output budget. Same scaling as
    /// `OllamaBeatExtractor.budgetForProse` — the Pass-A skeleton runs
    /// ~70 tokens/beat × 5–12 beats + voice metadata, so ~2× the
    /// source's token count of headroom closes the JSON. Floor 2048,
    /// cap 8192.
    public static func budgetForProse(_ sourceProse: String) -> Int {
        let wordCount = sourceProse.split(whereSeparator: { $0.isWhitespace }).count
        let scaled = Int(Double(wordCount) * 2.7)
        return min(8192, max(2048, scaled))
    }

    public func extractSkeleton(
        from sourceProse: String,
        completion: @escaping (Result<ExtractedSceneSkeleton, Error>) -> Void
    ) {
        // Unconstrained (default): flat structure-of-arrays prompt — the
        // shape small models can produce. GBNF path (useGrammar:true, a
        // non-thinking writer): the nested single-object schema the
        // grammar enforces.
        let prompt = useGrammar
            ? BeatExtraction.buildExtractionPrompt(sourceProse: sourceProse)
            : BeatExtraction.buildFlatPrompt(sourceProse: sourceProse)
        let grammar: String? = useGrammar ? BeatExtraction.gbnfGrammar() : nil
        let adapter = InstructTemplates.adapter(for: template)
        let wrapped = adapter.wrap(system: "", userBody: prompt, prefill: "")

        var params = baseParams
        // Deterministic extraction — tight sampler, not creative.
        params.temperature = 0.2
        // Output budget = the context remaining after the prompt, so a
        // verbose Thinking writer has room for its reasoning AND the full
        // JSON. The old flat 8192 cap was the bug: a reasoner spent most
        // of it thinking and the JSON truncated mid-structure (2026-05-22,
        // on a 16384-context server). Bounded at 12288 so a huge context
        // doesn't license an unbounded run.
        let promptTokens = TokenEstimator.estimate(wrapped)
        params.maxLength = max(2048, min(maxContextLength - promptTokens - 256, 12288))

        callWithRetry(
            wrapped: wrapped,
            stops: adapter.stopSequences,
            params: params,
            grammar: grammar,
            attemptsRemaining: 1,
            completion: completion
        )
    }

    private func callWithRetry(
        wrapped: String,
        stops: [String],
        params: SamplerParams,
        grammar: String?,
        attemptsRemaining: Int,
        completion: @escaping (Result<ExtractedSceneSkeleton, Error>) -> Void
    ) {
        // STRONG self capture (per the OllamaLedgerExtractor lifetime
        // test): the URLSession callback retains this closure for the
        // call's duration; capturing self strongly keeps the extractor
        // alive exactly that long.
        client.generate(
            prompt: wrapped,
            stopSequences: stops,
            params: params,
            maxContextLength: maxContextLength,
            grammar: grammar
        ) { result in
            switch result {
            case .success(let raw):
                // Strip the reasoning block. On the unconstrained path
                // (the default) the Thinking writer reasons first, THEN
                // emits the JSON — so the `<think>`/`<|channel>thought`
                // span is expected here and must come off before the
                // tolerant parser looks for the `{...}`.
                let cleaned = ThinkBlockStripper.strip(raw)
                if cleaned.isEmpty, attemptsRemaining > 0 {
                    var bumped = params
                    bumped.maxLength = min(12288, params.maxLength * 2)
                    DebugLog.shared.write("[template] empty extraction (kobold) — retrying with maxLength=\(bumped.maxLength)")
                    self.callWithRetry(
                        wrapped: wrapped, stops: stops, params: bumped,
                        grammar: grammar, attemptsRemaining: attemptsRemaining - 1,
                        completion: completion
                    )
                    return
                }
                do {
                    let skeleton = self.useGrammar
                        ? try BeatExtraction.parseExtractedSkeleton(cleaned)
                        : try BeatExtraction.parseFlatSkeleton(cleaned)
                    completion(.success(skeleton))
                } catch let parseError as BeatExtraction.ParseError where attemptsRemaining > 0 {
                    // A malformed/missing-brace roll is transient — re-roll
                    // once (matches OllamaBeatExtractor's retry set).
                    let snippet = cleaned.prefix(200).replacingOccurrences(of: "\n", with: "\\n")
                    DebugLog.shared.write("[template] parse failed (kobold, \(parseError)) — retrying once. raw=\"\(snippet)\" len=\(cleaned.count)")
                    self.callWithRetry(
                        wrapped: wrapped, stops: stops, params: params,
                        grammar: grammar, attemptsRemaining: attemptsRemaining - 1,
                        completion: completion
                    )
                } catch {
                    let snippet = cleaned.prefix(500).replacingOccurrences(of: "\n", with: "\\n")
                    DebugLog.shared.write("[template] parse failed (kobold): err=\(error) raw=\"\(snippet)\" len=\(cleaned.count)")
                    completion(.failure(error))
                }
            case .failure(let err):
                completion(.failure(err))
            }
        }
    }
}

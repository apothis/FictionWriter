import Foundation

/// Pure-data Kobold→NarrativeMode wiring for Phase 5 scope-lock #5
/// production. Mirrors [`KoboldEmbeddingsRequest`](EmbeddingClients.swift)
/// / [`KoboldEmbeddingsResponse`](EmbeddingClients.swift): the prompt
/// template, GBNF grammar, request body shape, and response parser
/// are TDD'd here; the URLSession glue is a thin synchronous wrapper
/// below, used by the ingest pipeline at ingest time (not on a hot
/// retrieval path).
///
/// Grammar + prompt structure match the
/// [LOOM_NARRATIVE_MODE_SPIKE](../../LOOM_NARRATIVE_MODE_SPIKE.md)
/// §10 PROCEED config: gemma-4-31B zero-shot + flat enum GBNF. Few-shot
/// was tested and DROPPED — it collapsed predictions to `mixed` (§8(a)).
public enum KoboldNarrativeModeRequest {
    /// Flat-enum grammar — the Bastan et al. 2025 "Lost in Space"
    /// failure-mode fix. Nested JSON wrapping caused the original
    /// Path C descriptor collapse in LOOM_RAG_SPIKE §13.3(c); this
    /// alternation-only grammar dodges that failure mode directly.
    public static let grammar: String = "root ::= \(NarrativeMode.gbnfAlternation)"

    public static func zeroShotPrompt(passage: String) -> String {
        """
        Classify this prose passage's primary narrative mode.

        Categories:
        - action: physical action / external events
        - dialogue: character speech
        - interiority: internal thought, feeling, or free-indirect discourse
        - description: settings, objects, sensory environment, suspended time
        - summary: compressed-time narration (e.g. "for three weeks…")
        - mixed: genuinely 50/50 across two modes

        Passage:
        \(passage)

        Mode:
        """
    }

    public static func body(passage: String) -> Data {
        let payload: [String: Any] = [
            "prompt": zeroShotPrompt(passage: passage),
            "max_length": 8,
            "max_context_length": 8192,
            "temperature": 0.0,
            "rep_pen": 1.0,
            "grammar": grammar,
        ]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }

    /// Parse Kobold's `/api/v1/generate` response into a NarrativeMode.
    /// Returns nil on:
    /// - malformed JSON
    /// - empty `results` array
    /// - leading/trailing whitespace is tolerated (per "Lost in Space"
    ///   2025 — grammar-constrained decoding occasionally emits stray
    ///   whitespace before the first valid token)
    /// - non-enum text content (out-of-grammar output, e.g. "narrative")
    public static func parse(_ data: Data) -> NarrativeMode? {
        struct Wire: Decodable {
            let results: [Item]
            struct Item: Decodable { let text: String }
        }
        guard let wire = try? JSONDecoder().decode(Wire.self, from: data) else { return nil }
        guard let raw = wire.results.first?.text else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return NarrativeMode(rawValue: trimmed)
    }
}

/// Synchronous wrapper used by [`ReferenceIngestPipeline`](ReferenceIngestPipeline.swift)
/// to wire its `modalityLLM` closure to Kobold. Blocks the calling
/// thread until the response (or timeout / error). Ingest is a batch
/// operation, typically run off the main thread; blocking is
/// acceptable for the use case but should never be called on the
/// main thread.
public enum KoboldNarrativeModeClassifier {
    /// Returns a closure suitable for `ReferenceIngestPipeline.modalityLLM`.
    /// `baseURL` is the Kobold server root (e.g.
    /// http://192.168.1.201:5001/). Timeout default 120s — gemma-31B
    /// at typical local speed returns in under 2s, so timeout exists
    /// to recover from a wedged server, not to bound success-case
    /// latency.
    public static func makeClosure(
        baseURL: URL,
        timeoutSeconds: TimeInterval = 120
    ) -> (String) -> NarrativeMode? {
        return { passage in
            guard let url = URL(string: "api/v1/generate", relativeTo: baseURL)?.absoluteURL else {
                return nil
            }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = KoboldNarrativeModeRequest.body(passage: passage)
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForRequest = timeoutSeconds
            let session = URLSession(configuration: cfg)
            let sem = DispatchSemaphore(value: 0)
            var result: NarrativeMode? = nil
            let task = session.dataTask(with: req) { data, _, err in
                if err == nil, let data {
                    result = KoboldNarrativeModeRequest.parse(data)
                }
                sem.signal()
            }
            task.resume()
            sem.wait()
            return result
        }
    }
}

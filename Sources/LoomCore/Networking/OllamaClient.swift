import Foundation

/// Sampler options for an Ollama chat call. Extraction defaults:
/// temperature 0.3 (deterministic-leaning, not zero — Gemma 4 emits
/// degenerate outputs at exactly 0 under JSON-Schema constraint),
/// num_predict 2048, repeat_penalty 1.1 (load-bearing — see
/// LOOM_LEDGER_SPIKE §9.4 / §10.4 for the degenerate-loop failure
/// mode this prevents).
///
/// **num_predict 2048 — load-bearing under JSON-Schema mode.**
/// Ollama's `format`-constrained pipeline buffers tokens until the
/// schema accepts a valid completion; if `num_predict` cuts off
/// before that, `done_reason == "length"` and `message.content` is
/// **empty** (not truncated). The §11/§12 spike used 1024 against
/// the fixture's ~150-word scenes, but production scenes routinely
/// hit 300-400 words — gemma4_2b needs ~1600 tokens to close a
/// 25-fact array for those, so 1024 silently empties out. Confirmed
/// live 2026-05-12 against a 312-word scene: 1024 → empty content +
/// `done_reason: length`; 2048 → 25 facts + `done_reason: stop` at
/// eval_count 1612. See HANDOFF §15.7 sibling — the retry-on-empty
/// path can't recover this deterministically-empty case (re-firing
/// with the same options yields the same length-cap).
public struct OllamaChatOptions: Equatable {
    public var temperature: Double
    public var numPredict: Int
    public var repeatPenalty: Double
    /// Phrase-level anti-slop banlist. Honoured only by the
    /// `KoboldCallProvider` (KoboldCpp `banned_strings`); the Ollama
    /// transport ignores it — hence it is not in `asDictionary`.
    public var bannedStrings: [String]

    public init(
        temperature: Double = 0.3,
        numPredict: Int = 2048,
        repeatPenalty: Double = 1.1,
        bannedStrings: [String] = []
    ) {
        self.temperature = temperature
        self.numPredict = numPredict
        self.repeatPenalty = repeatPenalty
        self.bannedStrings = bannedStrings
    }

    public var asDictionary: [String: Any] {
        return [
            "temperature": temperature,
            "num_predict": numPredict,
            "repeat_penalty": repeatPenalty,
        ]
    }
}

public enum OllamaError: Error, Equatable {
    case badURL
    case http(Int, String)
    case noBody
    case unexpectedShape
    case transport(String)
}

/// HTTP client for an Ollama endpoint speaking `/api/chat` with
/// JSON-Schema-constrained outputs. Phase 4 #7 role-routed extractor
/// transport — lifted from the spike's `ollamaExtract` free function
/// (`Tools/LedgerSpike/main.swift`) into LoomCore so the production
/// post-scene side-call (sub-task 2) can hit the same path. The
/// `parseChatResponseContent` + `makeChatRequestBody` helpers are
/// pure-data so the wire shape is testable without spinning a fake
/// HTTP server; the `extract(prompt:schema:completion:)` method is
/// honest-smoke (covered by the spike runner against a live server).
public final class OllamaClient {
    public let baseURL: URL
    public let model: String
    private let session: URLSession

    public init(
        baseURL: URL,
        model: String,
        timeout: TimeInterval = 600
    ) {
        self.baseURL = baseURL
        self.model = model
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = timeout
        cfg.timeoutIntervalForResource = 0
        self.session = URLSession(configuration: cfg)
    }

    /// The resolved /api/chat URL. Trailing slash on `baseURL` is
    /// optional; both forms produce the same absolute URL.
    public var chatURL: URL {
        // Use components instead of URL(string:relativeTo:) so the
        // result is independent of trailing-slash quirks in baseURL.
        var c = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        let basePath = c?.path ?? ""
        c?.path = basePath.hasSuffix("/")
            ? basePath + "api/chat"
            : basePath + "/api/chat"
        return c?.url ?? baseURL.appendingPathComponent("api/chat")
    }

    /// Build the JSON request body sent to /api/chat. Pure-data so
    /// tests can pin the wire shape without an HTTP round-trip.
    public static func makeChatRequestBody(
        model: String,
        prompt: String,
        schema: [String: Any],
        options: OllamaChatOptions
    ) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": prompt]],
            // Streaming mode — load-bearing. Ollama's NON-streaming
            // /api/chat with gemma4 intermittently returns an empty
            // `message.content` despite a full token generation
            // (`done: stop`, eval_count ~2000) — verified live
            // 2026-05-16, ~2/3 on a dense scene. Streaming assembles
            // the content per-chunk and does not hit that bug; the
            // caller collects the whole newline-delimited body and
            // concatenates (see parseChatResponseContent).
            "stream": true,
            "options": options.asDictionary,
            // `keep_alive` overrides Ollama's default 5-minute unload
            // timer. With the default, a writer who pauses to think
            // for 6+ minutes finds the model cold on their next save,
            // and the first cold-load inference under JSON-Schema
            // constraint occasionally emits an empty string (verified
            // live 2026-05-11). 30 minutes covers realistic editing
            // gaps while still letting the model unload eventually.
            "keep_alive": "30m",
        ]
        // An empty schema means unconstrained generation — omit the
        // `format` key entirely. Ollama's format-constrained pipeline
        // intermittently degenerates into a non-terminating buffer
        // that hits num_predict and returns empty content (verified
        // live 2026-05-16, ~50% on gemma4_2b); discovery callers opt
        // out by passing [:] and pinning the field names in-prompt.
        if !schema.isEmpty {
            body["format"] = schema
        }
        return body
    }

    /// Extract the assistant text from an /api/chat response body.
    /// Handles both shapes: a single JSON object (non-streaming) and
    /// a newline-delimited sequence of chunk objects (streaming) —
    /// the latter is concatenated. Throws `OllamaError.unexpectedShape`
    /// when no `message.content` is found anywhere (garbage payloads,
    /// `done`-only error frames).
    public static func parseChatResponseContent(from data: Data) throws -> String {
        // Non-streaming: the whole body is one JSON object.
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let msg = obj["message"] as? [String: Any],
           let content = msg["content"] as? String {
            return content
        }
        // Streaming: newline-delimited chunk objects; concatenate
        // every chunk's `message.content`.
        guard let text = String(data: data, encoding: .utf8) else {
            throw OllamaError.unexpectedShape
        }
        var assembled = ""
        var sawMessage = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let msg = obj["message"] as? [String: Any],
                  let content = msg["content"] as? String
            else { continue }
            assembled += content
            sawMessage = true
        }
        guard sawMessage else { throw OllamaError.unexpectedShape }
        return assembled
    }

    /// Fire a chat-extraction call. Completion runs on a background
    /// queue; caller marshals to main as appropriate. The model is
    /// taken from `self.model`; pass the JSON Schema in `schema`.
    public func extract(
        prompt: String,
        schema: [String: Any],
        options: OllamaChatOptions = OllamaChatOptions(),
        completion: @escaping (Result<String, OllamaError>) -> Void
    ) {
        var req = URLRequest(url: chatURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = OllamaClient.makeChatRequestBody(
            model: model,
            prompt: prompt,
            schema: schema,
            options: options
        )
        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(.unexpectedShape))
            return
        }
        req.httpBody = data
        let started = Date()
        let task = session.dataTask(with: req) { respData, resp, err in
            let elapsed = -started.timeIntervalSinceNow
            if let err = err {
                DebugLog.shared.write("[ollama] dataTask err after \(String(format: "%.1f", elapsed))s: \(err.localizedDescription)")
                completion(.failure(.transport(err.localizedDescription)))
                return
            }
            if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
                let body = respData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                DebugLog.shared.write("[ollama] dataTask http \(http.statusCode) after \(String(format: "%.1f", elapsed))s")
                completion(.failure(.http(http.statusCode, body)))
                return
            }
            guard let respData = respData else {
                DebugLog.shared.write("[ollama] dataTask no body after \(String(format: "%.1f", elapsed))s")
                completion(.failure(.noBody))
                return
            }
            DebugLog.shared.write("[ollama] dataTask ok in \(String(format: "%.1f", elapsed))s bytes=\(respData.count)")
            do {
                let content = try OllamaClient.parseChatResponseContent(from: respData)
                completion(.success(content))
            } catch let e as OllamaError {
                completion(.failure(e))
            } catch {
                completion(.failure(.unexpectedShape))
            }
        }
        task.resume()
    }
}

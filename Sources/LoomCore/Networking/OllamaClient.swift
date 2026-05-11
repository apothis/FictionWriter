import Foundation

/// Sampler options for an Ollama chat call. Extraction defaults match
/// the spike's `ollamaExtract` in `Tools/LedgerSpike/main.swift`:
/// temperature 0.3 (deterministic-leaning, not zero — Gemma 4 emits
/// degenerate outputs at exactly 0 under JSON-Schema constraint),
/// num_predict 1024 (matches the §11/§12 spike), repeat_penalty 1.1
/// (load-bearing — see LOOM_LEDGER_SPIKE §9.4 / §10.4 for the
/// degenerate-loop failure mode this prevents).
public struct OllamaChatOptions: Equatable {
    public var temperature: Double
    public var numPredict: Int
    public var repeatPenalty: Double

    public init(
        temperature: Double = 0.3,
        numPredict: Int = 1024,
        repeatPenalty: Double = 1.1
    ) {
        self.temperature = temperature
        self.numPredict = numPredict
        self.repeatPenalty = repeatPenalty
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
        return [
            "model": model,
            "messages": [["role": "user", "content": prompt]],
            "stream": false,
            "options": options.asDictionary,
            "format": schema,
            // `keep_alive` overrides Ollama's default 5-minute unload
            // timer. With the default, a writer who pauses to think
            // for 6+ minutes finds the model cold on their next save,
            // and the first cold-load inference under JSON-Schema
            // constraint occasionally emits an empty string (verified
            // live 2026-05-11). 30 minutes covers realistic editing
            // gaps while still letting the model unload eventually.
            "keep_alive": "30m",
        ]
    }

    /// Extract `message.content` from a non-streaming /api/chat
    /// response. Throws `OllamaError.unexpectedShape` when the JSON
    /// doesn't have the expected `{ message: { content: String } }`
    /// shape (covers garbage payloads and `done`-only error frames).
    public static func parseChatResponseContent(from data: Data) throws -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OllamaError.unexpectedShape
        }
        guard let msg = obj["message"] as? [String: Any],
              let content = msg["content"] as? String else {
            throw OllamaError.unexpectedShape
        }
        return content
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

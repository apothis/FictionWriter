import Foundation

public struct GenerateRequest {
    public var prompt: String
    public var stopSequences: [String]
    public var params: SamplerParams
    public var maxContextLength: Int
    /// Per-request override for the reply token cap. nil = use params.maxLength.
    public var maxLengthOverride: Int?
    /// Optional GBNF grammar string that constrains token sampling to
    /// grammar-conformant tokens. KoboldCpp's `grammar` parameter on
    /// `/api/v1/generate` (verified against the production server
    /// 2026-05-11). Phase 4 #7 (knowledge-ledger extraction) uses this
    /// to guarantee well-formed JSON output without prompt tricks; see
    /// LedgerExtraction.gbnfGrammar() + LOOM_LEDGER_SPIKE §8.1.
    public var grammar: String?

    public init(
        prompt: String,
        stopSequences: [String] = [],
        params: SamplerParams,
        maxContextLength: Int,
        maxLengthOverride: Int? = nil,
        grammar: String? = nil
    ) {
        self.prompt = prompt
        self.stopSequences = stopSequences
        self.params = params
        self.maxContextLength = maxContextLength
        self.maxLengthOverride = maxLengthOverride
        self.grammar = grammar
    }
}

public enum KoboldError: Error, Equatable {
    case badURL
    case http(Int, String)
    case noBody
    case unexpectedShape

    public static func == (lhs: KoboldError, rhs: KoboldError) -> Bool {
        switch (lhs, rhs) {
        case (.badURL, .badURL): return true
        case (.noBody, .noBody): return true
        case (.unexpectedShape, .unexpectedShape): return true
        case (.http(let lc, let lm), .http(let rc, let rm)): return lc == rc && lm == rm
        default: return false
        }
    }
}

/// Loom's HTTP wrapper around koboldcpp. Single-prompt streaming +
/// non-streaming completion against `/api/extra/generate/stream` and
/// `/api/v1/generate`; metadata via `/api/v1/model`,
/// `/api/extra/version`, `/api/extra/true_max_context_length`,
/// `/api/extra/tokencount`. Direct port from RPClient with the
/// chatCompletions path removed (Phase 1 doesn't use it). Embed path
/// re-added in Phase 4 #7 for ledger-fact similarity scoring +
/// deduplication (LOOM_LEDGER_SPIKE §10).
public final class KoboldClient: NSObject, URLSessionDataDelegate, KoboldGenerating, KoboldEmbedding {
    public private(set) var baseURL: URL
    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 600
        cfg.timeoutIntervalForResource = 0
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()

    private var streamBuffer = Data()
    private var onToken: ((String) -> Void)?
    private var onFinish: ((Error?) -> Void)?
    private var activeTask: URLSessionDataTask?
    private var activeSideCallTask: URLSessionDataTask?

    public init(baseURL: URL) {
        self.baseURL = baseURL
        super.init()
    }

    public func setBaseURL(_ url: URL) {
        self.baseURL = url
    }

    // MARK: - Streaming generation

    public func generateStream(
        request: GenerateRequest,
        onToken: @escaping (String) -> Void,
        onFinish: @escaping (Error?) -> Void
    ) {
        cancel()
        guard let url = URL(string: "/api/extra/generate/stream", relativeTo: baseURL)?.absoluteURL else {
            onFinish(KoboldError.badURL)
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.httpBody = try? JSONSerialization.data(withJSONObject: streamBody(for: request))

        self.streamBuffer = Data()
        self.onToken = onToken
        self.onFinish = onFinish

        let task = session.dataTask(with: req)
        self.activeTask = task
        task.resume()
    }

    public func cancel() {
        activeTask?.cancel()
        activeTask = nil
        activeSideCallTask?.cancel()
        activeSideCallTask = nil
        // Best-effort server-side abort. Works for both streaming and side-calls.
        guard let url = URL(string: "/api/extra/abort", relativeTo: baseURL)?.absoluteURL else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = "{}".data(using: .utf8)
        let abort = URLSession.shared.dataTask(with: req)
        abort.resume()
    }

    // MARK: - URLSessionDataDelegate

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        streamBuffer.append(data)
        processBuffer()
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let cb = self.onFinish
        self.onFinish = nil
        self.onToken = nil
        self.activeTask = nil
        if let error = error as NSError?, error.code == NSURLErrorCancelled {
            cb?(nil)
        } else {
            cb?(error)
        }
    }

    private func processBuffer() {
        // SSE frames separated by blank line ("\n\n"). Each frame has
        // "event:" and "data:" lines.
        while let range = streamBuffer.range(of: Data("\n\n".utf8)) {
            let frameData = streamBuffer.subdata(in: 0..<range.lowerBound)
            streamBuffer.removeSubrange(0..<range.upperBound)
            guard let frameText = String(data: frameData, encoding: .utf8) else { continue }
            handleFrame(frameText)
        }
    }

    private func handleFrame(_ frame: String) {
        var dataLines: [String] = []
        for line in frame.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line)
            if s.hasPrefix("data:") {
                let v = s.dropFirst(5)
                let trimmed = v.first == " " ? String(v.dropFirst()) : String(v)
                dataLines.append(trimmed)
            }
        }
        guard !dataLines.isEmpty else { return }
        let payload = dataLines.joined(separator: "\n")
        guard let pd = payload.data(using: .utf8) else { return }
        if let obj = try? JSONSerialization.jsonObject(with: pd) as? [String: Any] {
            if let tok = obj["token"] as? String {
                onToken?(tok)
            }
        }
    }

    // MARK: - Non-streaming generation (KoboldGenerating)

    /// Non-streaming generation. `KoboldGenerating` conformance — used by
    /// future side-calls and for simple Continue/Expand calls that don't
    /// need token-by-token streaming. Phase 1 .i wires Continue through
    /// the streaming path; non-streaming sits ready.
    public func generate(
        prompt: String,
        stopSequences: [String],
        params: SamplerParams,
        maxContextLength: Int,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        generate(
            request: GenerateRequest(
                prompt: prompt,
                stopSequences: stopSequences,
                params: params,
                maxContextLength: maxContextLength
            ),
            completion: completion
        )
    }

    /// Streaming overload — overrides the default protocol-extension
    /// fallback (which would deliver the entire response as a single
    /// `onToken` call). Each chunk from
    /// `/api/extra/generate/stream` is forwarded straight to
    /// `onToken`; `completion` fires once at the end with the
    /// concatenated full text.
    public func generate(
        prompt: String,
        stopSequences: [String],
        params: SamplerParams,
        maxContextLength: Int,
        onToken: @escaping (String) -> Void,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let request = GenerateRequest(
            prompt: prompt,
            stopSequences: stopSequences,
            params: params,
            maxContextLength: maxContextLength
        )
        var accumulated = ""
        generateStream(
            request: request,
            onToken: { token in
                accumulated += token
                // generateStream's URLSession delegate runs on a
                // private serial queue (delegateQueue: nil). Marshal
                // to main here so callers don't have to repeat the
                // hop in every onToken closure.
                DispatchQueue.main.async { onToken(token) }
            },
            onFinish: { error in
                DispatchQueue.main.async {
                    if let error = error {
                        completion(.failure(error))
                    } else {
                        completion(.success(accumulated))
                    }
                }
            }
        )
    }

    /// Non-streaming generation taking a full `GenerateRequest`. Use
    /// this overload when you need to pass fields beyond the basic
    /// prompt/sampler set — specifically `grammar` for GBNF-constrained
    /// extraction calls (LedgerSpike / Phase 4 #7).
    public func generate(
        request: GenerateRequest,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard let url = URL(string: "/api/v1/generate", relativeTo: baseURL)?.absoluteURL else {
            completion(.failure(KoboldError.badURL)); return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: nonStreamBody(for: request))
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 600
        let s = URLSession(configuration: cfg)
        let task = s.dataTask(with: req) { [weak self] data, _, err in
            self?.activeSideCallTask = nil
            if let err = err as NSError?, err.code == NSURLErrorCancelled {
                completion(.failure(err))
                return
            }
            if let err = err { completion(.failure(err)); return }
            guard let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = obj["results"] as? [[String: Any]],
                  let text = results.first?["text"] as? String else {
                completion(.failure(KoboldError.unexpectedShape))
                return
            }
            completion(.success(text))
        }
        activeSideCallTask = task
        task.resume()
    }

    // MARK: - Embeddings (KoboldEmbedding)

    /// Batched text → vector embeddings via KoboldCpp's `/v1/embeddings`.
    /// Server must be launched with `--embeddingsmodel <gguf>` (verified
    /// against production: bge-small-en-v1.5, 384-d). Ported from
    /// RPClient's `KoboldClient.embed`; same wire format, same shape.
    public func embed(
        texts: [String],
        completion: @escaping (Result<[[Float]], Error>) -> Void
    ) {
        guard !texts.isEmpty else { completion(.success([])); return }
        guard let url = URL(string: "/v1/embeddings", relativeTo: baseURL)?.absoluteURL else {
            completion(.failure(KoboldError.badURL)); return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "input": texts,
            "model": "embedding",
        ])
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 120
        let s = URLSession(configuration: cfg)
        s.dataTask(with: req) { data, resp, err in
            if let err = err { completion(.failure(err)); return }
            guard let data = data else {
                completion(.failure(KoboldError.noBody)); return
            }
            if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                let msg = String(data: data, encoding: .utf8) ?? ""
                completion(.failure(KoboldError.http(http.statusCode, msg)))
                return
            }
            do {
                guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let dataArr = obj["data"] as? [[String: Any]]
                else {
                    completion(.failure(KoboldError.unexpectedShape)); return
                }
                let vecs: [[Float]] = dataArr.compactMap { entry in
                    guard let raw = entry["embedding"] as? [Any] else { return nil }
                    return raw.compactMap { ($0 as? NSNumber)?.floatValue }
                }
                completion(.success(vecs))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    // MARK: - Misc endpoints

    public func fetchModel(completion: @escaping (Result<String, Error>) -> Void) {
        getJSON(path: "/api/v1/model") { result in
            switch result {
            case .success(let obj):
                if let dict = obj as? [String: Any], let r = dict["result"] as? String {
                    completion(.success(r))
                } else {
                    completion(.success("?"))
                }
            case .failure(let e): completion(.failure(e))
            }
        }
    }

    public func fetchTrueMaxContext(completion: @escaping (Result<Int, Error>) -> Void) {
        getJSON(path: "/api/extra/true_max_context_length") { result in
            switch result {
            case .success(let obj):
                if let dict = obj as? [String: Any],
                   let v = (dict["value"] as? NSNumber)?.intValue {
                    completion(.success(v))
                } else {
                    completion(.success(4096))
                }
            case .failure(let e): completion(.failure(e))
            }
        }
    }

    public func tokenCount(text: String, completion: @escaping (Result<Int, Error>) -> Void) {
        guard let url = URL(string: "/api/extra/tokencount", relativeTo: baseURL)?.absoluteURL else {
            completion(.failure(KoboldError.badURL)); return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["prompt": text])
        URLSession.shared.dataTask(with: req) { data, _, err in
            if let err = err { completion(.failure(err)); return }
            guard let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { completion(.success(0)); return }
            if let v = obj["value"] as? Int { completion(.success(v)) }
            else { completion(.success(0)) }
        }.resume()
    }

    private func getJSON(path: String, completion: @escaping (Result<Any, Error>) -> Void) {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            completion(.failure(KoboldError.badURL)); return
        }
        URLSession.shared.dataTask(with: url) { data, _, err in
            if let err = err { completion(.failure(err)); return }
            guard let data = data else { completion(.failure(KoboldError.noBody)); return }
            do {
                let obj = try JSONSerialization.jsonObject(with: data)
                completion(.success(obj))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    // MARK: - Body assembly

    private func streamBody(for r: GenerateRequest) -> [String: Any] {
        var b = baseBody(for: r)
        b["stream_sse"] = true
        return b
    }

    private func nonStreamBody(for r: GenerateRequest) -> [String: Any] {
        baseBody(for: r)
    }

    private func baseBody(for r: GenerateRequest) -> [String: Any] {
        let p = r.params
        var body: [String: Any] = [
            "prompt": r.prompt,
            "max_length": r.maxLengthOverride ?? p.maxLength,
            "max_context_length": r.maxContextLength,
            "temperature": p.temperature,
            "top_p": p.topP,
            "top_k": p.topK,
            "min_p": p.minP,
            "rep_pen": p.repPen,
            "rep_pen_range": p.repPenRange,
            "sampler_order": p.samplerOrder,
            "stop_sequence": r.stopSequences,
            "trim_stop": true,
            "dry_multiplier": p.dryMultiplier,
            "dry_base": p.dryBase,
            "dry_allowed_length": p.dryAllowedLength,
            "xtc_threshold": p.xtcThreshold,
            "xtc_probability": p.xtcProbability,
        ]
        if let grammar = r.grammar, !grammar.isEmpty {
            body["grammar"] = grammar
        }
        if !p.bannedStrings.isEmpty {
            body["banned_strings"] = p.bannedStrings
        }
        return body
    }
}

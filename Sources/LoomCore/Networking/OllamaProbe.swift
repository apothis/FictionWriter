import Foundation

/// "Test connection" probe for an Ollama endpoint. Sibling of
/// `ServerProbe` (which handles `.kobold` profiles); the Settings UI
/// branches on `ServerProfile.kind` to pick the right one. Ollama's
/// liveness endpoint is `GET /api/tags`, which returns the loaded
/// models list. The pure parse helper folds the first model's name
/// into a `ServerCapabilities` snapshot so the existing
/// `AutoProbe.applyResult` machinery caches it on the profile
/// unchanged.
///
/// `version` and `trueMaxContext` are nil because Ollama's
/// `/api/version` is a separate endpoint and the per-model context
/// limit isn't reported by `/api/tags`. Phase 4.x can extend if the
/// extractor side-call needs to know it.
public enum OllamaProbe {
    public enum ProbeError: Error, CustomStringConvertible {
        case timedOut
        case http(Int)
        case transport(Error)
        case unreachable
        case noModelsLoaded

        public var description: String {
            switch self {
            case .timedOut: return "Timed out"
            case .http(let code): return "HTTP \(code)"
            case .transport(let e): return "Network: \(e.localizedDescription)"
            case .unreachable: return "Unreachable"
            case .noModelsLoaded: return "No models loaded"
            }
        }
    }

    public static let timeout: TimeInterval = 5

    /// Parse the response body from `GET /api/tags`. Returns a
    /// `ServerCapabilities` whose `modelName` is the first model in
    /// the array, or nil when the array is empty or the payload
    /// shape is unexpected.
    public static func parseTagsResponse(from data: Data) -> ServerCapabilities? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        guard let models = obj["models"] as? [[String: Any]],
              let first = models.first,
              let name = first["name"] as? String,
              !name.isEmpty else {
            return nil
        }
        return ServerCapabilities(modelName: name, trueMaxContext: nil, version: nil)
    }

    /// Probe `baseURL` (`GET /api/tags`) and yield `ServerCapabilities`
    /// on success or a `ProbeError` on failure. Async dispatch on a
    /// background queue.
    public static func probe(
        baseURL: URL,
        completion: @escaping (Result<ServerCapabilities, ProbeError>) -> Void
    ) {
        guard let url = URL(string: "/api/tags", relativeTo: baseURL)?.absoluteURL else {
            completion(.failure(.unreachable))
            return
        }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeout
        cfg.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: cfg)
        let task = session.dataTask(with: url) { data, resp, err in
            if let err = err {
                let nsErr = err as NSError
                let probeErr: ProbeError =
                    nsErr.code == NSURLErrorTimedOut ? .timedOut
                    : nsErr.code == NSURLErrorCannotConnectToHost ? .unreachable
                    : .transport(err)
                completion(.failure(probeErr))
                return
            }
            if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
                completion(.failure(.http(http.statusCode)))
                return
            }
            guard let data = data, let caps = parseTagsResponse(from: data) else {
                completion(.failure(.noModelsLoaded))
                return
            }
            completion(.success(caps))
        }
        task.resume()
    }
}

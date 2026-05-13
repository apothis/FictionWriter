import Foundation
import LoomCore

// Phase 5 RAG-for-style spike runner (LOOM_RAG_SPIKE.md §6 S3).
//
// One-off eval harness. Talks to the local Kobold + Ollama servers
// directly; reads vectors.json produced by the Python sidecar for
// Paths D + E (LOOM_RAG_SPIKE.md §6 S5.5). Not part of the standard
// test suite — invoke explicitly:
//
//     swift run RagSpike --smoke           # S3 smoke check; ~5s per backend
//     swift run RagSpike --corpus          # full embedding sweep (S4+ scope)
//
// **S3 scope (this commit):** `--smoke` only. The default mode prints
// help and exits. The `--corpus` mode lands in S4 when the scoring
// pipeline is ready to consume the output.

// MARK: - Stderr helper

struct FileHandleOutputStream: TextOutputStream {
    let handle: FileHandle
    init(_ handle: FileHandle) { self.handle = handle }
    mutating func write(_ string: String) { handle.write(Data(string.utf8)) }
}
var stderrStream = FileHandleOutputStream(FileHandle.standardError)
func log(_ s: String) { print(s, to: &stderrStream) }

// MARK: - Config

let koboldURLString = ProcessInfo.processInfo.environment["LOOM_SPIKE_BASE_URL"]
    ?? "http://192.168.1.201:5001/"
let ollamaURLString = ProcessInfo.processInfo.environment["LOOM_SPIKE_OLLAMA_URL"]
    ?? "http://localhost:11434/"
let ollamaModelMxbai = "mxbai-embed-large"
let ollamaModelBge = "bge-large"
let pythonVectorsPath = "Tools/RagSpike/vectors.json"

// MARK: - Synchronous HTTP wrappers

func postJSON(url: URL, body: Data, timeoutSeconds: TimeInterval) -> Result<Data, Error> {
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = body
    let cfg = URLSessionConfiguration.default
    cfg.timeoutIntervalForRequest = timeoutSeconds
    let session = URLSession(configuration: cfg)
    let sem = DispatchSemaphore(value: 0)
    var result: Result<Data, Error> = .failure(NSError(domain: "RagSpike", code: -1))
    let task = session.dataTask(with: req) { data, _, err in
        if let err { result = .failure(err) }
        else if let data { result = .success(data) }
        sem.signal()
    }
    task.resume()
    sem.wait()
    return result
}

// MARK: - Path A: Kobold nomic-embed

func embedKoboldNomic(_ text: String) -> EmbeddingVector? {
    guard let url = URL(string: "v1/embeddings", relativeTo: URL(string: koboldURLString))?.absoluteURL else {
        return nil
    }
    let body = KoboldEmbeddingsRequest.body(input: text)
    switch postJSON(url: url, body: body, timeoutSeconds: 60) {
    case .success(let data): return KoboldEmbeddingsResponse.decode(data)
    case .failure(let e): log("[A] network error: \(e)"); return nil
    }
}

// MARK: - Path B: Ollama (mxbai + bge)

func embedOllama(_ text: String, model: String) -> EmbeddingVector? {
    guard let url = URL(string: "api/embed", relativeTo: URL(string: ollamaURLString))?.absoluteURL else {
        return nil
    }
    let body = OllamaEmbedRequest.body(model: model, input: text)
    switch postJSON(url: url, body: body, timeoutSeconds: 60) {
    case .success(let data): return OllamaEmbedResponse.decode(data)
    case .failure(let e): log("[B/\(model)] network error: \(e)"); return nil
    }
}

// MARK: - Path C: writer-distilled descriptor (gemma-4-31B GBNF)

/// GBNF grammar that constrains gemma's output to a single JSON object
/// with the style-descriptor fields. The descriptor is then converted
/// back to a natural-language string and embedded via Path A.
let descriptorGrammar: String = """
root        ::= "{" ws "\\"sentence_length\\":" ws slen "," ws "\\"modality\\":" ws mod "," ws "\\"tense\\":" ws tense "," ws "\\"pov\\":" ws pov "," ws "\\"register\\":" ws reg ws "}"
slen        ::= "\\"short\\"" | "\\"medium\\"" | "\\"long\\""
mod         ::= "\\"action\\"" | "\\"dialogue\\"" | "\\"interiority\\"" | "\\"description\\""
tense       ::= "\\"past\\"" | "\\"present\\""
pov         ::= "\\"first\\"" | "\\"tight_third\\"" | "\\"omniscient\\""
reg         ::= "\\"literary\\"" | "\\"pulpy\\"" | "\\"clinical\\"" | "\\"journalistic\\""
ws          ::= [ \\t\\n]*
"""

struct StyleDescriptor: Decodable {
    let sentence_length: String
    let modality: String
    let tense: String
    let pov: String
    let register: String

    /// Convert to a short embedding-friendly sentence — the input the
    /// nomic-embed call sees for Path C.
    var asEmbeddingText: String {
        "Prose style: sentence_length \(sentence_length), modality \(modality), tense \(tense), point of view \(pov), register \(register)."
    }
}

func generateDescriptor(for text: String) -> StyleDescriptor? {
    guard let url = URL(string: "api/v1/generate", relativeTo: URL(string: koboldURLString))?.absoluteURL else {
        return nil
    }
    let prompt = """
    You are analysing prose style. Read the passage below and emit a structured JSON descriptor of its style. The JSON keys are sentence_length (short|medium|long), modality (action|dialogue|interiority|description), tense (past|present), pov (first|tight_third|omniscient), register (literary|pulpy|clinical|journalistic).

    Passage:
    \(text)

    JSON output:
    """
    let body: [String: Any] = [
        "prompt": prompt,
        "max_length": 128,
        "max_context_length": 8192,
        "temperature": 0.3,
        "rep_pen": 1.1,
        "grammar": descriptorGrammar,
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
    switch postJSON(url: url, body: data, timeoutSeconds: 120) {
    case .success(let data):
        struct GenerateResponse: Decodable {
            let results: [Item]
            struct Item: Decodable { let text: String }
        }
        guard let resp = try? JSONDecoder().decode(GenerateResponse.self, from: data),
              let raw = resp.results.first?.text else { return nil }
        // The grammar prefills `{`-shape, so the raw output should be
        // pure JSON. Decode directly.
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let jsonData = trimmed.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(StyleDescriptor.self, from: jsonData)
    case .failure(let e):
        log("[C] network error: \(e)"); return nil
    }
}

func embedDescriptor(_ text: String) -> EmbeddingVector? {
    guard let descriptor = generateDescriptor(for: text) else { return nil }
    log("[C] descriptor: \(descriptor.asEmbeddingText)")
    return embedKoboldNomic(descriptor.asEmbeddingText)
}

// MARK: - Path D + E: read Python vectors.json

struct VectorsPayload: Decodable {
    let version: Int
    let paths: [PathBlock]
    struct PathBlock: Decodable {
        let path: String
        let model: String
        let dim: Int
        let vectors: [String: [Float]]
    }
}

func loadPythonVectors() -> VectorsPayload? {
    let cwd = FileManager.default.currentDirectoryPath
    let url = URL(fileURLWithPath: cwd).appendingPathComponent(pythonVectorsPath)
    guard let data = try? Data(contentsOf: url) else {
        log("[D/E] \(pythonVectorsPath) not found — run `python3 Tools/RagSpike/Python/embed_offline.py` first")
        return nil
    }
    return try? JSONDecoder().decode(VectorsPayload.self, from: data)
}

// MARK: - Smoke mode

func smoke() -> Int32 {
    let testText = "She walked into the kitchen. The kettle was on. She did not say anything."
    log("=== RagSpike smoke ===")
    log("Test input: \"\(testText)\"")
    log("")

    var passes = 0
    var fails = 0

    func check(_ label: String, _ block: () -> EmbeddingVector?) {
        let started = Date()
        if let vec = block() {
            let elapsed = Date().timeIntervalSince(started)
            let first3 = vec.values.prefix(3).map { String(format: "%.4f", $0) }.joined(separator: ", ")
            let paddedLabel = label.padding(toLength: 22, withPad: " ", startingAt: 0)
            log("  PASS  \(paddedLabel) dim=\(vec.dim)  first3=[\(first3)]  \(String(format: "%.2fs", elapsed))")
            passes += 1
        } else {
            log("  FAIL  \(label)")
            fails += 1
        }
    }

    check("A: nomic (Kobold)") { embedKoboldNomic(testText) }
    check("B: mxbai (Ollama)") { embedOllama(testText, model: ollamaModelMxbai) }
    check("B: bge (Ollama)") { embedOllama(testText, model: ollamaModelBge) }
    check("C: descriptor+nomic") { embedDescriptor(testText) }

    // Path D + E come from the Python sidecar.
    log("")
    if let payload = loadPythonVectors() {
        log("vectors.json: version \(payload.version), \(payload.paths.count) paths")
        for p in payload.paths {
            let paddedPath = p.path.padding(toLength: 22, withPad: " ", startingAt: 0)
            log("  \(paddedPath) dim=\(p.dim)  items=\(p.vectors.count)  model=\(p.model)")
            passes += 1
        }
    } else {
        log("  SKIP  D/E (no vectors.json)")
    }

    log("")
    log("\(passes) passed, \(fails) failed")
    return fails == 0 ? 0 : 1
}

// MARK: - Entry

let args = CommandLine.arguments.dropFirst()
if args.contains("--smoke") {
    exit(smoke())
} else if args.contains("--corpus") {
    log("--corpus mode lands in LOOM_RAG_SPIKE §6 S4. Not yet implemented.")
    exit(2)
} else {
    log("usage: swift run RagSpike --smoke")
    log("       swift run RagSpike --corpus    (not yet implemented; S4)")
    log("")
    log("env overrides:")
    log("  LOOM_SPIKE_BASE_URL   (default \(koboldURLString))")
    log("  LOOM_SPIKE_OLLAMA_URL (default \(ollamaURLString))")
    exit(2)
}

import Foundation
import LoomCore

// Phase 8.a §6.1 — Embedder discrimination spike runner.
//
// See LOOM_SCENE_EXEMPLAR.md §6.1 + LOOM_SCENE_EXEMPLAR_RESEARCH.md for
// the design + the four-candidate set (StyleDistance / Wegmann / LUAR /
// mxbai). This file is the integration glue around the pure-data types
// in LoomCore — fixture loading, subprocess/HTTP embedders, and the
// subcommand dispatch.
//
// Usage:
//   swift run SceneExemplarSpike cosine-matrix --embedder=styledistance
//   swift run SceneExemplarSpike cosine-matrix --embedder=wegmann
//   swift run SceneExemplarSpike cosine-matrix --embedder=luar
//   swift run SceneExemplarSpike cosine-matrix --embedder=mxbai
//
// Env:
//   LOOM_SPIKE_VENV     default Tools/RagSpike/Python/.venv/bin/python3
//   LOOM_SPIKE_OLLAMA   default http://localhost:11434

// MARK: - stderr helper

struct FileHandleStream: TextOutputStream {
    let handle: FileHandle
    init(_ handle: FileHandle) { self.handle = handle }
    mutating func write(_ string: String) { handle.write(Data(string.utf8)) }
}
var stderrStream = FileHandleStream(FileHandle.standardError)
func log(_ s: String) { print(s, to: &stderrStream) }

// MARK: - Paths + config

let fixturesDir = "Tools/SceneExemplarSpike/fixtures"
let outputDir = "Tools/SceneExemplarSpike/last-run"

let pythonExecutable: URL = {
    let env = ProcessInfo.processInfo.environment["LOOM_SPIKE_VENV"]
        ?? "Tools/RagSpike/Python/.venv/bin/python3"
    return URL(fileURLWithPath: env)
}()

let embedScriptPath = URL(fileURLWithPath: "Tools/SceneExemplarSpike/Python/embed_st.py")

let ollamaBaseURL: URL = {
    let env = ProcessInfo.processInfo.environment["LOOM_SPIKE_OLLAMA"]
        ?? "http://localhost:11434"
    return URL(string: env)!
}()

// MARK: - Embedder catalog (id → backend)

struct EmbedderSpec {
    let id: String                          // CLI name + report id
    let role: String                        // report subtitle
    let backend: Backend

    enum Backend {
        /// Python sentence-transformers via embed_st.py.
        case subprocess(model: String, trustRemoteCode: Bool)
        /// Ollama HTTP /api/embeddings.
        case ollama(model: String)
    }
}

let embedderCatalog: [String: EmbedderSpec] = [
    "styledistance": EmbedderSpec(
        id: "StyleDistance/styledistance",
        role: "incumbent (style) — Phase 5 retrieval embedder; the §6.1 hypothesis is *about* this one",
        backend: .subprocess(model: "StyleDistance/styledistance", trustRemoteCode: true)
    ),
    "wegmann": EmbedderSpec(
        id: "AnnaWegmann/Style-Embedding",
        role: "primary style alternate — canonical STEL baseline, iBERT substitute",
        backend: .subprocess(model: "AnnaWegmann/Style-Embedding", trustRemoteCode: false)
    ),
    "luar": EmbedderSpec(
        id: "gabrielloiseau/LUAR-MUD-sentence-transformers",
        role: "predicted negative control — authorship embedder; expected to fail register discrimination per Wegmann TACL + StyleDistance paper",
        backend: .subprocess(model: "gabrielloiseau/LUAR-MUD-sentence-transformers", trustRemoteCode: false)
    ),
    "mxbai": EmbedderSpec(
        id: "mxbai-embed-large (Ollama)",
        role: "retrieval baseline — topical-cosine reference",
        backend: .ollama(model: "mxbai-embed-large")
    ),
]

// MARK: - Subprocess embedder

/// Long-lived Python subprocess wrapping sentence-transformers.
/// Spawns `embed_st.py --model <id>` once; per-call write+read on
/// stdin/stdout. Mirrors the existing PythonStyleDistanceClient
/// pattern but is parameterized by model id.
final class SubprocessEmbedder: SpikeEmbedder {
    let id: String
    private let model: String
    private let trustRemoteCode: Bool
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutBuffer = Data()
    private var stdoutPipeRead: FileHandle?

    init(id: String, model: String, trustRemoteCode: Bool) {
        self.id = id
        self.model = model
        self.trustRemoteCode = trustRemoteCode
    }

    deinit {
        stdinHandle?.closeFile()
        process?.waitUntilExit()
    }

    func embed(_ text: String) -> EmbeddingVector? {
        do { try ensureStarted() } catch {
            log("[subprocess:\(model)] start failed: \(error)")
            return nil
        }
        guard let stdin = stdinHandle else { return nil }

        let req: [String: Any] = ["text": text]
        guard let data = try? JSONSerialization.data(withJSONObject: req) else { return nil }
        var line = data
        line.append(0x0a)
        do { try stdin.write(contentsOf: line) } catch { return nil }

        while let respLine = readLine() {
            if let any = try? JSONSerialization.jsonObject(with: respLine),
               let dict = any as? [String: Any] {
                if dict["ready"] != nil { continue }
                if let err = dict["error"] as? String {
                    log("[subprocess:\(model)] embed error: \(err)")
                    return nil
                }
                if let vec = dict["vec"] as? [Double] {
                    return EmbeddingVector(values: vec.map { Float($0) })
                }
            }
        }
        return nil
    }

    private func ensureStarted() throws {
        if process != nil { return }
        let task = Process()
        task.executableURL = pythonExecutable
        var args = [embedScriptPath.path, "--model", model]
        if trustRemoteCode { args.append("--trust-remote-code") }
        task.arguments = args

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        task.standardInput = stdinPipe
        task.standardOutput = stdoutPipe
        // Surface subprocess stderr to our stderr — useful for HF download progress + errors.
        let stderrPipe = Pipe()
        task.standardError = stderrPipe
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                FileHandle.standardError.write(data)
            }
        }

        log("[subprocess:\(model)] spawning embed_st.py (this may take a minute on first model load)...")
        try task.run()
        self.process = task
        self.stdinHandle = stdinPipe.fileHandleForWriting
        self.stdoutPipeRead = stdoutPipe.fileHandleForReading

        // Wait for `{"ready": true}` before returning. Long timeout because
        // first-time HF model downloads can take minutes on a slow link.
        let deadline = Date().addingTimeInterval(600)
        while Date() < deadline {
            guard let line = readLine() else {
                throw NSError(domain: "SubprocessEmbedder", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "subprocess exited before ready"
                ])
            }
            if let any = try? JSONSerialization.jsonObject(with: line),
               let dict = any as? [String: Any] {
                if dict["ready"] != nil { return }
                if let err = dict["error"] as? String {
                    throw NSError(domain: "SubprocessEmbedder", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: "subprocess startup error: \(err)"
                    ])
                }
            }
        }
        throw NSError(domain: "SubprocessEmbedder", code: 3, userInfo: [
            NSLocalizedDescriptionKey: "ready timeout (600s)"
        ])
    }

    private func readLine() -> Data? {
        guard let handle = stdoutPipeRead else { return nil }
        while !stdoutBuffer.contains(0x0a) {
            let chunk = handle.availableData
            if chunk.isEmpty { return nil }
            stdoutBuffer.append(chunk)
        }
        guard let newlineIdx = stdoutBuffer.firstIndex(of: 0x0a) else { return nil }
        let line = stdoutBuffer[..<newlineIdx]
        stdoutBuffer.removeSubrange(...newlineIdx)
        return Data(line)
    }
}

// MARK: - Ollama HTTP embedder

/// Wraps the Ollama daemon's POST /api/embeddings endpoint. Single
/// blocking call per embed; URLSession + a semaphore to make it
/// synchronous so it conforms to SpikeEmbedder.
final class OllamaEmbedder: SpikeEmbedder {
    let id: String
    private let model: String

    init(id: String, model: String) {
        self.id = id
        self.model = model
    }

    func embed(_ text: String) -> EmbeddingVector? {
        let url = ollamaBaseURL.appendingPathComponent("api/embeddings")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["model": model, "prompt": text]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        req.httpBody = bodyData
        req.timeoutInterval = 120

        let sem = DispatchSemaphore(value: 0)
        var result: EmbeddingVector?
        var err: Error?
        URLSession.shared.dataTask(with: req) { data, response, error in
            defer { sem.signal() }
            if let error = error { err = error; return }
            guard let data = data,
                  let any = try? JSONSerialization.jsonObject(with: data),
                  let dict = any as? [String: Any],
                  let vec = dict["embedding"] as? [Double] else {
                if let data = data, let s = String(data: data, encoding: .utf8) {
                    log("[ollama:\(self.model)] unexpected response: \(s.prefix(200))")
                }
                return
            }
            result = EmbeddingVector(values: vec.map { Float($0) })
        }.resume()
        sem.wait()
        if let err = err {
            log("[ollama:\(model)] error: \(err)")
        }
        return result
    }
}

// MARK: - Chunking decorator
//
// BERT-class embedders cap at ~512 tokens (mxbai rejects outright;
// sentence-transformers models silently truncate). For uniform
// fixture-level vectors across all 4 candidates, we chunk each
// ~400-word fixture into 250-word windows, embed each window, and
// mean-pool the resulting vectors. RagChunker is reused from Phase 5.

final class ChunkingEmbedder: SpikeEmbedder {
    let id: String
    private let inner: SpikeEmbedder
    private let chunkSize: Int

    init(_ inner: SpikeEmbedder, chunkSize: Int = 250) {
        self.id = inner.id
        self.inner = inner
        self.chunkSize = chunkSize
    }

    func embed(_ text: String) -> EmbeddingVector? {
        let chunks = RagChunker.chunk(text, size: chunkSize, overlap: 0)
        guard !chunks.isEmpty else { return nil }
        var vectors: [EmbeddingVector] = []
        for chunk in chunks {
            guard let v = inner.embed(chunk.text) else { return nil }
            vectors.append(v)
        }
        return meanPool(vectors)
    }

    private func meanPool(_ vectors: [EmbeddingVector]) -> EmbeddingVector? {
        guard let first = vectors.first else { return nil }
        let dim = first.dim
        var acc = [Float](repeating: 0, count: dim)
        for v in vectors {
            guard v.dim == dim else { return nil }
            for i in 0..<dim { acc[i] += v.values[i] }
        }
        let n = Float(vectors.count)
        for i in 0..<dim { acc[i] /= n }
        // L2 normalize so cosine math is consistent with the
        // sentence-transformers `normalize_embeddings=True` setting.
        var norm: Float = 0
        for x in acc { norm += x * x }
        norm = sqrt(norm)
        guard norm > 0 else { return EmbeddingVector(values: acc) }
        for i in 0..<dim { acc[i] /= norm }
        return EmbeddingVector(values: acc)
    }
}

// MARK: - Fixture loader

func loadAllFixtures() throws -> [SceneExemplarFixture] {
    let fm = FileManager.default
    let dirURL = URL(fileURLWithPath: fixturesDir)
    let files = try fm.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "md" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    var fixtures: [SceneExemplarFixture] = []
    for url in files {
        let text = try String(contentsOf: url, encoding: .utf8)
        let f = try SceneExemplarFixtureParser.parse(text)
        fixtures.append(f)
    }
    return fixtures
}

// MARK: - Subcommand dispatch

func usageAndExit() -> Never {
    let names = embedderCatalog.keys.sorted().joined(separator: " | ")
    log("usage:")
    log("  swift run SceneExemplarSpike cosine-matrix --embedder=<\(names)>")
    log("")
    log("Output: Markdown report written to \(outputDir)/<embedder>.md and stdout.")
    exit(2)
}

let args = CommandLine.arguments
guard args.count >= 2 else { usageAndExit() }

switch args[1] {
case "cosine-matrix":
    var embedderKey: String?
    var scope: String = "all"
    for arg in args.dropFirst(2) {
        if arg.hasPrefix("--embedder=") {
            embedderKey = String(arg.dropFirst("--embedder=".count))
        } else if arg.hasPrefix("--scope=") {
            scope = String(arg.dropFirst("--scope=".count))
        }
    }
    guard let key = embedderKey, let spec = embedderCatalog[key] else {
        log("error: --embedder=<id> required; one of \(embedderCatalog.keys.sorted())")
        exit(2)
    }
    guard ["all", "nsfw", "sfw"].contains(scope) else {
        log("error: --scope must be one of: all | nsfw | sfw")
        exit(2)
    }

    log("[spike] loading fixtures from \(fixturesDir)...")
    var fixtures: [SceneExemplarFixture]
    do {
        fixtures = try loadAllFixtures()
    } catch {
        log("[spike] fixture load failed: \(error)")
        exit(1)
    }
    switch scope {
    case "nsfw": fixtures = fixtures.filter(\.nsfw)
    case "sfw":  fixtures = fixtures.filter { !$0.nsfw }
    default: break
    }
    log("[spike] loaded \(fixtures.count) fixtures (scope=\(scope))")

    let baseEmbedder: SpikeEmbedder
    switch spec.backend {
    case let .subprocess(model, trust):
        baseEmbedder = SubprocessEmbedder(id: spec.id, model: model, trustRemoteCode: trust)
    case let .ollama(model):
        baseEmbedder = OllamaEmbedder(id: spec.id, model: model)
    }
    // Uniform fixture-level vectors across all 4 embedders: 250-word
    // chunks → embed each → mean-pool. Keeps the comparison fair
    // (mxbai hard-rejects long input; ST models silently truncate).
    let embedder: SpikeEmbedder = ChunkingEmbedder(baseEmbedder, chunkSize: 250)

    log("[spike] embedding \(fixtures.count) fixtures with \(spec.id)...")
    let started = Date()
    let result: SpikeOrchestratorResult
    do {
        result = try SpikeOrchestrator.cosineMatrix(fixtures: fixtures, embedder: embedder)
    } catch {
        log("[spike] orchestrator failed: \(error)")
        exit(1)
    }
    let elapsed = Date().timeIntervalSince(started)
    log(String(format: "[spike] embedded %d fixtures in %.1fs", fixtures.count, elapsed))

    let report = EmbedderReportFormatter.formatReport(
        embedderId: spec.id,
        embedderRole: spec.role,
        matrix: result.matrix,
        registerScore: result.registerScore,
        styleAxisScore: result.styleAxisScore
    )

    print(report)

    // Persist a per-embedder file under last-run/ for aggregation into
    // LOOM_SCENE_EXEMPLAR_SPIKE.md.
    do {
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: outputDir),
            withIntermediateDirectories: true
        )
        let suffix = scope == "all" ? "" : ".\(scope)"
        let outFile = URL(fileURLWithPath: outputDir).appendingPathComponent("\(key)\(suffix).md")
        try report.write(to: outFile, atomically: true, encoding: .utf8)
        log("[spike] wrote \(outFile.path)")
    } catch {
        log("[spike] failed to persist report: \(error)")
    }

case "extract":
    // §6.3 / Phase 8 sanity probe — does gemma4_2b Pass-A extraction work
    // on NSFW fixtures? If extraction refuses or fails on the NSFW set,
    // the entire Phase 8 design has a load-bearing assumption to fix.
    var only: [String] = []
    for arg in args.dropFirst(2) {
        if arg.hasPrefix("--fixture=") {
            only.append(String(arg.dropFirst("--fixture=".count)))
        }
    }
    log("[spike] loading fixtures...")
    let allFixtures: [SceneExemplarFixture]
    do { allFixtures = try loadAllFixtures() } catch {
        log("[spike] fixture load failed: \(error)"); exit(1)
    }
    let target = only.isEmpty
        ? allFixtures
        : allFixtures.filter { only.contains($0.id) }
    let ollamaBase = ProcessInfo.processInfo.environment["LOOM_SPIKE_OLLAMA_URL"]
        ?? "http://localhost:11434/"
    let model = ProcessInfo.processInfo.environment["LOOM_SPIKE_OLLAMA_MODEL"]
        ?? "gemma4_2b:latest"
    guard let baseURL = URL(string: ollamaBase) else { exit(1) }
    let extractor = OllamaBeatExtractor(baseURL: baseURL, model: model)

    try? FileManager.default.createDirectory(
        at: URL(fileURLWithPath: outputDir),
        withIntermediateDirectories: true
    )

    for fixture in target {
        log("[extract] \(fixture.id) (\(fixture.body.split(whereSeparator: { $0.isWhitespace }).count) words)...")
        let sem = DispatchSemaphore(value: 0)
        var result: Result<ExtractedSceneSkeleton, Error>?
        let started = Date()
        extractor.extractSkeleton(from: fixture.body) { res in
            result = res
            sem.signal()
        }
        sem.wait()
        let elapsed = Date().timeIntervalSince(started)
        switch result {
        case .success(let skeleton):
            log(String(format: "[extract] %@ → %d beats in %.1fs",
                       fixture.id, skeleton.beats.count, elapsed))
            // Persist the skeleton + a short summary line.
            let outURL = URL(fileURLWithPath: outputDir)
                .appendingPathComponent("\(fixture.id).beats.json")
            if let data = try? JSONEncoder().encode(skeleton) {
                try? data.write(to: outURL)
            }
            let summaryLines: [String] = skeleton.beats.map { beat in
                "  beat \(beat.index) (\(beat.modality.rawValue)/\(beat.function.rawValue), \(beat.targetWords)w): \(beat.summary.prefix(70))..."
            }
            for line in summaryLines { log(line) }
        case .failure(let err):
            log("[extract] \(fixture.id) FAILED: \(err)")
        case .none:
            log("[extract] \(fixture.id) — no result")
        }
    }

default:
    usageAndExit()
}

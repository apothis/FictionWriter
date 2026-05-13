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

// MARK: - Fixture types

struct Fixture: Decodable {
    let excerpts: [Item]
    let queries: [Item]
    struct Item: Decodable {
        let id: Int
        let style: String
        let topic: String
        let nsfw: Bool
        let text: String
    }
}

func loadFixture() -> Fixture? {
    let cwd = FileManager.default.currentDirectoryPath
    let url = URL(fileURLWithPath: cwd).appendingPathComponent("Tests/LoomCoreTests/Fixtures/RagSpike/fixture.json")
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(Fixture.self, from: data)
}

// MARK: - Corpus mode

/// Embed every item via the given path-name + embedder closure.
/// Returns `[id: EmbeddingVector]`. Skips items where the embedder
/// returns nil and logs the failure; the caller decides whether to
/// proceed with a partial result.
func embedAll(
    _ items: [Fixture.Item],
    label: String,
    embedder: (String) -> EmbeddingVector?
) -> [Int: EmbeddingVector] {
    var result: [Int: EmbeddingVector] = [:]
    for item in items {
        guard let vec = embedder(item.text) else {
            log("  [\(label)] FAIL on item \(item.id) (\(item.style)/\(item.topic))")
            continue
        }
        result[item.id] = vec
    }
    return result
}

struct PathResult {
    let name: String
    let model: String
    let dim: Int
    /// Per-query: (queryId, ranked excerpt ids)
    let rankings: [(Int, [Int])]
    /// Per-query NDCG@3 (binary style-match) — same order as rankings.
    let ndcgs: [Double]
    /// Per-query style-vs-topic preference — same order.
    let preferences: [Double]
}

func score(
    pathName: String,
    model: String,
    dim: Int,
    fixture: Fixture,
    vectors: [Int: EmbeddingVector]
) -> PathResult {
    var rankings: [(Int, [Int])] = []
    var ndcgs: [Double] = []
    var preferences: [Double] = []

    for query in fixture.queries {
        guard let queryVec = vectors[query.id] else {
            rankings.append((query.id, []))
            ndcgs.append(0.0)
            preferences.append(0.0)
            continue
        }
        let excerptPairs: [(Int, EmbeddingVector)] = fixture.excerpts.compactMap { ex in
            guard let v = vectors[ex.id] else { return nil }
            return (ex.id, v)
        }
        let ranking = RankingMetrics.rankExcerpts(query: queryVec, excerpts: excerptPairs)
        rankings.append((query.id, ranking))

        // Gold: same-style excerpts.
        let styleMatch = Set(fixture.excerpts.filter { $0.style == query.style }.map { $0.id })
        let topicMatch = Set(fixture.excerpts.filter { $0.topic == query.topic }.map { $0.id })

        let ndcg = RankingMetrics.ndcg(at: 3, gold: styleMatch, ranking: ranking)
        ndcgs.append(ndcg)

        let top3 = Array(ranking.prefix(3))
        let pref = RankingMetrics.styleTopicPreference(
            top3: top3,
            styleMatch: styleMatch,
            topicMatch: topicMatch
        )
        preferences.append(pref)
    }

    return PathResult(
        name: pathName, model: model, dim: dim,
        rankings: rankings, ndcgs: ndcgs, preferences: preferences
    )
}

func mean(_ xs: [Double]) -> Double {
    guard !xs.isEmpty else { return 0 }
    return xs.reduce(0, +) / Double(xs.count)
}

/// NSFW-vs-SFW parity audit (LOOM_RAG_SPIKE §6 S5.5). For each NSFW
/// query, compute how many of its top-3 same-style hits are NSFW vs
/// SFW excerpts. A path that systematically deranks NSFW at equivalent
/// style match is a production-relevant Loom-specific finding.
func nsfwParity(fixture: Fixture, result: PathResult) -> (nsfwHitRate: Double, sfwHitRate: Double) {
    // Across queries, count: of the top-3 same-style hits, what
    // fraction are NSFW vs SFW excerpts? Compares against the
    // fixture's same-style NSFW/SFW availability.
    var nsfwHits = 0
    var sfwHits = 0
    var nsfwAvailable = 0
    var sfwAvailable = 0
    for (i, query) in fixture.queries.enumerated() {
        let ranking = result.rankings[i].1
        let top3 = Set(ranking.prefix(3))
        let sameStyle = fixture.excerpts.filter { $0.style == query.style }
        for ex in sameStyle {
            if ex.nsfw { nsfwAvailable += 1 } else { sfwAvailable += 1 }
            if top3.contains(ex.id) {
                if ex.nsfw { nsfwHits += 1 } else { sfwHits += 1 }
            }
        }
    }
    let nsfwRate = nsfwAvailable > 0 ? Double(nsfwHits) / Double(nsfwAvailable) : 0
    let sfwRate = sfwAvailable > 0 ? Double(sfwHits) / Double(sfwAvailable) : 0
    return (nsfwRate, sfwRate)
}

func corpus() -> Int32 {
    log("=== RagSpike --corpus ===")
    guard let fixture = loadFixture() else {
        log("FATAL: could not load fixture")
        return 1
    }
    log("Fixture: \(fixture.excerpts.count) excerpts + \(fixture.queries.count) queries")
    log("")

    var pathResults: [PathResult] = []
    let allItems = fixture.excerpts + fixture.queries

    // Path A
    log("[A] embedding \(allItems.count) items via Kobold nomic...")
    let aStart = Date()
    let aVecs = embedAll(allItems, label: "A") { embedKoboldNomic($0) }
    log("  A: \(aVecs.count) vectors  \(String(format: "%.1fs", Date().timeIntervalSince(aStart)))")
    pathResults.append(score(
        pathName: "A-nomic", model: "kobold/nomic-embed-text",
        dim: aVecs.values.first?.dim ?? 0,
        fixture: fixture, vectors: aVecs
    ))

    // Path B (mxbai)
    log("[B-mxbai] embedding via Ollama mxbai-embed-large...")
    let bmStart = Date()
    let bmVecs = embedAll(allItems, label: "B-mxbai") { embedOllama($0, model: ollamaModelMxbai) }
    log("  B-mxbai: \(bmVecs.count) vectors  \(String(format: "%.1fs", Date().timeIntervalSince(bmStart)))")
    pathResults.append(score(
        pathName: "B-mxbai", model: "ollama/mxbai-embed-large",
        dim: bmVecs.values.first?.dim ?? 0,
        fixture: fixture, vectors: bmVecs
    ))

    // Path B (bge)
    log("[B-bge] embedding via Ollama bge-large...")
    let bgStart = Date()
    let bgVecs = embedAll(allItems, label: "B-bge") { embedOllama($0, model: ollamaModelBge) }
    log("  B-bge: \(bgVecs.count) vectors  \(String(format: "%.1fs", Date().timeIntervalSince(bgStart)))")
    pathResults.append(score(
        pathName: "B-bge", model: "ollama/bge-large",
        dim: bgVecs.values.first?.dim ?? 0,
        fixture: fixture, vectors: bgVecs
    ))

    // Path C (descriptor + nomic) — slow, ~6s per item, so warn first.
    log("[C] descriptor distillation + nomic embed; ~\(allItems.count * 6)s expected...")
    let cStart = Date()
    let cVecs = embedAll(allItems, label: "C") { embedDescriptor($0) }
    log("  C: \(cVecs.count) vectors  \(String(format: "%.1fs", Date().timeIntervalSince(cStart)))")
    pathResults.append(score(
        pathName: "C-descriptor", model: "kobold/gemma-4-31B+nomic (GBNF descriptor)",
        dim: cVecs.values.first?.dim ?? 0,
        fixture: fixture, vectors: cVecs
    ))

    // Paths D + E from Python sidecar
    if let payload = loadPythonVectors() {
        for p in payload.paths {
            var vecs: [Int: EmbeddingVector] = [:]
            for (idStr, arr) in p.vectors {
                if let id = Int(idStr) {
                    vecs[id] = EmbeddingVector(values: arr)
                }
            }
            log("[\(p.path)] loaded \(vecs.count) vectors from vectors.json")
            pathResults.append(score(
                pathName: p.path, model: p.model, dim: p.dim,
                fixture: fixture, vectors: vecs
            ))
        }
    } else {
        log("[D/E] vectors.json missing — run python3 Tools/RagSpike/Python/embed_offline.py first")
    }

    // Report
    log("")
    log("=== Per-path aggregate (mean over 4 queries) ===")
    log("")
    log("| Path                     | dim  | NDCG@3 | preference | NSFW hit | SFW hit |")
    log("|--------------------------|------|--------|------------|----------|---------|")
    for r in pathResults {
        let avgNdcg = mean(r.ndcgs)
        let avgPref = mean(r.preferences)
        let parity = nsfwParity(fixture: fixture, result: r)
        let nameCol = r.name.padding(toLength: 24, withPad: " ", startingAt: 0)
        log(String(format: "| %@ | %4d | %.3f  | %+.3f     | %.3f    | %.3f   |",
                   nameCol, r.dim, avgNdcg, avgPref, parity.nsfwHitRate, parity.sfwHitRate))
    }

    log("")
    log("=== Per-query × per-path breakdown ===")
    log("")
    for (i, q) in fixture.queries.enumerated() {
        log("Q\(q.id) [\(q.style)/\(q.topic), NSFW=\(q.nsfw ? "Y" : "N")]:")
        for r in pathResults {
            let nameCol = r.name.padding(toLength: 24, withPad: " ", startingAt: 0)
            let top3 = Array(r.rankings[i].1.prefix(3)).map { String($0) }.joined(separator: ",")
            log(String(format: "  %@ NDCG=%.2f  pref=%+.2f  top3=[%@]",
                       nameCol, r.ndcgs[i], r.preferences[i], top3))
        }
        log("")
    }

    // Save raw rankings to last-run for follow-up analysis
    let cwd = FileManager.default.currentDirectoryPath
    let lastRunDir = URL(fileURLWithPath: cwd)
        .appendingPathComponent("Tools/RagSpike/last-run")
    try? FileManager.default.createDirectory(at: lastRunDir, withIntermediateDirectories: true)

    // Dump per-path summary as JSON for downstream tooling
    var dump: [[String: Any]] = []
    for r in pathResults {
        let parity = nsfwParity(fixture: fixture, result: r)
        dump.append([
            "path": r.name,
            "model": r.model,
            "dim": r.dim,
            "ndcg_mean": mean(r.ndcgs),
            "preference_mean": mean(r.preferences),
            "ndcg_per_query": r.ndcgs,
            "preference_per_query": r.preferences,
            "rankings": r.rankings.map { ["query_id": $0.0, "ranking": $0.1] },
            "nsfw_hit_rate": parity.nsfwHitRate,
            "sfw_hit_rate": parity.sfwHitRate,
        ])
    }
    let dumpURL = lastRunDir.appendingPathComponent("rankings.json")
    if let data = try? JSONSerialization.data(withJSONObject: dump, options: [.prettyPrinted, .sortedKeys]) {
        try? data.write(to: dumpURL)
        log("Wrote \(dumpURL.path)")
    }

    return 0
}

// MARK: - Hybrid retrieval validation (Phase 5 scope-lock #4)

/// Loads D (StyleDistance) + E (function-word z-score) vectors from
/// Tools/RagSpike/vectors.json, runs both as per-path top-12 rankings,
/// merges via Reciprocal Rank Fusion (k=10, equal weights — the
/// scope-lock #4 decision), and scores the hybrid alongside the
/// individual paths. Behavioural validation that RRF preserves the
/// §13.1 metrics without smearing toward one embedder.
func hybrid() -> Int32 {
    log("=== RagSpike --hybrid (D + E via RRF k=10) ===")
    guard let fixture = loadFixture() else {
        log("FATAL: could not load fixture")
        return 1
    }
    guard let payload = loadPythonVectors() else {
        log("FATAL: Tools/RagSpike/vectors.json missing — run python3 Tools/RagSpike/Python/embed_offline.py first")
        return 1
    }

    func vectorsFor(_ pathPrefix: String) -> [Int: EmbeddingVector]? {
        guard let block = payload.paths.first(where: { $0.path.hasPrefix(pathPrefix) }) else {
            return nil
        }
        var out: [Int: EmbeddingVector] = [:]
        for (idStr, arr) in block.vectors {
            if let id = Int(idStr) { out[id] = EmbeddingVector(values: arr) }
        }
        return out
    }

    guard let dVecs = vectorsFor("D-styledistance"),
          let eVecs = vectorsFor("E-funcword-z") else {
        log("FATAL: missing D or E in vectors.json")
        return 1
    }

    var pathResults: [PathResult] = []
    pathResults.append(score(pathName: "D-styledistance", model: payload.paths[0].model,
                              dim: dVecs.values.first?.dim ?? 0,
                              fixture: fixture, vectors: dVecs))
    pathResults.append(score(pathName: "E-funcword-z", model: "loom/funcword-z-top150",
                              dim: eVecs.values.first?.dim ?? 0,
                              fixture: fixture, vectors: eVecs))

    // Hybrid scoring: for each query, rank under both paths, RRF
    // merge, score the merged ranking against the same gold.
    var hybridRankings: [(Int, [Int])] = []
    var hybridNdcgs: [Double] = []
    var hybridPrefs: [Double] = []
    for query in fixture.queries {
        guard let qD = dVecs[query.id], let qE = eVecs[query.id] else {
            hybridRankings.append((query.id, []))
            hybridNdcgs.append(0)
            hybridPrefs.append(0)
            continue
        }
        let dPairs: [(Int, EmbeddingVector)] = fixture.excerpts.compactMap {
            guard let v = dVecs[$0.id] else { return nil }; return ($0.id, v)
        }
        let ePairs: [(Int, EmbeddingVector)] = fixture.excerpts.compactMap {
            guard let v = eVecs[$0.id] else { return nil }; return ($0.id, v)
        }
        let dRank = RankingMetrics.rankExcerpts(query: qD, excerpts: dPairs)
        let eRank = RankingMetrics.rankExcerpts(query: qE, excerpts: ePairs)
        let merged = RankingMetrics.reciprocalRankFusion(
            rankings: [dRank, eRank],
            k: 10
        )
        hybridRankings.append((query.id, merged))

        let styleMatch = Set(fixture.excerpts.filter { $0.style == query.style }.map { $0.id })
        let topicMatch = Set(fixture.excerpts.filter { $0.topic == query.topic }.map { $0.id })
        let ndcg = RankingMetrics.ndcg(at: 3, gold: styleMatch, ranking: merged)
        let pref = RankingMetrics.styleTopicPreference(
            top3: Array(merged.prefix(3)),
            styleMatch: styleMatch,
            topicMatch: topicMatch
        )
        hybridNdcgs.append(ndcg)
        hybridPrefs.append(pref)
    }
    pathResults.append(PathResult(
        name: "Hybrid D+E (RRF k=10)",
        model: "loom/hybrid-rrf-k10",
        dim: 0,
        rankings: hybridRankings,
        ndcgs: hybridNdcgs,
        preferences: hybridPrefs
    ))

    // Report
    log("")
    log("=== Per-path aggregate (mean over 4 queries) ===")
    log("| Path                     | NDCG@3 | preference | NSFW hit | SFW hit |")
    log("|--------------------------|--------|------------|----------|---------|")
    for r in pathResults {
        let parity = nsfwParity(fixture: fixture, result: r)
        let nameCol = r.name.padding(toLength: 24, withPad: " ", startingAt: 0)
        log(String(format: "| %@ | %.3f  | %+.3f     | %.3f    | %.3f   |",
                   nameCol, mean(r.ndcgs), mean(r.preferences),
                   parity.nsfwHitRate, parity.sfwHitRate))
    }

    log("")
    log("=== Per-query top-3 ===")
    for (i, q) in fixture.queries.enumerated() {
        log("Q\(q.id) [\(q.style)/\(q.topic), NSFW=\(q.nsfw ? "Y" : "N")]:")
        for r in pathResults {
            let nameCol = r.name.padding(toLength: 24, withPad: " ", startingAt: 0)
            let top3 = Array(r.rankings[i].1.prefix(3)).map { String($0) }.joined(separator: ",")
            log(String(format: "  %@ NDCG=%.2f pref=%+.2f top3=[%@]",
                       nameCol, r.ndcgs[i], r.preferences[i], top3))
        }
        log("")
    }
    return 0
}

// MARK: - Funcword-Z Swift port cross-check (LOOM_RAG_SPIKE §13.6 graduation)

/// One-time validation: embed the fixture via the Swift FuncwordZEmbedder
/// and dump the resulting vectors as JSON for comparison against the
/// canonical Python embed_path_e output. Pairs with
/// Tools/RagSpike/MlxSpike/compare_funcword_z.py.
func dumpFuncwordZ() -> Int32 {
    guard let fixture = loadFixture() else {
        log("FATAL: could not load fixture")
        return 1
    }
    let all = fixture.excerpts + fixture.queries
    let model = FuncwordZEmbedder.fit(corpus: all.map { $0.text }, topN: 150)
    log("[E-swift] fitted vocab dim=\(model.dim) over \(all.count) items")

    var vectors: [String: [Float]] = [:]
    for item in all {
        let v = FuncwordZEmbedder.transform(item.text, using: model)
        vectors[String(item.id)] = v.values
    }

    let payload: [String: Any] = [
        "version": 1,
        "paths": [[
            "path": "E-funcword-z-swift",
            "model": "swift/FuncwordZEmbedder@LoomCore",
            "dim": model.dim,
            "vectors": vectors,
        ]],
    ]
    let cwd = FileManager.default.currentDirectoryPath
    let out = URL(fileURLWithPath: cwd)
        .appendingPathComponent("Tools/RagSpike/MlxSpike/vectors_funcword_z_swift.json")
    if let data = try? JSONSerialization.data(withJSONObject: payload),
       (try? data.write(to: out)) != nil {
        log("Wrote \(out.path)")
        return 0
    }
    log("FATAL: could not write \(out.path)")
    return 1
}

// MARK: - Entry

let args = CommandLine.arguments.dropFirst()
if args.contains("--smoke") {
    exit(smoke())
} else if args.contains("--corpus") {
    exit(corpus())
} else if args.contains("--funcword-z-dump") {
    exit(dumpFuncwordZ())
} else if args.contains("--hybrid") {
    exit(hybrid())
} else {
    log("usage: swift run RagSpike --smoke")
    log("       swift run RagSpike --corpus")
    log("       swift run RagSpike --hybrid           (D+E via RRF — scope-lock #4)")
    log("       swift run RagSpike --funcword-z-dump   (LOOM_MLX_PORT_SPIKE §11 cross-check)")
    log("")
    log("env overrides:")
    log("  LOOM_SPIKE_BASE_URL   (default \(koboldURLString))")
    log("  LOOM_SPIKE_OLLAMA_URL (default \(ollamaURLString))")
    exit(2)
}

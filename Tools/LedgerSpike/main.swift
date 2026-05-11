import Foundation
import LoomCore

// MARK: - Stderr helper (declared first so it's initialised before use)

struct FileHandleOutputStream: TextOutputStream {
    let handle: FileHandle
    init(_ handle: FileHandle) { self.handle = handle }
    mutating func write(_ string: String) {
        handle.write(Data(string.utf8))
    }
}
var stderrStream = FileHandleOutputStream(FileHandle.standardError)
func logProgress(_ s: String) {
    print(s, to: &stderrStream)
}

// Knowledge-ledger feasibility spike (LOOM_MEMORY §4.5 falsifiable
// hypothesis: per-scene extraction is feasible at <13B; we're testing
// at 27B). One-off runner: loads a hand-graded fixture, sends each
// scene through the LOOM_STORY_BIBLE §3.3 extraction prompt against
// the configured local LLM server, scores the response against the
// gold ledger, and emits a markdown report to stdout.
//
// **Run:** `swift run LedgerSpike` (Loom server must be reachable at
// LOOM_SPIKE_BASE_URL, default http://192.168.1.201:5001/).
//
// **What gates Phase 4 #7:** the report's aggregate F1 + per-certainty
// breakdown. If the model can produce schema-conformant JSON with
// reasonable precision on the asserted facts (the most common case),
// the full pipeline is worth building. If it routinely fails to emit
// JSON at all, or hallucinates facts not in the prose, defer the
// extractor side to Phase 5 and keep the manual-authoring path only.

// MARK: - Fixture types (mirror fixture.json)

struct Fixture: Codable {
    let characters: [LedgerExtraction.CharacterRef]
    let aliases_canonical: [String: String]
    let scenes: [Scene]
}

struct Scene: Codable {
    let id: String
    let title: String
    let tag: String
    let prose: String
    let gold_facts: [GoldFact]
}

struct GoldFact: Codable {
    let character_id: String
    let fact: String
    let certainty: String
    let evidence_quote: String

    func asExtracted() -> LedgerExtraction.ExtractedFact {
        let cert = LedgerExtraction.Certainty(rawValue: certainty) ?? .asserted
        return LedgerExtraction.ExtractedFact(
            characterId: character_id,
            fact: fact,
            certainty: cert,
            evidenceQuote: evidence_quote
        )
    }
}

// MARK: - Per-scene result

struct SceneResult {
    let scene: Scene
    let prompt: String
    let rawResponse: String
    let parseError: Error?
    let extracted: [LedgerExtraction.ExtractedFact]
    let score: LedgerExtraction.ScoreReport          // Jaccard (fast, wordform)
    var scoreEmbedding: LedgerExtraction.ScoreReport // cosine (semantic, real)
    let elapsedSeconds: Double                        // wall-clock for the side-call
}

// MARK: - Runner

let fixtureRelativePath = "Tests/LoomCoreTests/Fixtures/LedgerSpike/fixture.json"

/// Two backends supported:
/// - `kobold` (default): hits KoboldCpp at LOOM_SPIKE_BASE_URL via the
///   `/api/v1/generate` endpoint with a GBNF `grammar` field. The
///   existing production server (Qwen3.6-27B) speaks this.
/// - `ollama`: hits Ollama at LOOM_SPIKE_OLLAMA_URL via `/api/chat`
///   with a `format: <JSON schema>` field. The §10 → §11 evolution:
///   embedding-scorer findings + research §5 motivated swapping the
///   extractor model; Ollama with a small Gemma 4 variant is the
///   first such swap to validate.
enum Backend: String { case kobold, ollama }
let backend = Backend(rawValue: ProcessInfo.processInfo.environment["LOOM_SPIKE_BACKEND"] ?? "kobold") ?? .kobold
let baseURLString = ProcessInfo.processInfo.environment["LOOM_SPIKE_BASE_URL"]
    ?? "http://192.168.1.201:5001/"
let ollamaURLString = ProcessInfo.processInfo.environment["LOOM_SPIKE_OLLAMA_URL"]
    ?? "http://localhost:11434/"
let ollamaModel = ProcessInfo.processInfo.environment["LOOM_SPIKE_OLLAMA_MODEL"]
    ?? "gemma4_4b:latest"

/// Send the §3.3 extraction call to Ollama. Uses `/api/chat` (so
/// Ollama applies the model's chat template — important for Gemma
/// which needs `<start_of_turn>user/model` wrapping) with the JSON
/// Schema in the `format` field. Returns the message content on
/// success; error otherwise. Synchronous wrapper for the spike runner.
func ollamaExtract(
    prompt: String,
    schema: [String: Any]
) -> Result<String, Error> {
    guard let url = URL(string: "api/chat", relativeTo: URL(string: ollamaURLString))?.absoluteURL else {
        return .failure(NSError(domain: "Spike", code: -1, userInfo: [NSLocalizedDescriptionKey: "bad ollama URL"]))
    }
    let body: [String: Any] = [
        "model": ollamaModel,
        "messages": [["role": "user", "content": prompt]],
        "stream": false,
        "options": [
            "temperature": 0.3,
            "num_predict": 1024,
            // rep_pen equivalent in Ollama options; default 1.1.
            "repeat_penalty": 1.1,
        ],
        "format": schema,
    ]
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try? JSONSerialization.data(withJSONObject: body)
    let cfg = URLSessionConfiguration.default
    cfg.timeoutIntervalForRequest = 600
    let s = URLSession(configuration: cfg)
    let sem = DispatchSemaphore(value: 0)
    var result: Result<String, Error> = .failure(NSError(domain: "Spike", code: -1))
    s.dataTask(with: req) { data, _, err in
        defer { sem.signal() }
        if let err = err { result = .failure(err); return }
        guard let data = data else {
            result = .failure(NSError(domain: "Spike", code: -1, userInfo: [NSLocalizedDescriptionKey: "no body"]))
            return
        }
        do {
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let msg = obj?["message"] as? [String: Any],
               let content = msg["content"] as? String {
                result = .success(content)
            } else {
                let raw = String(data: data, encoding: .utf8) ?? ""
                result = .failure(NSError(domain: "Spike", code: -1, userInfo: [NSLocalizedDescriptionKey: "unexpected shape: \(raw.prefix(200))"]))
            }
        } catch {
            result = .failure(error)
        }
    }.resume()
    sem.wait()
    return result
}

func loadFixture() throws -> (Fixture, URL) {
    let cwd = FileManager.default.currentDirectoryPath
    let url = URL(fileURLWithPath: cwd).appendingPathComponent(fixtureRelativePath)
    let data = try Data(contentsOf: url)
    let f = try JSONDecoder().decode(Fixture.self, from: data)
    return (f, url)
}

func extractSceneSync(
    client: KoboldClient,
    scene: Scene,
    characters: [LedgerExtraction.CharacterRef],
    maxContextLength: Int
) -> SceneResult {
    let prompt = LedgerExtraction.buildExtractionPrompt(
        characters: characters,
        scenePose: scene.prose
    )
    let started = Date()
    func elapsed() -> Double { -started.timeIntervalSinceNow }

    // Ollama backend: use JSON Schema instead of GBNF; otherwise the
    // same prompt + scoring shape. Ollama applies the model's chat
    // template via /api/chat — works for Gemma 4, which expects
    // `<start_of_turn>user...<end_of_turn><start_of_turn>model`.
    if backend == .ollama {
        let schema = LedgerExtraction.jsonSchema(
            certainties: [.asserted],
            characters: characters
        )
        let emptyEmbScore = LedgerExtraction.ScoreReport(
            truePositives: 0, falsePositives: 0,
            falseNegatives: scene.gold_facts.count
        )
        let response = ollamaExtract(prompt: prompt, schema: schema)
        switch response {
        case .failure(let e):
            return SceneResult(
                scene: scene, prompt: prompt, rawResponse: "<<ollama error: \(e)>>",
                parseError: e, extracted: [],
                score: emptyEmbScore, scoreEmbedding: emptyEmbScore,
                elapsedSeconds: elapsed()
            )
        case .success(let raw):
            do {
                let extracted = try LedgerExtraction.parseExtractedFacts(raw)
                let gold = scene.gold_facts.map { $0.asExtracted() }
                let score = LedgerExtraction.score(
                    extracted: extracted, gold: gold, aliases: fixtureAliases
                )
                return SceneResult(
                    scene: scene, prompt: prompt, rawResponse: raw,
                    parseError: nil, extracted: extracted, score: score,
                    scoreEmbedding: emptyEmbScore,
                    elapsedSeconds: elapsed()
                )
            } catch {
                return SceneResult(
                    scene: scene, prompt: prompt, rawResponse: raw,
                    parseError: error, extracted: [],
                    score: emptyEmbScore, scoreEmbedding: emptyEmbScore,
                    elapsedSeconds: elapsed()
                )
            }
        }
    }

    // Tight sampler — extraction wants deterministic JSON, not creative
    // prose. Temperature 0.3, no XTC (which actively pushes the model
    // away from common-token JSON syntax). max_length 1024 is now
    // sufficient because the GBNF grammar (below) prevents `<think>`
    // emission by construction (LOOM_LEDGER_SPIKE §8.1) — the budget
    // that used to be consumed by thinking is freed for the actual
    // extraction.
    let params = SamplerParams(
        temperature: 0.2,
        topP: 0.95,
        topK: 0,
        minP: 0.05,
        // rep_pen is load-bearing for extraction. Empirically observed
        // (LOOM_LEDGER_SPIKE iteration): rep_pen=1.0 lets the model
        // get stuck in a degenerate loop emitting the same fact
        // object repeatedly, often with the prompt itself leaking into
        // evidence_quote strings. rep_pen=1.1 with a 512-token window
        // breaks the loop without affecting JSON syntax (the grammar
        // enforces syntax; rep_pen only penalises content-token
        // repeats).
        repPen: 1.1,
        repPenRange: 512,
        maxLength: 1024,
        dryMultiplier: 0.0,
        dryBase: 1.75,
        dryAllowedLength: 2,
        xtcThreshold: 0.0,
        xtcProbability: 0.0
    )

    // Phase 4 #7 production posture (LOOM_LEDGER_SPIKE §8.3):
    // the extractor's grammar emits ONLY `asserted` facts. Negative
    // knowledge (`unknown` / `mistaken`) is derived from a per-
    // character scene-exposure graph at query time rather than asked
    // of the model — the spike's §3.e finding (recall 0/2 on unknown)
    // confirmed that local models cannot extract negative knowledge
    // reliably.
    // Restrict character_id to the bible's named characters + aliases.
    // Without this, the model occasionally puts garbage in
    // character_id ("hallway", "kitchen", or sentence fragments) —
    // observed in the §10 first-pass run with free-string
    // character_id. The grammar-level enum eliminates that failure.
    let grammar = LedgerExtraction.gbnfGrammar(
        certainties: [.asserted],
        characters: characters
    )

    let sem = DispatchSemaphore(value: 0)
    var response: Result<String, Error> = .failure(NSError(domain: "Spike", code: -1))
    let req = GenerateRequest(
        prompt: prompt,
        stopSequences: [],
        params: params,
        maxContextLength: maxContextLength,
        grammar: grammar
    )
    client.generate(request: req) { result in
        response = result
        sem.signal()
    }
    sem.wait()

    let raw: String
    let emptyEmbeddingScore = LedgerExtraction.ScoreReport(
        truePositives: 0, falsePositives: 0,
        falseNegatives: scene.gold_facts.count
    )
    switch response {
    case .success(let s): raw = s
    case .failure(let e):
        return SceneResult(
            scene: scene, prompt: prompt, rawResponse: "<<network error: \(e)>>",
            parseError: e, extracted: [],
            score: emptyEmbeddingScore,
            scoreEmbedding: emptyEmbeddingScore,
            elapsedSeconds: elapsed()
        )
    }

    // With grammar-constrained decoding the model emits a well-formed
    // JSON array directly — no `<think>` blocks (the grammar root
    // doesn't permit `<`), no preamble, no force-prefill. Pass raw
    // straight to the parser.
    do {
        let extracted = try LedgerExtraction.parseExtractedFacts(raw)
        let gold = scene.gold_facts.map { $0.asExtracted() }
        let score = LedgerExtraction.score(extracted: extracted, gold: gold, aliases: fixtureAliases)
        return SceneResult(
            scene: scene, prompt: prompt, rawResponse: raw,
            parseError: nil, extracted: extracted, score: score,
            scoreEmbedding: emptyEmbeddingScore, // populated post-extraction
            elapsedSeconds: elapsed()
        )
    } catch {
        return SceneResult(
            scene: scene, prompt: prompt, rawResponse: raw,
            parseError: error, extracted: [],
            score: emptyEmbeddingScore,
            scoreEmbedding: emptyEmbeddingScore,
            elapsedSeconds: elapsed()
        )
    }
}

let fixtureAliases: [String: String] = [
    "Mia Vance": "Mia", "Miss Vance": "Mia", "the librarian": "Mia",
    "Anders Voll": "Anders", "the stranger": "Anders",
    "Karim Vance": "Karim",
]

/// Batch-embed every gold + extracted fact text, then re-score each
/// scene using cosine similarity over the embeddings (LOOM_LEDGER_SPIKE
/// §10). One round-trip to the server's `/v1/embeddings` endpoint
/// regardless of fixture size; cheap.
func attachEmbeddingScores(
    _ results: [SceneResult],
    client: KoboldClient
) -> [SceneResult] {
    var allTexts: [String] = []
    for r in results {
        for f in r.scene.gold_facts { allTexts.append(f.fact) }
        for f in r.extracted { allTexts.append(f.fact) }
    }
    let uniqueTexts = Array(Set(allTexts)).sorted()
    if uniqueTexts.isEmpty { return results }

    logProgress("LedgerSpike: embedding \(uniqueTexts.count) unique fact texts in one batch…")
    let sem = DispatchSemaphore(value: 0)
    var embeddings: [String: [Float]] = [:]
    var embedError: Error?
    client.embed(texts: uniqueTexts) { result in
        switch result {
        case .success(let vecs):
            for (txt, vec) in zip(uniqueTexts, vecs) {
                embeddings[txt] = vec
            }
        case .failure(let e):
            embedError = e
        }
        sem.signal()
    }
    sem.wait()
    if let e = embedError {
        logProgress("LedgerSpike: embedding failed: \(e)")
        return results
    }
    logProgress("LedgerSpike: embedded — dim=\(embeddings.first?.value.count ?? 0)")

    return results.map { r in
        let gold = r.scene.gold_facts.map { $0.asExtracted() }
        let score = LedgerExtraction.scoreByEmbedding(
            extracted: r.extracted, gold: gold,
            embedding: { embeddings[$0] ?? [] },
            threshold: 0.65,
            aliases: fixtureAliases
        )
        var updated = r
        updated.scoreEmbedding = score
        return updated
    }
}

// MARK: - Report

func emitReport(results: [SceneResult]) -> String {
    var out = "# LOOM_LEDGER_SPIKE — knowledge-ledger feasibility eval\n\n"
    out += "**Date:** \(ISO8601DateFormatter().string(from: Date()))\n"
    let backendDesc: String
    switch backend {
    case .kobold: backendDesc = "kobold @ \(baseURLString)"
    case .ollama: backendDesc = "ollama @ \(ollamaURLString) model=\(ollamaModel)"
    }
    out += "**Backend:** \(backendDesc)\n"
    out += "**Fixture:** \(results.count) scenes, "
    out += "\(results.flatMap { $0.scene.gold_facts }.count) gold facts total\n\n"

    let totalElapsed = results.reduce(0.0) { $0 + $1.elapsedSeconds }
    let avgElapsed = results.isEmpty ? 0 : totalElapsed / Double(results.count)
    out += "**Wall-clock (extraction side-call only):** total \(String(format: "%.1f", totalElapsed))s, "
    out += "avg \(String(format: "%.1f", avgElapsed))s/scene\n\n"
    out += "**Hypothesis** (LOOM_MEMORY §4.5): per-scene knowledge-state extraction is feasible at <13B model size. We test against Qwen3.6-27B (a 27B-class abliterated model) — so the threshold here is even easier than the falsifiable claim.\n\n"

    let agg = LedgerExtraction.ScoreReport(
        truePositives: results.reduce(0) { $0 + $1.score.truePositives },
        falsePositives: results.reduce(0) { $0 + $1.score.falsePositives },
        falseNegatives: results.reduce(0) { $0 + $1.score.falseNegatives }
    )
    let aggEmb = LedgerExtraction.ScoreReport(
        truePositives: results.reduce(0) { $0 + $1.scoreEmbedding.truePositives },
        falsePositives: results.reduce(0) { $0 + $1.scoreEmbedding.falsePositives },
        falseNegatives: results.reduce(0) { $0 + $1.scoreEmbedding.falseNegatives }
    )

    out += "## Aggregate\n\n"
    out += "Two scorers run on the same extraction output: **Jaccard** (wordform-overlap, fast, threshold 0.5) and **Embedding cosine** (semantic, via bge-small-en-v1.5 on the live server, threshold 0.65 per LOOM_MEMORY §B2). The embedding scorer is the load-bearing measure of actual extraction quality; Jaccard is preserved as a fast fallback and to show the metric gap.\n\n"
    out += "| Metric    | Jaccard | Embedding (cosine ≥ 0.65) |\n"
    out += "|-----------|---------|---------------------------|\n"
    out += "| TP        | \(agg.truePositives) | \(aggEmb.truePositives) |\n"
    out += "| FP        | \(agg.falsePositives) | \(aggEmb.falsePositives) |\n"
    out += "| FN        | \(agg.falseNegatives) | \(aggEmb.falseNegatives) |\n"
    out += "| Precision | \(String(format: "%.2f", agg.precision)) | \(String(format: "%.2f", aggEmb.precision)) |\n"
    out += "| Recall    | \(String(format: "%.2f", agg.recall)) | \(String(format: "%.2f", aggEmb.recall)) |\n"
    out += "| F1        | \(String(format: "%.2f", agg.f1)) | \(String(format: "%.2f", aggEmb.f1)) |\n\n"

    // Per-certainty breakdown: how well does the model do on each
    // certainty bucket? Asserted is the easy case; unknown/mistaken
    // are the hard cases that require explicit prose negation.
    out += "## Per-certainty (gold → did the model produce a true-positive match?)\n\n"
    var byCertaintyGold: [String: Int] = [:]
    var byCertaintyMatched: [String: Int] = [:]
    for r in results {
        let goldByCert = Dictionary(grouping: r.scene.gold_facts, by: { $0.certainty })
        for (cert, facts) in goldByCert {
            byCertaintyGold[cert, default: 0] += facts.count
            // Count how many of those gold facts found a true-positive
            // match. We can't perfectly cross-tab without re-running
            // the matcher per certainty — approximate by counting
            // gold-side TPs: r.score.truePositives is the total per scene.
            // For a fair per-certainty breakdown we re-score per-cert.
            let goldThisCert = facts.map { $0.asExtracted() }
            let s = LedgerExtraction.score(
                extracted: r.extracted, gold: goldThisCert,
                aliases: [
                    "Mia Vance": "Mia", "Miss Vance": "Mia", "the librarian": "Mia",
                    "Anders Voll": "Anders", "the stranger": "Anders",
                    "Karim Vance": "Karim",
                ]
            )
            byCertaintyMatched[cert, default: 0] += s.truePositives
        }
    }
    out += "| Certainty | Gold | Matched | Recall |\n|-----------|------|---------|--------|\n"
    for cert in ["asserted", "suspected", "unknown", "mistaken"] {
        let gold = byCertaintyGold[cert, default: 0]
        let matched = byCertaintyMatched[cert, default: 0]
        let recall = gold == 0 ? "—" : String(format: "%.2f", Double(matched) / Double(gold))
        out += "| \(cert) | \(gold) | \(matched) | \(recall) |\n"
    }
    out += "\n"

    // Per-scene detail.
    out += "## Per-scene detail\n\n"
    for r in results {
        out += "### Scene `\(r.scene.id)` — \(r.scene.title) [\(r.scene.tag)]\n\n"
        out += "Wall-clock: \(String(format: "%.1f", r.elapsedSeconds))s · "
        out += "extracted \(r.extracted.count) facts (gold has \(r.scene.gold_facts.count))\n\n"
        out += "Jaccard: TP \(r.score.truePositives) / FP \(r.score.falsePositives) / FN \(r.score.falseNegatives) — P \(String(format: "%.2f", r.score.precision)) R \(String(format: "%.2f", r.score.recall))\n"
        out += "Embedding: TP \(r.scoreEmbedding.truePositives) / FP \(r.scoreEmbedding.falsePositives) / FN \(r.scoreEmbedding.falseNegatives) — P \(String(format: "%.2f", r.scoreEmbedding.precision)) R \(String(format: "%.2f", r.scoreEmbedding.recall))\n\n"

        if let e = r.parseError {
            out += "**PARSE FAILURE:** \(e)\n\n"
        }

        out += "**Raw response (first 600 chars):**\n```\n"
        out += String(r.rawResponse.prefix(600))
        out += (r.rawResponse.count > 600 ? "\n…\n" : "")
        out += "```\n\n"

        out += "**Extracted facts** (\(r.extracted.count)):\n"
        for f in r.extracted {
            out += "- `\(f.characterId)` [\(f.certainty.rawValue)] — \(f.fact)\n"
        }
        out += "\n**Gold facts** (\(r.scene.gold_facts.count)):\n"
        for f in r.scene.gold_facts {
            out += "- `\(f.character_id)` [\(f.certainty)] — \(f.fact)\n"
        }
        out += "\n"
    }
    return out
}

// MARK: - Main

print("LedgerSpike: loading fixture…", to: &stderrStream)
let (fixture, fixtureURL): (Fixture, URL)
do {
    (fixture, fixtureURL) = try loadFixture()
} catch {
    print("FATAL: \(error)", to: &stderrStream)
    print("(working directory: \(FileManager.default.currentDirectoryPath))", to: &stderrStream)
    exit(1)
}
print("LedgerSpike: loaded \(fixture.scenes.count) scenes from \(fixtureURL.path)", to: &stderrStream)

guard let baseURL = URL(string: baseURLString) else {
    print("FATAL: invalid base URL \(baseURLString)", to: &stderrStream)
    exit(1)
}
let client = KoboldClient(baseURL: baseURL)

// Best-effort probe of true max ctx; falls back to 16384 if unavailable.
let probeSem = DispatchSemaphore(value: 0)
var maxCtx = 16384
client.fetchTrueMaxContext { result in
    if case .success(let n) = result { maxCtx = n }
    probeSem.signal()
}
probeSem.wait()
print("LedgerSpike: ctx=\(maxCtx)", to: &stderrStream)

var results: [SceneResult] = []
let dumpDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Tools/LedgerSpike/last-run")
try? FileManager.default.createDirectory(at: dumpDir, withIntermediateDirectories: true)
for (i, scene) in fixture.scenes.enumerated() {
    logProgress("LedgerSpike: [\(i+1)/\(fixture.scenes.count)] extracting `\(scene.id)`…")
    let r = extractSceneSync(
        client: client,
        scene: scene,
        characters: fixture.characters,
        maxContextLength: maxCtx
    )
    logProgress("    \(String(format: "%.1f", r.elapsedSeconds))s · raw=\(r.rawResponse.count) chars · extracted \(r.extracted.count)")
    // Dump the raw response per scene so we can diagnose empty / weird
    // outputs without trying to fit them in the report excerpt window.
    let dumpURL = dumpDir.appendingPathComponent("\(scene.id).raw.txt")
    try? r.rawResponse.write(to: dumpURL, atomically: true, encoding: .utf8)
    results.append(r)
}

logProgress("")
// Batch-embed all gold + extracted fact texts and compute the
// semantic-similarity scoreboard alongside Jaccard.
let resultsWithEmb = attachEmbeddingScores(results, client: client)
logProgress("")
let report = emitReport(results: resultsWithEmb)
print(report)

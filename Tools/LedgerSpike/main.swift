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
    let score: LedgerExtraction.ScoreReport
}

// MARK: - Runner

let fixtureRelativePath = "Tests/LoomCoreTests/Fixtures/LedgerSpike/fixture.json"
let baseURLString = ProcessInfo.processInfo.environment["LOOM_SPIKE_BASE_URL"]
    ?? "http://192.168.1.201:5001/"

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
    let grammar = LedgerExtraction.gbnfGrammar(certainties: [.asserted])

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
    switch response {
    case .success(let s): raw = s
    case .failure(let e):
        return SceneResult(
            scene: scene, prompt: prompt, rawResponse: "<<network error: \(e)>>",
            parseError: e, extracted: [],
            score: LedgerExtraction.ScoreReport(
                truePositives: 0, falsePositives: 0,
                falseNegatives: scene.gold_facts.count
            )
        )
    }

    // With grammar-constrained decoding the model emits a well-formed
    // JSON array directly — no `<think>` blocks (the grammar root
    // doesn't permit `<`), no preamble, no force-prefill. Pass raw
    // straight to the parser.
    do {
        let extracted = try LedgerExtraction.parseExtractedFacts(raw)
        let gold = scene.gold_facts.map { $0.asExtracted() }
        // Use the fixture's canonical alias map.
        // Hard-coded for now; would be loaded from fixture for richer cases.
        let aliases: [String: String] = [
            "Mia Vance": "Mia", "Miss Vance": "Mia", "the librarian": "Mia",
            "Anders Voll": "Anders", "the stranger": "Anders",
            "Karim Vance": "Karim",
        ]
        let score = LedgerExtraction.score(extracted: extracted, gold: gold, aliases: aliases)
        return SceneResult(
            scene: scene, prompt: prompt, rawResponse: raw,
            parseError: nil, extracted: extracted, score: score
        )
    } catch {
        return SceneResult(
            scene: scene, prompt: prompt, rawResponse: raw,
            parseError: error, extracted: [],
            score: LedgerExtraction.ScoreReport(
                truePositives: 0, falsePositives: 0,
                falseNegatives: scene.gold_facts.count
            )
        )
    }
}

// MARK: - Report

func emitReport(results: [SceneResult]) -> String {
    var out = "# LOOM_LEDGER_SPIKE — knowledge-ledger feasibility eval\n\n"
    out += "**Date:** \(ISO8601DateFormatter().string(from: Date()))\n"
    out += "**Server:** \(baseURLString)\n"
    out += "**Fixture:** \(results.count) scenes, "
    out += "\(results.flatMap { $0.scene.gold_facts }.count) gold facts total\n\n"
    out += "**Hypothesis** (LOOM_MEMORY §4.5): per-scene knowledge-state extraction is feasible at <13B model size. We test against Qwen3.6-27B (a 27B-class abliterated model) — so the threshold here is even easier than the falsifiable claim.\n\n"

    let totalTP = results.reduce(0) { $0 + $1.score.truePositives }
    let totalFP = results.reduce(0) { $0 + $1.score.falsePositives }
    let totalFN = results.reduce(0) { $0 + $1.score.falseNegatives }
    let agg = LedgerExtraction.ScoreReport(
        truePositives: totalTP, falsePositives: totalFP, falseNegatives: totalFN
    )

    out += "## Aggregate\n\n"
    out += "| Metric    | Value |\n|-----------|-------|\n"
    out += "| TP        | \(agg.truePositives) |\n"
    out += "| FP        | \(agg.falsePositives) |\n"
    out += "| FN        | \(agg.falseNegatives) |\n"
    out += "| Precision | \(String(format: "%.2f", agg.precision)) |\n"
    out += "| Recall    | \(String(format: "%.2f", agg.recall)) |\n"
    out += "| F1        | \(String(format: "%.2f", agg.f1)) |\n\n"

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
        out += "TP \(r.score.truePositives) / FP \(r.score.falsePositives) / FN \(r.score.falseNegatives)"
        out += " — P \(String(format: "%.2f", r.score.precision)), R \(String(format: "%.2f", r.score.recall))\n\n"

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
    logProgress("    raw=\(r.rawResponse.count) chars, TP \(r.score.truePositives) FP \(r.score.falsePositives) FN \(r.score.falseNegatives)")
    // Dump the raw response per scene so we can diagnose empty / weird
    // outputs without trying to fit them in the report excerpt window.
    let dumpURL = dumpDir.appendingPathComponent("\(scene.id).raw.txt")
    try? r.rawResponse.write(to: dumpURL, atomically: true, encoding: .utf8)
    results.append(r)
}

logProgress("")
let report = emitReport(results: results)
print(report)

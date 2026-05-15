import Foundation
import LoomCore

// Phase 9 entity-discovery feasibility spike (LOOM_ENTITY_DISCOVERY_SPIKE.md
// §6.3). One-off runner: loads the hand-graded EntityDiscoverySpike fixture,
// drives each scene through Stage A2 (candidate gen) + promotion gate +
// Stage D (normalisation) against a live Ollama endpoint, scores the
// proposed entities against the gold ledger, and emits a markdown report.
//
// **Run:** `swift run EntityDiscoverySpike` (Ollama reachable at
// LOOM_SPIKE_OLLAMA_URL, default http://localhost:11434/; model from
// LOOM_SPIKE_OLLAMA_MODEL, default gemma4_2b:latest).
//
// **What gates Phase 9 productionisation:** the report's aggregate
// precision/recall/F1 + proposals-per-scene cap rate vs the
// hypothesis thresholds in §1 of the plan doc (precision ≥ 75%,
// recall ≥ 60%, ≤ 5 proposals/scene, ≤ 30 s/scene).
//
// v1 of the runner does NOT exercise Stage C (dedup) — every promoted
// candidate is treated as new. Dedup is a separate sub-experiment.

// MARK: - Stderr helper

struct FileHandleOutputStream: TextOutputStream {
    let handle: FileHandle
    init(_ handle: FileHandle) { self.handle = handle }
    mutating func write(_ string: String) {
        handle.write(Data(string.utf8))
    }
}
var stderrStream = FileHandleOutputStream(FileHandle.standardError)
func logProgress(_ s: String) { print(s, to: &stderrStream) }

// MARK: - Fixture types (mirror Tests/LoomCoreTests/Fixtures/EntityDiscoverySpike/fixture.json)

struct Fixture: Codable {
    let _description: String
    let schema_version: Int
    let scenes: [FixtureScene]
}

struct FixtureScene: Codable {
    let id: String
    let title: String
    let tag: String
    let source: String
    let prose: String
    let starting_bible: StartingBible
    let gold_entities: [GoldEntity]
    let gold_distractors: [GoldDistractor]
    let gold_facts: [GoldFact]
}

struct StartingBible: Codable {
    let characters: [StartingCharacter]?
    let settings: [StartingSetting]?
}

struct StartingCharacter: Codable {
    let name: String
    let aliases: [String]
}

struct StartingSetting: Codable {
    let name: String
    let aliases: [String]
}

struct GoldEntity: Codable {
    let kind: String
    let canonical_name: String
    let aliases: [String]
    let is_new: Bool
    let merges_with_bible_name: String?
    let is_worth_tracking: Bool
    let one_line: String
    let evidence_quote: String
    let reasoning: String
}

struct GoldDistractor: Codable {
    let surface: String
    let kind: String
    let reasoning: String
}

struct GoldFact: Codable {
    let entity_canonical_name: String
    let fact: String
    let certainty: String
    let evidence_quote: String
}

// MARK: - Configuration

let fixtureRelativePath = "Tests/LoomCoreTests/Fixtures/EntityDiscoverySpike/fixture.json"
let ollamaURLString = ProcessInfo.processInfo.environment["LOOM_SPIKE_OLLAMA_URL"]
    ?? "http://localhost:11434/"
let ollamaModel = ProcessInfo.processInfo.environment["LOOM_SPIKE_OLLAMA_MODEL"]
    ?? "gemma4_2b:latest"

// MARK: - Sync-on-async HTTP wrapper

func ollamaExtractSync(prompt: String, schema: [String: Any]) -> Result<String, Error> {
    guard let url = URL(string: "api/chat", relativeTo: URL(string: ollamaURLString))?.absoluteURL else {
        return .failure(NSError(domain: "Spike", code: -1, userInfo: [NSLocalizedDescriptionKey: "bad ollama url"]))
    }
    let body: [String: Any] = [
        "model": ollamaModel,
        "messages": [["role": "user", "content": prompt]],
        "stream": false,
        "options": [
            "temperature": 0.2,
            "num_predict": 1024,
        ],
        "format": schema,
        "keep_alive": "30m",
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

// MARK: - Pipeline

struct PipelineSceneResult {
    let sceneId: String
    let sceneTitle: String
    let tag: String
    let elapsedSec: TimeInterval
    let rawCandidates: [EntityDiscovery.Candidate]
    let postGate: [EntityDiscovery.Candidate]
    let gateRejects: [(candidate: EntityDiscovery.Candidate, verdict: EntityPromotionGate.Verdict)]
    let normalised: [EntityDiscovery.NormalisedEntity]
    let stageAError: String?
    let stageDErrors: [(surface: String, error: String)]
    let scoreInput: EntityDiscoveryScorer.ScoreInput
}

func runScene(_ scene: FixtureScene) -> PipelineSceneResult {
    let started = Date()
    let knownNames: [String] = {
        var names: [String] = []
        if let chars = scene.starting_bible.characters {
            for c in chars { names.append(c.name); names.append(contentsOf: c.aliases) }
        }
        if let sets = scene.starting_bible.settings {
            for s in sets { names.append(s.name); names.append(contentsOf: s.aliases) }
        }
        return names
    }()

    logProgress("[\(scene.id)] Stage A2 — candidate gen ...")
    let a2Prompt = EntityDiscovery.buildCandidateGenerationPrompt(
        scenePose: scene.prose,
        knownEntityNames: knownNames
    )
    let a2Schema = EntityDiscovery.candidateGenerationJSONSchema()
    var candidates: [EntityDiscovery.Candidate] = []
    var stageAError: String?
    switch ollamaExtractSync(prompt: a2Prompt, schema: a2Schema) {
    case .success(let raw):
        do {
            candidates = try EntityDiscovery.parseCandidates(raw)
            logProgress("[\(scene.id)]   got \(candidates.count) candidates")
        } catch {
            stageAError = "parse: \(error)"
            logProgress("[\(scene.id)]   Stage A2 parse error: \(error)")
        }
    case .failure(let err):
        stageAError = "transport: \(err)"
        logProgress("[\(scene.id)]   Stage A2 transport error: \(err)")
    }

    // Stage B: promotion gate.
    var postGate: [EntityDiscovery.Candidate] = []
    var gateRejects: [(EntityDiscovery.Candidate, EntityPromotionGate.Verdict)] = []
    for c in candidates {
        let verdict = EntityPromotionGate.evaluate(canonicalName: c.surface)
        if verdict == .promote {
            postGate.append(c)
        } else {
            gateRejects.append((c, verdict))
        }
    }
    logProgress("[\(scene.id)]   \(postGate.count) survive gate, \(gateRejects.count) rejected")

    // Stage D: normalise each survivor.
    var normalised: [EntityDiscovery.NormalisedEntity] = []
    var stageDErrors: [(String, String)] = []
    for c in postGate {
        logProgress("[\(scene.id)]   Stage D — normalising \(c.surface) ...")
        let dPrompt = EntityDiscovery.buildNormalisationPrompt(
            candidateSurface: c.surface,
            candidateKind: c.kind,
            firstSeenQuote: c.firstSeenQuote,
            scenePose: scene.prose
        )
        let dSchema = EntityDiscovery.normalisationJSONSchema()
        switch ollamaExtractSync(prompt: dPrompt, schema: dSchema) {
        case .success(let raw):
            do {
                let ent = try EntityDiscovery.parseNormalisedEntity(raw)
                normalised.append(ent)
            } catch {
                stageDErrors.append((c.surface, "parse: \(error)"))
            }
        case .failure(let err):
            stageDErrors.append((c.surface, "transport: \(err)"))
        }
    }

    // Convert normalised → ProposedSurface for scorer; convert
    // gold_entities → GoldSurface.
    let proposed: [EntityDiscoveryScorer.ProposedSurface] = normalised.map { ent in
        EntityDiscoveryScorer.ProposedSurface(
            canonicalName: ent.canonicalName,
            aliases: ent.aliases,
            kind: ent.kind
        )
    }
    let gold: [EntityDiscoveryScorer.GoldSurface] = scene.gold_entities.compactMap { g in
        guard let k = EntityDiscovery.Kind(rawValue: g.kind) else { return nil }
        return EntityDiscoveryScorer.GoldSurface(
            canonicalName: g.canonical_name,
            aliases: g.aliases,
            kind: k
        )
    }
    let scoreInput = EntityDiscoveryScorer.ScoreInput(
        sceneId: scene.id,
        proposed: proposed,
        gold: gold
    )

    let elapsed = Date().timeIntervalSince(started)
    return PipelineSceneResult(
        sceneId: scene.id,
        sceneTitle: scene.title,
        tag: scene.tag,
        elapsedSec: elapsed,
        rawCandidates: candidates,
        postGate: postGate,
        gateRejects: gateRejects,
        normalised: normalised,
        stageAError: stageAError,
        stageDErrors: stageDErrors,
        scoreInput: scoreInput
    )
}

// MARK: - Report

func renderReport(results: [PipelineSceneResult], aggregate: EntityDiscoveryScorer.Report) -> String {
    var out = ""
    out += "# EntityDiscoverySpike — live eval report\n\n"
    out += "**Generated**: \(ISO8601DateFormatter().string(from: Date()))  \n"
    out += "**Model**: \(ollamaModel) (at \(ollamaURLString))  \n"
    out += "**Fixture**: \(fixtureRelativePath)  \n"
    out += "**Scenes**: \(results.count)\n\n"

    // Aggregate
    out += "## Aggregate metrics\n\n"
    out += "| Metric | Value | §1 target | Pass? |\n"
    out += "|---|---|---|---|\n"
    let pPct = aggregate.precision * 100
    let rPct = aggregate.recall * 100
    let fPct = aggregate.f1 * 100
    out += "| Precision | \(String(format: "%.1f%%", pPct)) (\(aggregate.truePositives)/\(aggregate.truePositives + aggregate.falsePositives)) | ≥ 75% | \(aggregate.precision >= 0.75 ? "✓" : "✗") |\n"
    out += "| Recall    | \(String(format: "%.1f%%", rPct)) (\(aggregate.truePositives)/\(aggregate.truePositives + aggregate.falseNegatives)) | ≥ 60% | \(aggregate.recall >= 0.60 ? "✓" : "✗") |\n"
    out += "| F1        | \(String(format: "%.1f%%", fPct)) | — | — |\n"
    out += "\n"

    // Per-scene
    out += "## Per-scene breakdown\n\n"
    out += "| Scene | Tag | Raw → Gate → Norm | TP | FP | FN | Latency |\n"
    out += "|---|---|---|---|---|---|---|\n"
    for r in results {
        let tally = aggregate.perScene[r.sceneId]
        let tp = tally?.truePositives ?? 0
        let fp = tally?.falsePositives ?? 0
        let fn = tally?.falseNegatives ?? 0
        out += "| \(r.sceneId) **\(r.sceneTitle)** | \(r.tag) | \(r.rawCandidates.count) → \(r.postGate.count) → \(r.normalised.count) | \(tp) | \(fp) | \(fn) | \(String(format: "%.1fs", r.elapsedSec)) |\n"
    }
    out += "\n"

    // Latency
    let totalLatency = results.map(\.elapsedSec).reduce(0, +)
    let avgLatency = results.isEmpty ? 0 : totalLatency / Double(results.count)
    out += "**Avg latency/scene**: \(String(format: "%.1fs", avgLatency)) — §1 target ≤ 30 s — **\(avgLatency <= 30 ? "✓" : "✗")**\n\n"

    // Per-scene cap rate
    let overCap = results.filter { $0.normalised.count > 5 }.count
    out += "**Scenes exceeding ≤ 5 proposals cap**: \(overCap) / \(results.count) — §1 target 0 — **\(overCap == 0 ? "✓" : "✗")**\n\n"

    // Stage A / D failures
    let aErrors = results.compactMap { $0.stageAError }
    let dErrorCount = results.map { $0.stageDErrors.count }.reduce(0, +)
    out += "## Pipeline failures\n\n"
    out += "- **Stage A2 (candidate gen) errors**: \(aErrors.count) / \(results.count)\n"
    out += "- **Stage D (normalisation) errors**: \(dErrorCount) total across all candidates\n\n"
    if !aErrors.isEmpty {
        out += "**Stage A2 error detail**:\n\n"
        for (i, r) in results.enumerated() where r.stageAError != nil {
            out += "- \(r.sceneId): \(r.stageAError ?? "?")\n"
            _ = i
        }
        out += "\n"
    }
    if dErrorCount > 0 {
        out += "**Stage D error detail**:\n\n"
        for r in results where !r.stageDErrors.isEmpty {
            for e in r.stageDErrors {
                out += "- \(r.sceneId) / \(e.surface): \(e.error)\n"
            }
        }
        out += "\n"
    }

    // Per-scene details
    out += "## Per-scene details\n\n"
    for r in results {
        out += "### \(r.sceneId) — \(r.sceneTitle) [\(r.tag)]\n\n"
        out += "Raw A2 candidates (\(r.rawCandidates.count)):\n\n"
        for c in r.rawCandidates {
            let gateVerdict = EntityPromotionGate.evaluate(canonicalName: c.surface)
            let mark = gateVerdict == .promote ? "✓" : "✗"
            out += "- \(mark) `\(c.surface)` (\(c.kind.rawValue)) — gate=\(gateVerdict)\n"
        }
        if !r.normalised.isEmpty {
            out += "\nNormalised proposals (\(r.normalised.count)):\n\n"
            for n in r.normalised {
                let aliases = n.aliases.isEmpty ? "" : " (aliases: \(n.aliases.joined(separator: ", ")))"
                out += "- **\(n.canonicalName)**\(aliases) [\(n.kind.rawValue)] — \(n.oneLine)\n"
            }
        }
        out += "\n"
    }

    out += "## §6.4 decision criteria\n\n"
    out += "Per LOOM_ENTITY_DISCOVERY_SPIKE §1, the spike passes if **all** of:\n\n"
    out += "- Precision ≥ 75% — \(aggregate.precision >= 0.75 ? "✓" : "✗") (got \(String(format: "%.1f%%", pPct)))\n"
    out += "- Recall ≥ 60% — \(aggregate.recall >= 0.60 ? "✓" : "✗") (got \(String(format: "%.1f%%", rPct)))\n"
    out += "- Avg latency ≤ 30 s/scene — \(avgLatency <= 30 ? "✓" : "✗") (got \(String(format: "%.1fs", avgLatency)))\n"
    out += "- Per-scene cap ≤ 5 proposals — \(overCap == 0 ? "✓" : "✗") (\(overCap) scenes over)\n"
    return out
}

// MARK: - Main

func loadFixture() throws -> Fixture {
    let cwd = FileManager.default.currentDirectoryPath
    let url = URL(fileURLWithPath: cwd).appendingPathComponent(fixtureRelativePath)
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(Fixture.self, from: data)
}

logProgress("EntityDiscoverySpike — loading fixture from \(fixtureRelativePath)")
let fixture: Fixture
do { fixture = try loadFixture() } catch {
    logProgress("ERROR: failed to load fixture: \(error)")
    exit(1)
}
logProgress("Loaded \(fixture.scenes.count) scenes. Ollama: \(ollamaModel) at \(ollamaURLString)")

var results: [PipelineSceneResult] = []
for scene in fixture.scenes {
    results.append(runScene(scene))
}

let aggregate = EntityDiscoveryScorer.score(inputs: results.map(\.scoreInput))
let report = renderReport(results: results, aggregate: aggregate)
print(report)

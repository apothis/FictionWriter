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

let fixtureRelativePath = ProcessInfo.processInfo.environment["LOOM_SPIKE_FIXTURE"]
    ?? "Tests/LoomCoreTests/Fixtures/EntityDiscoverySpike/fixture.json"
let ollamaURLString = ProcessInfo.processInfo.environment["LOOM_SPIKE_OLLAMA_URL"]
    ?? "http://localhost:11434/"
let ollamaModel = ProcessInfo.processInfo.environment["LOOM_SPIKE_OLLAMA_MODEL"]
    ?? "gemma4_2b:latest"

// Detection step: "gliner" (the native NER tagger) or "llm" (the
// historical generative Stage A2). Either way Stage D normalisation
// stays on the LLM.
let detectorMode = (ProcessInfo.processInfo.environment["LOOM_SPIKE_DETECTOR"] ?? "gliner").lowercased()

/// Optional `--into <project-path>`: when present, every accepted
/// proposal (precision-filtered through Stages B-D as usual) gets
/// appended to that project's ProposedEntitiesStore so the Bible
/// Workspace webview's EntityProposalsQueue can review them.
let intoProjectURL: URL? = {
    let args = CommandLine.arguments
    guard let idx = args.firstIndex(of: "--into"), idx + 1 < args.count else {
        return nil
    }
    let path = args[idx + 1]
    let expanded = (path as NSString).expandingTildeInPath
    let url = URL(fileURLWithPath: expanded, isDirectory: true)
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
          isDir.boolValue else {
        logProgress("ERROR: --into target does not exist or is not a directory: \(expanded)")
        exit(2)
    }
    return url
}()

// MARK: - Sync-on-async HTTP wrapper

func ollamaExtractSync(prompt: String, schema: [String: Any], temperature: Double = 0.2) -> Result<String, Error> {
    guard let url = URL(string: "api/chat", relativeTo: URL(string: ollamaURLString))?.absoluteURL else {
        return .failure(NSError(domain: "Spike", code: -1, userInfo: [NSLocalizedDescriptionKey: "bad ollama url"]))
    }
    var body: [String: Any] = [
        "model": ollamaModel,
        "messages": [["role": "user", "content": prompt]],
        "stream": false,
        "options": [
            "temperature": temperature,
            "num_predict": 1024,
        ],
        "keep_alive": "30m",
    ]
    // An empty schema means unconstrained generation — omit `format`
    // entirely, mirroring OllamaClient.makeChatRequestBody (a literal
    // `format: {}` is not the same as omitting the key).
    if !schema.isEmpty {
        body["format"] = schema
    }
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

// MARK: - GLiNER detection (sync bridge)

/// Lazily-loaded GLiNER candidate detector — built only in gliner mode.
let glinerCandidateDetector: GLiNERCandidateDetector? = {
    guard detectorMode == "gliner" else { return nil }
    let sem = DispatchSemaphore(value: 0)
    final class Box: @unchecked Sendable { var detector: GLiNERDetector? }
    let box = Box()
    Task.detached {
        box.detector = try? await GLiNERDetector()
        sem.signal()
    }
    sem.wait()
    guard let detector = box.detector else {
        logProgress("ERROR: GLiNER detector failed to load — run Tools/GLiNERProbe/export_gliner_onnx.py")
        exit(3)
    }
    return GLiNERCandidateDetector(detector: detector)
}()

/// Run GLiNER detection on a scene, blocking until candidates land.
func glinerDetectSync(prose: String) -> Result<[EntityDiscovery.Candidate], Error> {
    guard let detector = glinerCandidateDetector else {
        return .failure(NSError(domain: "Spike", code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "no GLiNER detector"]))
    }
    let sem = DispatchSemaphore(value: 0)
    var result: Result<[EntityDiscovery.Candidate], Error> = .success([])
    detector.detectCandidates(in: prose) { result = $0; sem.signal() }
    sem.wait()
    return result
}

// MARK: - Pipeline

struct PipelineSceneResult {
    let sceneId: String
    let sceneTitle: String
    let tag: String
    let elapsedSec: TimeInterval
    let rawPreDedupCount: Int
    let rawCandidates: [EntityDiscovery.Candidate]
    let droppedAsKnown: [EntityDiscovery.Candidate]
    let droppedByPlaceRecurrence: [EntityDiscovery.Candidate]
    let postGate: [EntityDiscovery.Candidate]
    let gateRejects: [(candidate: EntityDiscovery.Candidate, verdict: EntityPromotionGate.Verdict)]
    let dedupMerged: [(candidate: EntityDiscovery.Candidate, mergedWith: String)]
    let normalised: [EntityDiscovery.NormalisedEntity]
    let stageAError: String?
    let stageARetried: Bool
    let stageDErrors: [(surface: String, error: String)]
    let scoreInput: EntityDiscoveryScorer.ScoreInput
}

/// Stage A2 with one-shot retry: re-prompt at higher temperature
/// if the first attempt fails to parse OR returns zero candidates
/// that survive the known-entity filter (often signals the model
/// over-applied the "don't emit known" instruction).
func runStageA2WithRetry(
    prompt: String,
    schema: [String: Any],
    knownNames: [String],
    sceneId: String
) -> (candidates: [EntityDiscovery.Candidate], retried: Bool, error: String?) {
    enum AttemptOutcome { case ok([EntityDiscovery.Candidate]); case err(String) }
    func attempt(_ temp: Double) -> AttemptOutcome {
        switch ollamaExtractSync(prompt: prompt, schema: schema, temperature: temp) {
        case .success(let raw):
            do { return .ok(try EntityDiscovery.parseCandidates(raw)) }
            catch { return .err("parse: \(error)") }
        case .failure(let err):
            return .err("transport: \(err)")
        }
    }

    // First attempt at temp 0.2 (deterministic-ish).
    let first = attempt(0.2)
    if case .ok(let cands) = first {
        // Success — even an empty result counts as a genuine answer
        // (null-discovery scenes legitimately produce []). Mode-
        // collapse vs null-discovery isn't disambiguable from the
        // output alone (run-4 finding: retrying on "all filtered as
        // known" eats latency in null-discovery scenes without
        // recovering anything in the mode-collapse case at temp 0.4).
        _ = knownNames
        return (cands, false, nil)
    }

    // First attempt errored (transport or parse). Retry once at
    // temp 0.4 — cheap insurance against transient JSON-parse
    // failures (run-1 saw 1/8 = 12.5% on eds-01).
    if case .err(let err) = first {
        logProgress("[\(sceneId)]   Stage A2 retry: \(err)")
    }
    let second = attempt(0.4)
    switch second {
    case .ok(let cands):
        return (cands, true, nil)
    case .err(let err):
        return ([], true, err)
    }
}

func runScene(_ scene: FixtureScene, embedder: EmbeddingClient?) -> PipelineSceneResult {
    let started = Date()
    let knownNames: [String] = {
        var names: [String] = []
        if let chars = scene.starting_bible.characters {
            for c in chars { names.append(c.name); names.append(contentsOf: c.aliases) }
        }
        if let sets = scene.starting_bible.settings {
            for s in sets { names.append(s.name); names.append(contentsOf: s.aliases) }
        }
        // Fix-4: expand with proper-noun tokens so "Vance" alone
        // gets caught as alias of "Karim Vance".
        return EntityDiscovery.expandKnownNamesWithTokens(names)
    }()
    let existingEntities: [EntityDedupEngine.ExistingEntity] = {
        var out: [EntityDedupEngine.ExistingEntity] = []
        if let chars = scene.starting_bible.characters {
            for c in chars {
                out.append(.init(id: UUID(), canonicalName: c.name, aliases: c.aliases))
            }
        }
        if let sets = scene.starting_bible.settings {
            for s in sets {
                out.append(.init(id: UUID(), canonicalName: s.name, aliases: s.aliases))
            }
        }
        return out
    }()

    let rawCands: [EntityDiscovery.Candidate]
    let stageARetried: Bool
    let stageAError: String?
    if detectorMode == "gliner" {
        logProgress("[\(scene.id)] GLiNER detection ...")
        switch glinerDetectSync(prose: scene.prose) {
        case .success(let cands):
            rawCands = cands
            stageARetried = false
            stageAError = nil
        case .failure(let err):
            rawCands = []
            stageARetried = false
            stageAError = "gliner: \(err)"
        }
    } else {
        logProgress("[\(scene.id)] Stage A2 — candidate gen ...")
        let a2Prompt = EntityDiscovery.buildCandidateGenerationPrompt(
            scenePose: scene.prose,
            knownEntityNames: knownNames
        )
        let a2Schema = EntityDiscovery.candidateGenerationJSONSchema()
        (rawCands, stageARetried, stageAError) = runStageA2WithRetry(
            prompt: a2Prompt,
            schema: a2Schema,
            knownNames: knownNames,
            sceneId: scene.id
        )
    }
    logProgress("[\(scene.id)]   got \(rawCands.count) candidates\(stageARetried ? " (after retry)" : "")")

    // Collapse duplicate mentions of the same entity before any
    // downstream work — matches EntityDiscoveryPipeline.applyFilters'
    // first step. Load-bearing for GLiNER detection, which emits one
    // candidate per *mention* ("Chantal" ×40 in a scene); each survivor
    // otherwise costs a serialised Stage D LLM call.
    let rawPreDedupCount = rawCands.count
    var candidates = EntityDiscovery.dedupCandidatesBySurface(rawCands)
    if candidates.count < rawCands.count {
        logProgress("[\(scene.id)]   dedupBySurface: \(rawCands.count) → \(candidates.count)")
    }
    // Snapshot the deduped output for the report's funnel.
    let rawCandidatesSnapshot = candidates

    // Fix-1: pre-gate known-entity filter (structural enforcement
    // of the prompt's "don't re-propose known entities" instruction
    // since gemma4_2b ignores it).
    var droppedAsKnown: [EntityDiscovery.Candidate] = []
    candidates = candidates.filter { c in
        let known = EntityDiscovery.isKnownSurface(c.surface, knownNames: knownNames)
        if known { droppedAsKnown.append(c) }
        return !known
    }
    if droppedAsKnown.count > 0 {
        logProgress("[\(scene.id)]   dropped \(droppedAsKnown.count)/\(rawCandidatesSnapshot.count) as already-known")
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
    logProgress("[\(scene.id)]   \(postGate.count) survive gate, \(gateRejects.count) gate-rejected")

    // Fix-3: place recurrence filter (drops single-mention non-
    // "The"-prefix places like Brussels, Edinburgh).
    var droppedByPlaceRecurrence: [EntityDiscovery.Candidate] = []
    postGate = postGate.filter { c in
        let pass = EntityDiscovery.passesPlaceRecurrence(
            surface: c.surface, kind: c.kind, scenePose: scene.prose
        )
        if !pass { droppedByPlaceRecurrence.append(c) }
        return pass
    }
    if droppedByPlaceRecurrence.count > 0 {
        logProgress("[\(scene.id)]   dropped \(droppedByPlaceRecurrence.count) as single-mention places")
    }

    // Fix-2: Stage C dedup against starting-bible entities. Same-
    // person-different-surface ("Marius Thorn" / "Dr Thorn") is
    // the typical case. Embedding-based — skipped if no embedder
    // is available (fallback for environments without the
    // CoreML bundle).
    var dedupMerged: [(EntityDiscovery.Candidate, String)] = []
    if let embedder = embedder, !existingEntities.isEmpty {
        // First pass: dedup vs starting bible.
        postGate = postGate.filter { c in
            let v = EntityDedupEngine.evaluate(
                candidateName: c.surface,
                candidateEvidenceQuote: c.firstSeenQuote,
                existingEntities: existingEntities,
                embedder: embedder
            )
            switch v {
            case .mergesWith(let id, _):
                let merged = existingEntities.first(where: { $0.id == id })?.canonicalName ?? "?"
                dedupMerged.append((c, merged))
                return false
            case .ambiguous, .proposeAsNew:
                return true
            }
        }
    }
    // Second pass: dedup within this batch — same candidate
    // proposed twice ("Marius Thorn" and "Dr Thorn") collapses
    // to one. Iterative: accept first, embed against accepted,
    // collapse subsequent.
    if let embedder = embedder, postGate.count > 1 {
        var accepted: [EntityDedupEngine.ExistingEntity] = []
        var kept: [EntityDiscovery.Candidate] = []
        for c in postGate {
            if accepted.isEmpty {
                accepted.append(.init(id: UUID(), canonicalName: c.surface, aliases: []))
                kept.append(c)
                continue
            }
            let v = EntityDedupEngine.evaluate(
                candidateName: c.surface,
                candidateEvidenceQuote: c.firstSeenQuote,
                existingEntities: accepted,
                embedder: embedder
            )
            switch v {
            case .mergesWith(let id, _):
                let merged = accepted.first(where: { $0.id == id })?.canonicalName ?? "?"
                dedupMerged.append((c, merged))
            case .ambiguous, .proposeAsNew:
                accepted.append(.init(id: UUID(), canonicalName: c.surface, aliases: []))
                kept.append(c)
            }
        }
        postGate = kept
    }
    if dedupMerged.count > 0 {
        logProgress("[\(scene.id)]   dedup merged \(dedupMerged.count) candidates")
    }

    // Stage D: normalise each survivor IN PARALLEL. Each call is
    // independent (no shared context between Stage D normalisations
    // of different candidates), so fan-out cuts latency roughly
    // linearly with the candidate count. The Ollama server queues
    // internally — practical concurrency is bounded by the model
    // load slot, but the wall-clock win is still real for the
    // multi-candidate scenes (eds-07 with 4 candidates drops from
    // ~45s sequential to ~13s parallel in observed runs).
    // Stage D runs unconstrained — production dropped the `format`
    // schema (it degenerates on gemma4_2b); the prompt pins the shape.
    let dSchema: [String: Any] = [:]
    let group = DispatchGroup()
    let lock = NSLock()
    enum StageDOutcome { case ok(EntityDiscovery.NormalisedEntity); case err(String) }
    var byIndex: [Int: StageDOutcome] = [:]
    var stageDErrors: [(String, String)] = []
    if !postGate.isEmpty {
        logProgress("[\(scene.id)]   Stage D — normalising \(postGate.count) candidates in parallel ...")
    }
    for (i, c) in postGate.enumerated() {
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let dPrompt = EntityDiscovery.buildNormalisationPrompt(
                candidateSurface: c.surface,
                candidateKind: c.kind,
                firstSeenQuote: c.firstSeenQuote,
                scenePose: EntityDiscovery.sceneWindow(around: c, in: scene.prose)
            )
            let outcome: StageDOutcome
            switch ollamaExtractSync(prompt: dPrompt, schema: dSchema) {
            case .success(let raw):
                do {
                    outcome = .ok(try EntityDiscovery.parseNormalisedEntity(raw))
                } catch {
                    outcome = .err("parse: \(error)")
                }
            case .failure(let err):
                outcome = .err("transport: \(err)")
            }
            lock.lock()
            byIndex[i] = outcome
            lock.unlock()
            group.leave()
        }
    }
    group.wait()

    // Re-collect results in original order so the report is stable
    // run-to-run regardless of completion-order races.
    var normalised: [EntityDiscovery.NormalisedEntity] = []
    for (i, c) in postGate.enumerated() {
        switch byIndex[i] {
        case .ok(let ent):
            normalised.append(ent)
        case .err(let msg):
            stageDErrors.append((c.surface, msg))
        case .none:
            stageDErrors.append((c.surface, "missing result (shouldn't happen)"))
        }
    }

    // Fix-5: post-Stage-D dedup on identical canonical names —
    // catches the eds-06 "Marius Thorn" duplicate that Wegmann
    // style-embedding didn't merge at Stage C.
    let preMergeCount = normalised.count
    normalised = EntityDiscovery.dedupByCanonicalName(normalised)
    if normalised.count < preMergeCount {
        logProgress("[\(scene.id)]   post-Stage-D dedup merged \(preMergeCount - normalised.count)")
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
        rawPreDedupCount: rawPreDedupCount,
        rawCandidates: rawCandidatesSnapshot,
        droppedAsKnown: droppedAsKnown,
        droppedByPlaceRecurrence: droppedByPlaceRecurrence,
        postGate: postGate,
        gateRejects: gateRejects,
        dedupMerged: dedupMerged,
        normalised: normalised,
        stageAError: stageAError,
        stageARetried: stageARetried,
        stageDErrors: stageDErrors,
        scoreInput: scoreInput
    )
}

// MARK: - Report

func renderReport(results: [PipelineSceneResult], aggregate: EntityDiscoveryScorer.Report) -> String {
    var out = ""
    out += "# EntityDiscoverySpike — live eval report\n\n"
    out += "**Generated**: \(ISO8601DateFormatter().string(from: Date()))  \n"
    out += "**Detector**: \(detectorMode == "gliner" ? "GLiNER (native NER)" : "LLM Stage A2")  \n"
    out += "**Model** (Stage D normalisation): \(ollamaModel) (at \(ollamaURLString))  \n"
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
    out += "| Scene | Tag | Raw → Dedup → -Known → +Gate → +Place → +CosineDedup → Norm | TP | FP | FN | Latency |\n"
    out += "|---|---|---|---|---|---|---|\n"
    for r in results {
        let tally = aggregate.perScene[r.sceneId]
        let tp = tally?.truePositives ?? 0
        let fp = tally?.falsePositives ?? 0
        let fn = tally?.falseNegatives ?? 0
        let afterKnown = r.rawCandidates.count - r.droppedAsKnown.count
        let afterGate = afterKnown - r.gateRejects.count
        let afterPlace = afterGate - r.droppedByPlaceRecurrence.count
        let afterDedup = r.postGate.count
        out += "| \(r.sceneId) **\(r.sceneTitle)** | \(r.tag) | \(r.rawPreDedupCount) → \(r.rawCandidates.count) → \(afterKnown) → \(afterGate) → \(afterPlace) → \(afterDedup) → \(r.normalised.count) | \(tp) | \(fp) | \(fn) | \(String(format: "%.1fs", r.elapsedSec)) |\n"
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

// Try to resolve the CoreML Wegmann bundle for dedup. The bundle
// lives in LoomCore's resources; from a sibling executable target
// `Bundle.module` resolves to this Tools/ target which has no
// resources. Fall back to constructing a path from CWD.
let embedder: EmbeddingClient? = {
    let cwd = FileManager.default.currentDirectoryPath
    let bundle = URL(fileURLWithPath: cwd)
        .appendingPathComponent("Sources/LoomCore/Resources/StyleEmbedding")
    if FileManager.default.fileExists(atPath: bundle.path) {
        logProgress("Dedup: CoreML Wegmann at \(bundle.path)")
        return CoreMLEmbeddingClient(bundleURL: bundle)
    }
    logProgress("Dedup: no embedder available — skipping Stage C")
    return nil
}()

var results: [PipelineSceneResult] = []
for scene in fixture.scenes {
    results.append(runScene(scene, embedder: embedder))
}

// Optional `--into <project>` writes the spike's normalised
// proposals into the target project's ProposedEntitiesStore so the
// Bible Workspace webview can render them. The fixture's eds-NN
// scene ids don't correspond to any real project scene, so source
// scene UUIDs are synthesised here and the snapshot renders them as
// "(unknown scene)" — demo-grade plumbing; real editor-triggered
// discovery will bind to actual scene UUIDs.
if let projectURL = intoProjectURL {
    var entities: [EntityDiscovery.ProposedEntity] = []
    for r in results {
        let syntheticSceneId = UUID()
        for n in r.normalised {
            entities.append(EntityDiscovery.ProposedEntity(
                id: UUID(),
                kind: n.kind,
                canonicalName: n.canonicalName,
                aliases: n.aliases,
                oneLine: n.oneLine,
                evidenceQuote: n.evidenceQuote,
                sourceSceneId: syntheticSceneId,
                confidence: 0.8
            ))
        }
    }
    do {
        try ProposedEntitiesStore.append(entities: entities, facts: [], in: projectURL)
        logProgress("--into: wrote \(entities.count) proposals to \(projectURL.appendingPathComponent("proposed-entities/proposed-entities.json").path)")
    } catch {
        logProgress("--into: ERROR writing proposals: \(error)")
    }
}

let aggregate = EntityDiscoveryScorer.score(inputs: results.map(\.scoreInput))
let report = renderReport(results: results, aggregate: aggregate)
print(report)

import Foundation
import LoomCore

// Continuity Audit (L10) — Phase A feasibility spike
// (LOOM_CONTINUITY_AUDIT.md §10). One-off runner: loads the
// ContinuityAuditSpike fixture and drives it through the two
// LLM-facing ends of the audit pipeline, scoring each against the
// hand-graded gold set.
//
//   1. EXTRACTION — per-scene typed-claim extraction (Ollama,
//      schema-constrained). Scored as recall of the planted gold
//      claims.
//   2. ADJUDICATION — pairwise verdict on each gold claim pair.
//      Scored as contradiction precision / recall / F1 plus a
//      confusion matrix. THIS is the make-or-break number — ContraDoc
//      showed whole-document judging tops out near 54% precision.
//
// Run:  swift run ContinuityAuditSpike
//   LOOM_SPIKE_FIXTURE      default Tests/.../ContinuityAuditSpike/fixture.json
//   LOOM_SPIKE_OLLAMA_URL   default http://localhost:11434
//   LOOM_SPIKE_OLLAMA_MODEL extraction model, default gemma4_2b:latest
//   LOOM_SPIKE_PHASE        both | extract | adjudicate | engine | eval
//                                                         (default both)
//   LOOM_SPIKE_ADJ_BACKEND  ollama | kobold               (default ollama)
//   LOOM_SPIKE_ADJ_MODEL    ollama adjudication model, default = extraction model
//   LOOM_SPIKE_KOBOLD_URL   default http://192.168.1.201:5001
//
// The `eval` phase is the multi-run eval harness (LOOM_CONTINUITY_AUDIT
// §21): it drives the four-manuscript eval fixture set k times and scores
// it with `ContinuityEvalMetrics` — extraction recall (mean ± CI, Chao1
// coverage) and end-to-end findings (precision/recall, pass@k vs pass^k).
//   LOOM_EVAL_RUNS          runs per scene / per manuscript   (default 5)
//   LOOM_EVAL_MODE          extract | engine | both           (default extract)
//   LOOM_EVAL_FIXTURE_DIR   default Tests/.../ContinuityAuditEval

// MARK: - stderr progress

struct Stderr: TextOutputStream {
    mutating func write(_ s: String) { FileHandle.standardError.write(Data(s.utf8)) }
}
var errStream = Stderr()
func log(_ s: String) { print(s, to: &errStream) }

// MARK: - Fixture

struct Fixture: Codable {
    let scenes: [FScene]
    let gold_claims: [FGoldClaim]
    let gold_pairs: [FGoldPair]
}
struct FScene: Codable { let id: String; let title: String; let prose: String }
struct FGoldClaim: Codable { let scene: String; let type: String; let subject: String; let value: String }
struct FGoldPair: Codable {
    let id: String
    let verdict: String
    let note: String
    let earlier: FClaim
    let later: FClaim
    private enum CodingKeys: String, CodingKey { case id, verdict, note, earlier, later }
}
struct FClaim: Codable {
    let type: String, subject: String, attribute_key: String
    let value: String, scene: String, source: String, evidence_quote: String
}

// Eval-harness fixture (schema v2) — one manuscript with gold findings.
struct EvalManuscript: Codable {
    let id: String
    let title: String
    let genre: String
    let scenes: [FScene]
    let gold_claims: [FGoldClaim]
    let gold_pairs: [FGoldPair]
    let gold_contradictions: [FGoldContradiction]
}
struct FGoldContradiction: Codable {
    let id: String, kind: String
    let scene_a: String, scene_b: String, scene_distance: Int
    let subject: String, summary: String
    let value_a: String, value_b: String
}

func toGoldClaim(_ f: FGoldClaim) -> ContinuityEvalMetrics.GoldClaim {
    ContinuityEvalMetrics.GoldClaim(
        scene: f.scene,
        type: ContinuityAudit.ClaimType(rawValue: f.type) ?? .event,
        subject: f.subject, value: f.value)
}

func toGoldContradiction(_ f: FGoldContradiction) -> ContinuityEvalMetrics.GoldContradiction? {
    guard let kind = ContinuityFinding.Kind(rawValue: f.kind) else { return nil }
    return ContinuityEvalMetrics.GoldContradiction(
        id: f.id, kind: kind, sceneA: f.scene_a, sceneB: f.scene_b,
        valueA: f.value_a, valueB: f.value_b, sceneDistance: f.scene_distance)
}

func toClaim(_ f: FClaim) -> ContinuityAudit.Claim {
    ContinuityAudit.Claim(
        type: ContinuityAudit.ClaimType(rawValue: f.type) ?? .event,
        subject: f.subject, attributeKey: f.attribute_key, value: f.value,
        sourceSceneId: f.scene,
        source: ContinuityAudit.ClaimSource(rawValue: f.source) ?? .narration,
        evidenceQuote: f.evidence_quote
    )
}

// MARK: - Config

let env = ProcessInfo.processInfo.environment
let fixturePath = env["LOOM_SPIKE_FIXTURE"]
    ?? "Tests/LoomCoreTests/Fixtures/ContinuityAuditSpike/fixture.json"
let ollamaURL = env["LOOM_SPIKE_OLLAMA_URL"] ?? "http://localhost:11434"
let extractModel = env["LOOM_SPIKE_OLLAMA_MODEL"] ?? "gemma4_2b:latest"
let phase = env["LOOM_SPIKE_PHASE"] ?? "both"
let extractBackend = env["LOOM_SPIKE_EXTRACT_BACKEND"] ?? "ollama"
let adjBackend = env["LOOM_SPIKE_ADJ_BACKEND"] ?? "ollama"
let adjModel = env["LOOM_SPIKE_ADJ_MODEL"] ?? extractModel
let koboldURL = env["LOOM_SPIKE_KOBOLD_URL"] ?? "http://192.168.1.201:5001"

// Kobold instruct template — detected from the loaded model name so the
// model-vs-model A/B wraps prompts in the right chat format (Mistral for
// Goetia, ChatML for Qwen, Gemma for Gemma). The wrong template degrades
// a model and would make the comparison invalid. Override with
// LOOM_SPIKE_KOBOLD_TEMPLATE if a model's filename defeats detection.
let koboldModelName: String = {
    guard let url = URL(string: "/api/v1/model", relativeTo: URL(string: koboldURL)!)?.absoluteURL
    else { return "" }
    let sem = DispatchSemaphore(value: 0)
    var name = ""
    URLSession.shared.dataTask(with: url) { data, _, _ in
        defer { sem.signal() }
        if let data = data,
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let r = obj["result"] as? String { name = r }
    }.resume()
    sem.wait()
    return name
}()
let koboldTemplate: InstructTemplate = {
    if let override = env["LOOM_SPIKE_KOBOLD_TEMPLATE"],
       let t = InstructTemplate(rawValue: override) { return t }
    return InstructTemplates.detect(forModelName: koboldModelName) ?? .mistralV7
}()

/// Wrap a bare prompt in the detected model family's instruct template.
/// Returns the wrapped text and the family's stop sequences.
func koboldWrap(_ prompt: String) -> (text: String, stops: [String]) {
    let adapter = InstructTemplates.adapter(for: koboldTemplate)
    // ChatML / Qwen 3.x: suppress default chain-of-thought via an empty
    // think block in the prefill (the PromptBuilder.prefillFor pattern).
    let prefill = koboldTemplate == .chatml ? "<think>\n\n</think>\n\n" : ""
    return (adapter.wrap(system: "", userBody: prompt, prefill: prefill),
            adapter.stopSequences)
}
log("kobold model: \(koboldModelName.isEmpty ? "?" : koboldModelName) → template \(koboldTemplate.rawValue)")

guard let fixtureData = FileManager.default.contents(atPath: fixturePath),
      let fixture = try? JSONDecoder().decode(Fixture.self, from: fixtureData) else {
    log("FATAL: cannot load fixture at \(fixturePath)")
    exit(1)
}

// MARK: - Sync call helpers (CLI blocks the main thread on a semaphore;
// OllamaClient / URLSession fire completions off-main, so no deadlock).

let ollama = OllamaClient(baseURL: URL(string: ollamaURL)!, model: extractModel)
let ollamaAdj = OllamaClient(baseURL: URL(string: ollamaURL)!, model: adjModel)

/// A KoboldCpp `/api/v1/generate` provider — lets the production
/// `OllamaContinuityExtractor` run on the writer model (Goetia, 24B)
/// instead of the small Ollama extractor. `[INST]`-wrapped, unconstrained.
final class KoboldGenerateProvider: OllamaCallProvider {
    let baseURL: URL
    init(baseURL: URL) { self.baseURL = baseURL }
    func call(
        prompt: String, schema: [String: Any], options: OllamaChatOptions,
        completion: @escaping (Result<String, OllamaError>) -> Void
    ) {
        guard let url = URL(string: "/api/v1/generate", relativeTo: baseURL)?.absoluteURL else {
            completion(.failure(.badURL)); return
        }
        let wrapped = koboldWrap(prompt)
        let body: [String: Any] = [
            "prompt": wrapped.text,
            "max_length": options.numPredict, "max_context_length": 8192,
            "temperature": 0.2, "top_p": 0.9, "min_p": 0.05, "rep_pen": 1.05,
            "stop_sequence": wrapped.stops,
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 600
        URLSession(configuration: cfg).dataTask(with: req) { data, _, err in
            if let err = err { completion(.failure(.transport("\(err)"))); return }
            guard let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = obj["results"] as? [[String: Any]],
                  let text = results.first?["text"] as? String
            else { completion(.failure(.unexpectedShape)); return }
            completion(.success(text))
        }.resume()
    }
}

/// An Ollama `/api/embed` provider conforming to `KoboldEmbedding` —
/// lets the engine's claim-filter pipeline run against a local text
/// embedder (bge-large / mxbai-embed-large).
final class OllamaEmbedProvider: KoboldEmbedding {
    let baseURL: URL
    let model: String
    init(baseURL: URL, model: String) { self.baseURL = baseURL; self.model = model }
    func embed(texts: [String], completion: @escaping (Result<[[Float]], Error>) -> Void) {
        guard let url = URL(string: "/api/embed", relativeTo: baseURL)?.absoluteURL else {
            completion(.failure(OllamaError.badURL)); return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(
            withJSONObject: ["model": model, "input": texts])
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 600
        URLSession(configuration: cfg).dataTask(with: req) { data, _, err in
            if let err = err { completion(.failure(err)); return }
            guard let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rows = obj["embeddings"] as? [[Any]]
            else { completion(.failure(OllamaError.unexpectedShape)); return }
            completion(.success(rows.map { row in row.map { ($0 as? NSNumber)?.floatValue ?? 0 } }))
        }.resume()
    }
}

// Extraction goes through the production OllamaContinuityExtractor —
// unconstrained generation + re-roll, the corrected path. The backend
// is selectable: the small Ollama extractor, or the 24B Goetia writer
// on KoboldCpp (LOOM_SPIKE_EXTRACT_BACKEND).
let extractProvider: OllamaCallProvider = extractBackend == "kobold"
    ? KoboldGenerateProvider(baseURL: URL(string: koboldURL)!)
    : ollama
let continuityExtractor = OllamaContinuityExtractor(provider: extractProvider)

func extractClaims(prose: String, sceneId: String) -> [ContinuityAudit.Claim] {
    let sem = DispatchSemaphore(value: 0)
    var out: [ContinuityAudit.Claim] = []
    continuityExtractor.extract(scenePose: prose, sceneId: sceneId) { result in
        out = (try? result.get()) ?? []
        sem.signal()
    }
    sem.wait()
    return out
}

func callOllama(_ client: OllamaClient, prompt: String, schema: [String: Any]) -> String? {
    let sem = DispatchSemaphore(value: 0)
    var out: String? = nil
    client.extract(prompt: prompt, schema: schema,
                   options: OllamaChatOptions(temperature: 0.2)) { result in
        if case .success(let text) = result { out = text }
        else if case .failure(let e) = result { log("  ollama error: \(e)") }
        sem.signal()
    }
    sem.wait()
    return out
}

func callKobold(prompt: String) -> String? {
    guard let url = URL(string: "/api/v1/generate", relativeTo: URL(string: koboldURL)!)?.absoluteURL
    else { return nil }
    let wrapped = koboldWrap(prompt)
    let body: [String: Any] = [
        "prompt": wrapped.text,
        "max_length": 512, "max_context_length": 8192,
        "temperature": 0.2, "top_p": 0.9, "min_p": 0.05, "rep_pen": 1.05,
        "stop_sequence": wrapped.stops,
    ]
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try? JSONSerialization.data(withJSONObject: body)
    let cfg = URLSessionConfiguration.default
    cfg.timeoutIntervalForRequest = 600
    let sem = DispatchSemaphore(value: 0)
    var out: String? = nil
    URLSession(configuration: cfg).dataTask(with: req) { data, _, err in
        defer { sem.signal() }
        if let err = err { log("  kobold error: \(err)"); return }
        guard let data = data,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = obj["results"] as? [[String: Any]],
              let text = results.first?["text"] as? String else { return }
        out = text
    }.resume()
    sem.wait()
    return out
}

func adjudicateRaw(_ prompt: String) -> String? {
    adjBackend == "kobold" ? callKobold(prompt: prompt)
                           : callOllama(ollamaAdj, prompt: prompt, schema: ContinuityAudit.adjudicationJSONSchema())
}

// MARK: - Word-set Jaccard (for fuzzy extraction-recall matching)

let stop: Set<String> = ["a","an","the","is","was","were","be","of","in","on","at","to","for","and","or","it","has","have","had"]
func words(_ s: String) -> Set<String> {
    Set(s.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { !stop.contains($0) })
}
func jaccard(_ a: String, _ b: String) -> Double {
    let x = words(a), y = words(b)
    if x.isEmpty && y.isEmpty { return 1 }
    let u = x.union(y).count
    return u == 0 ? 0 : Double(x.intersection(y).count) / Double(u)
}

// MARK: - Report

var report = "# ContinuityAuditSpike\n\n"
let koboldDesc = "\(koboldModelName.isEmpty ? "?" : koboldModelName) [\(koboldTemplate.rawValue)] @ \(koboldURL)"
report += "- **Extraction**: \(extractBackend == "kobold" ? koboldDesc : "\(extractModel) @ \(ollamaURL)")\n"
report += "- **Adjudication**: \(adjBackend == "kobold" ? koboldDesc : "\(adjModel) @ \(ollamaURL)")\n"
report += "- **Fixture**: \(fixture.scenes.count) scenes, \(fixture.gold_claims.count) gold claims, \(fixture.gold_pairs.count) gold pairs\n\n"

// MARK: - Probe phase — §25 Part B same-fact judgment de-risk
//
// Sources real extracted-claim pairs from one eval manuscript (default
// `lighthouse`), labels them mechanically using the gold contradictions
// (within-cluster = `same_fact`, cross-cluster at the same gold site =
// `different_fact`), runs the same-fact prompt on each, and reports a
// confusion matrix. The §26 lesson: this is the production-noisy probe
// the NLI path never did — the inputs are the actual extracted
// paraphrases the audit will feed Part B's canonicalisation step, not
// gold reference strings.
//
//   LOOM_PROBE_MANUSCRIPT    default lighthouse
//   LOOM_PROBE_EXTRACT_RUNS  default 3 (gives ~2-3 paraphrases per cluster)
//   LOOM_PROBE_OUT_DIR       default Tools/ContinuityAuditSpike/probe/
//   LOOM_PROBE_MATCH_THRESHOLD  default 0.34 (eval matcher's threshold)

if phase == "probe" {
    let probeManuscriptId = env["LOOM_PROBE_MANUSCRIPT"] ?? "lighthouse"
    let probeRuns = Int(env["LOOM_PROBE_EXTRACT_RUNS"] ?? "") ?? 3
    let probeOutDir = env["LOOM_PROBE_OUT_DIR"]
        ?? "Tools/ContinuityAuditSpike/probe"
    let matchThreshold = Double(env["LOOM_PROBE_MATCH_THRESHOLD"] ?? "") ?? 0.34
    let evalDir = env["LOOM_EVAL_FIXTURE_DIR"]
        ?? "Tests/LoomCoreTests/Fixtures/ContinuityAuditEval"

    let fm = FileManager.default
    try? fm.createDirectory(atPath: probeOutDir, withIntermediateDirectories: true)

    guard let files = try? fm.contentsOfDirectory(atPath: evalDir) else {
        log("FATAL: cannot list eval fixture dir \(evalDir)"); exit(1)
    }
    var picked: EvalManuscript? = nil
    for file in files.sorted() where file.hasSuffix(".json") {
        guard let data = fm.contents(atPath: evalDir + "/" + file),
              let m = try? JSONDecoder().decode(EvalManuscript.self, from: data),
              m.id == probeManuscriptId else { continue }
        picked = m
        break
    }
    guard let manuscript = picked else {
        log("FATAL: no eval manuscript with id=\(probeManuscriptId) in \(evalDir)"); exit(1)
    }
    log("== PROBE: same-fact judgment ==")
    log("  manuscript: \(manuscript.id) (\(manuscript.scenes.count) scenes, \(manuscript.gold_contradictions.count) gold contradictions)")
    log("  extraction: \(extractBackend == "kobold" ? koboldDesc : "\(extractModel) @ \(ollamaURL)") · runs=\(probeRuns)")
    log("  adjudication: \(adjBackend == "kobold" ? koboldDesc : "\(adjModel) @ \(ollamaURL)")")
    log("  out dir: \(probeOutDir)")

    // --- 1. Multi-run extraction. Same call path as the production
    // audit — `extractClaims` already uses `OllamaContinuityExtractor`
    // with the chosen backend. Multiple runs give us paraphrases per
    // underlying fact, which is what makes same-fact pairs available.
    struct ExtractedClaim: Codable {
        let run: Int
        let scene: String
        let type: String
        let subject: String
        let attribute_key: String
        let value: String
        let source: String
        let evidence_quote: String
    }
    var extracted: [ExtractedClaim] = []
    for run in 0..<probeRuns {
        for scene in manuscript.scenes {
            log("  extract: \(manuscript.id)/\(scene.id) run \(run + 1)/\(probeRuns) …")
            let claims = extractClaims(prose: scene.prose, sceneId: scene.id)
            for c in claims {
                extracted.append(ExtractedClaim(
                    run: run, scene: scene.id,
                    type: c.type.rawValue, subject: c.subject,
                    attribute_key: c.attributeKey, value: c.value,
                    source: c.source.rawValue, evidence_quote: c.evidenceQuote))
            }
        }
    }
    log("  extracted total: \(extracted.count) claims (\(probeRuns) runs × \(manuscript.scenes.count) scenes)")
    let claimsPath = probeOutDir + "/claims.json"
    if let data = try? JSONEncoder().encode(extracted) {
        try? data.write(to: URL(fileURLWithPath: claimsPath))
        log("  wrote \(claimsPath)")
    }

    // --- 2. Label pairs using gold contradictions. A non-knowledge
    // contradiction g links `value_a` in `scene_a` to `value_b` in
    // `scene_b`. The eval matcher's Jaccard ≥ 0.34 against the gold
    // value defines cluster membership — same procedure that scores
    // recall, so the labels track the eval's own truth.
    struct LabelledPair: Codable {
        let id: String
        let label: String          // same_fact | different_fact
        let goldId: String
        let claimA: ExtractedClaim
        let claimB: ExtractedClaim
    }
    func clusterMembership(_ c: ExtractedClaim, valueGold: String, sceneGold: String)
        -> Bool
    {
        c.scene == sceneGold && jaccard(c.value, valueGold) >= matchThreshold
    }
    var pairs: [LabelledPair] = []
    var sameFactCount = 0, differentFactCount = 0
    // Skip knowledge_violation — it is the Part B target, not the
    // class we're canonicalising; the gold value_a there is a
    // reference, not a fact assertion.
    for g in manuscript.gold_contradictions where g.kind != "knowledge_violation" {
        let clusterA = extracted.filter { clusterMembership($0, valueGold: g.value_a, sceneGold: g.scene_a) }
        let clusterB = extracted.filter { clusterMembership($0, valueGold: g.value_b, sceneGold: g.scene_b) }
        // within-cluster same-fact pairs
        for cluster in [clusterA, clusterB] {
            for i in 0..<cluster.count {
                for j in (i + 1)..<cluster.count {
                    pairs.append(LabelledPair(
                        id: "\(g.id)-sf-\(pairs.count)",
                        label: "same_fact",
                        goldId: g.id,
                        claimA: cluster[i], claimB: cluster[j]))
                    sameFactCount += 1
                }
            }
        }
        // cross-cluster different-fact pairs (same topic, different proposition)
        for a in clusterA {
            for b in clusterB {
                pairs.append(LabelledPair(
                    id: "\(g.id)-df-\(pairs.count)",
                    label: "different_fact",
                    goldId: g.id,
                    claimA: a, claimB: b))
                differentFactCount += 1
            }
        }
    }
    log("  pairs: \(pairs.count) total · same_fact=\(sameFactCount) · different_fact=\(differentFactCount)")
    let pairsPath = probeOutDir + "/pairs.json"
    if let data = try? JSONEncoder().encode(pairs) {
        try? data.write(to: URL(fileURLWithPath: pairsPath))
        log("  wrote \(pairsPath)")
    }
    guard !pairs.isEmpty else {
        log("FATAL: no labelled pairs — extraction recall on lighthouse may be too thin")
        exit(1)
    }

    // --- 3. Score each pair with the same-fact prompt against the
    // adjudication backend (Kobold + Gemma-4-31B in the standard
    // probe configuration).
    func extractedToClaim(_ e: ExtractedClaim) -> ContinuityAudit.Claim {
        ContinuityAudit.Claim(
            type: ContinuityAudit.ClaimType(rawValue: e.type) ?? .event,
            subject: e.subject, attributeKey: e.attribute_key, value: e.value,
            sourceSceneId: e.scene,
            source: ContinuityAudit.ClaimSource(rawValue: e.source) ?? .narration,
            evidenceQuote: e.evidence_quote)
    }
    func sameFactRaw(prompt: String) -> String? {
        adjBackend == "kobold"
            ? callKobold(prompt: prompt)
            : callOllama(ollamaAdj, prompt: prompt, schema: ContinuityAudit.sameFactJSONSchema())
    }
    struct Verdict: Codable {
        let pairId: String
        let label: String
        let predicted: String
        let confidence: Double
        let explanation: String
        let raw: String
    }
    var verdicts: [Verdict] = []
    for (i, pair) in pairs.enumerated() {
        log("  probe: pair \(i + 1)/\(pairs.count) [\(pair.label)] …")
        let prompt = ContinuityAudit.buildSameFactPrompt(
            claimA: extractedToClaim(pair.claimA),
            claimB: extractedToClaim(pair.claimB))
        let raw = sameFactRaw(prompt: prompt) ?? ""
        if let j = try? ContinuityAudit.parseSameFact(raw) {
            verdicts.append(Verdict(
                pairId: pair.id, label: pair.label,
                predicted: j.verdict.rawValue, confidence: j.confidence,
                explanation: j.explanation, raw: raw))
        } else {
            verdicts.append(Verdict(
                pairId: pair.id, label: pair.label,
                predicted: "ERROR", confidence: 0, explanation: "", raw: raw))
        }
    }
    let resultsPath = probeOutDir + "/results.json"
    if let data = try? JSONEncoder().encode(verdicts) {
        try? data.write(to: URL(fileURLWithPath: resultsPath))
        log("  wrote \(resultsPath)")
    }

    // --- 4. Confusion + headline. The probe goes/no-goes on whether
    // the predicted verdict tracks the label cleanly.
    var confusion: [String: [String: Int]] = [
        "same_fact": ["same_fact": 0, "different_fact": 0, "ERROR": 0],
        "different_fact": ["same_fact": 0, "different_fact": 0, "ERROR": 0],
    ]
    for v in verdicts {
        var row = confusion[v.label] ?? [:]
        row[v.predicted, default: 0] += 1
        confusion[v.label] = row
    }
    let sfRow = confusion["same_fact"]!
    let dfRow = confusion["different_fact"]!
    let sfCorrect = sfRow["same_fact"]!
    let sfTotal = sameFactCount
    let dfCorrect = dfRow["different_fact"]!
    let dfTotal = differentFactCount
    let sfRate = sfTotal == 0 ? 0 : Double(sfCorrect) / Double(sfTotal)
    let dfRate = dfTotal == 0 ? 0 : Double(dfCorrect) / Double(dfTotal)

    var pr = "# ContinuityAuditSpike — same-fact probe (\(manuscript.id))\n\n"
    pr += "- **Manuscript**: \(manuscript.id) · \(manuscript.scenes.count) scenes · \(manuscript.gold_contradictions.count) gold contradictions\n"
    pr += "- **Extraction**: \(extractBackend == "kobold" ? koboldDesc : "\(extractModel) @ \(ollamaURL)") · runs=\(probeRuns)\n"
    pr += "- **Adjudication**: \(adjBackend == "kobold" ? koboldDesc : "\(adjModel) @ \(ollamaURL)")\n"
    pr += "- **Pairs**: \(pairs.count) (same_fact=\(sameFactCount), different_fact=\(differentFactCount))\n\n"
    pr += "## Confusion (rows = label, cols = predicted)\n\n"
    pr += "| label \\ pred | same_fact | different_fact | ERROR |\n|---|---|---|---|\n"
    pr += "| same_fact | \(sfRow["same_fact"]!) | \(sfRow["different_fact"]!) | \(sfRow["ERROR"]!) |\n"
    pr += "| different_fact | \(dfRow["same_fact"]!) | \(dfRow["different_fact"]!) | \(dfRow["ERROR"]!) |\n\n"
    pr += "## Headline\n\n"
    pr += "- **same_fact agreement**: \(sfCorrect)/\(sfTotal) = \(Int(sfRate * 100))%\n"
    pr += "- **different_fact agreement**: \(dfCorrect)/\(dfTotal) = \(Int(dfRate * 100))%\n"
    pr += "- **separation**: \(String(format: "%.2f", sfRate - dfRate)) (1.0 = perfect, 0.0 = no signal)\n\n"

    print(pr)
    let mdPath = probeOutDir + "/report.md"
    try? pr.write(toFile: mdPath, atomically: true, encoding: .utf8)
    log("  wrote \(mdPath)")
    exit(0)
}

// MARK: - Eval phase — multi-run eval harness (LOOM_CONTINUITY_AUDIT §21)

if phase == "eval" {
    let evalRuns = Int(env["LOOM_EVAL_RUNS"] ?? "") ?? 5
    let evalMode = env["LOOM_EVAL_MODE"] ?? "extract"
    let evalDir = env["LOOM_EVAL_FIXTURE_DIR"]
        ?? "Tests/LoomCoreTests/Fixtures/ContinuityAuditEval"
    let embedModel = env["LOOM_SPIKE_EMBED_MODEL"] ?? "bge-large:latest"

    let fm = FileManager.default
    guard let files = try? fm.contentsOfDirectory(atPath: evalDir) else {
        log("FATAL: cannot list eval fixture dir \(evalDir)"); exit(1)
    }
    var manuscripts: [(String, EvalManuscript)] = []
    for file in files.sorted() where file.hasSuffix(".json") {
        guard let data = fm.contents(atPath: evalDir + "/" + file),
              let m = try? JSONDecoder().decode(EvalManuscript.self, from: data) else {
            log("  skip \(file) — not a v2 eval manuscript"); continue
        }
        manuscripts.append((m.id, m))
    }
    guard !manuscripts.isEmpty else {
        log("FATAL: no eval manuscripts in \(evalDir)"); exit(1)
    }

    var er = "# ContinuityAuditSpike — eval harness\n\n"
    er += "- **Mode**: \(evalMode) · **Runs**: \(evalRuns)\n"
    er += "- **Manuscripts**: \(manuscripts.map { $0.0 }.joined(separator: ", "))\n"
    er += "- **Extraction**: \(extractBackend == "kobold" ? koboldDesc : "\(extractModel) @ \(ollamaURL)")\n\n"

    func fmtCI(_ a: ContinuityEvalMetrics.Aggregate) -> String {
        let half = (a.ci95High - a.ci95Low) / 2
        return String(format: "%.0f%% ±%.0f", a.mean * 100, half * 100)
    }
    func normKey(_ s: String) -> String { words(s).sorted().joined(separator: " ") }

    // --- extraction multi-run (synchronous) ---
    if evalMode == "extract" || evalMode == "both" {
        log("== EVAL: extraction (\(evalRuns) runs/scene) ==")
        er += "## Extraction recall — \(evalRuns) runs per scene\n\n"
        er += "| manuscript | content recall | typed recall | Chao1 completeness |\n|---|---|---|---|\n"
        var allContent: [Double] = [], allTyped: [Double] = []
        for (name, m) in manuscripts {
            var mContent: [Double] = [], mTyped: [Double] = [], mCov: [Double] = []
            for scene in m.scenes {
                let gold = m.gold_claims.filter { $0.scene == scene.id }.map(toGoldClaim)
                var perRunKeys: [[String]] = []
                for run in 0..<evalRuns {
                    log("  \(name)/\(scene.id) run \(run + 1)/\(evalRuns) …")
                    let claims = extractClaims(prose: scene.prose, sceneId: scene.id)
                    let score = ContinuityEvalMetrics.extractionRecall(gold: gold, extracted: claims)
                    mContent.append(score.recallContent)
                    mTyped.append(score.recallTyped)
                    perRunKeys.append(claims.map { normKey($0.value) })
                }
                mCov.append(ContinuityEvalMetrics.chao1(perRunItemKeys: perRunKeys).completeness)
            }
            let c = ContinuityEvalMetrics.aggregate(mContent)
            let t = ContinuityEvalMetrics.aggregate(mTyped)
            let cov = ContinuityEvalMetrics.aggregate(mCov)
            er += "| \(name) | \(fmtCI(c)) | \(fmtCI(t)) | \(String(format: "%.0f%%", cov.mean * 100)) |\n"
            allContent += mContent; allTyped += mTyped
        }
        er += "| **all** | **\(fmtCI(ContinuityEvalMetrics.aggregate(allContent)))**"
        er += " | **\(fmtCI(ContinuityEvalMetrics.aggregate(allTyped)))** | |\n\n"
    }

    // --- engine multi-run (async, chained — the engine marshals onto main) ---
    if evalMode == "engine" || evalMode == "both" {
        log("== EVAL: engine end-to-end (\(evalRuns) runs/manuscript) ==")
        var tasks: [(String, EvalManuscript, Int)] = []
        for (name, m) in manuscripts {
            for run in 0..<evalRuns { tasks.append((name, m, run)) }
        }
        var perRunFindings: [String: [[ContinuityFinding]]] = [:]
        // The engine uses `[weak self]` internally; if nothing holds a
        // strong reference past `runTask`'s synchronous return it
        // deallocates and the audit silently stalls (no completion ever
        // fires). Hold the live engine here for the audit's duration.
        var liveEngine: ContinuityAuditEngine?

        func renderEngine() -> String {
            var r = "## Engine end-to-end — \(evalRuns) runs per manuscript\n\n"
            r += "| manuscript | finding precision | recall | F1 |\n|---|---|---|---|\n"
            // (manuscript, goldContradiction, per-run detected?)
            var detections: [(String, ContinuityEvalMetrics.GoldContradiction, [Bool])] = []
            var allP: [Double] = [], allR: [Double] = [], allF: [Double] = []
            for (name, m) in manuscripts {
                let gold = m.gold_contradictions.compactMap(toGoldContradiction)
                let runs = perRunFindings[name] ?? []
                var ps: [Double] = [], rs: [Double] = [], fs: [Double] = []
                var perGold: [String: [Bool]] = [:]
                for findings in runs {
                    let score = ContinuityEvalMetrics.findingScore(gold: gold, findings: findings)
                    ps.append(score.precision); rs.append(score.recall); fs.append(score.f1)
                    let caught = Set(score.matchedGoldIds)
                    for g in gold { perGold[g.id, default: []].append(caught.contains(g.id)) }
                }
                for g in gold { detections.append((name, g, perGold[g.id] ?? [])) }
                let p = ContinuityEvalMetrics.aggregate(ps)
                let rr = ContinuityEvalMetrics.aggregate(rs)
                let f = ContinuityEvalMetrics.aggregate(fs)
                r += "| \(name) | \(fmtCI(p)) | \(fmtCI(rr)) | \(String(format: "%.2f", f.mean)) |\n"
                allP += ps; allR += rs; allF += fs
            }
            r += "| **all** | **\(fmtCI(ContinuityEvalMetrics.aggregate(allP)))**"
            r += " | **\(fmtCI(ContinuityEvalMetrics.aggregate(allR)))**"
            r += " | **\(String(format: "%.2f", ContinuityEvalMetrics.aggregate(allF).mean))** |\n\n"

            let atK = detections.filter { ContinuityEvalMetrics.passAtK($0.2) }.count
            let hatK = detections.filter { ContinuityEvalMetrics.passHatK($0.2) }.count
            r += "### Reliability — pass@k vs pass^k\n\n"
            r += "- **pass@k** (caught in ≥1 run): \(atK)/\(detections.count)\n"
            r += "- **pass^k** (caught in every run): \(hatK)/\(detections.count)\n"
            r += "- the gap of \(atK - hatK) is the stochasticity tax — contradictions a single audit will sometimes miss.\n\n"

            r += "### Detection rate by class\n\n| class | mean detection rate | pass^k |\n|---|---|---|\n"
            for kind in ContinuityFinding.Kind.allCases {
                let group = detections.filter { $0.1.kind == kind }
                guard !group.isEmpty else { continue }
                let rate = group.map { ContinuityEvalMetrics.detectionRate($0.2) }.reduce(0, +) / Double(group.count)
                let hk = group.filter { ContinuityEvalMetrics.passHatK($0.2) }.count
                r += "| \(kind.rawValue) | \(String(format: "%.0f%%", rate * 100)) | \(hk)/\(group.count) |\n"
            }
            r += "\n### Detection rate by scene distance\n\n| distance | mean detection rate | n |\n|---|---|---|\n"
            let buckets: [(String, (Int) -> Bool)] = [
                ("adjacent (1-2)", { $0 <= 2 }),
                ("mid (3-5)", { $0 >= 3 && $0 <= 5 }),
                ("far (6+)", { $0 >= 6 }),
            ]
            for (label, test) in buckets {
                let group = detections.filter { test($0.1.sceneDistance) }
                guard !group.isEmpty else { continue }
                let rate = group.map { ContinuityEvalMetrics.detectionRate($0.2) }.reduce(0, +) / Double(group.count)
                r += "| \(label) | \(String(format: "%.0f%%", rate * 100)) | \(group.count) |\n"
            }
            r += "\n### Per-contradiction detection\n\n| manuscript:id | kind | dist | detection rate |\n|---|---|---|---|\n"
            for (name, g, det) in detections {
                r += "| \(name):\(g.id) | \(g.kind.rawValue) | \(g.sceneDistance) | "
                r += "\(String(format: "%.0f%%", ContinuityEvalMetrics.detectionRate(det) * 100)) |\n"
            }
            return r
        }

        func runTask(_ i: Int) {
            if i >= tasks.count {
                er += renderEngine()
                print(er)
                exit(0)
            }
            let (name, m, run) = tasks[i]
            log("  engine: \(name) run \(run + 1)/\(evalRuns) …")
            let kobold = KoboldGenerateProvider(baseURL: URL(string: koboldURL)!)
            let engine = ContinuityAuditEngine(
                extractor: OllamaContinuityExtractor(provider: kobold),
                adjudicationProvider: kobold,
                entities: [],
                embedder: OllamaEmbedProvider(baseURL: URL(string: ollamaURL)!, model: embedModel))
            liveEngine = engine
            let sceneInputs = m.scenes.map {
                ContinuityAuditEngine.SceneInput(id: $0.id, prose: $0.prose)
            }
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("cas-eval-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            engine.audit(scenes: sceneInputs, projectURL: dir) { result in
                perRunFindings[name, default: []].append((try? result.get()) ?? [])
                runTask(i + 1)
            }
        }
        runTask(0)
        dispatchMain()
    }

    print(er)
    exit(0)
}

// MARK: - Engine phase — full end-to-end audit

// `ContinuityAuditEngine` marshals provider completions onto the main
// queue, so this branch services it with `dispatchMain()` (never
// returns; exits from the audit completion) rather than blocking the
// main thread on a semaphore.
if phase == "engine" {
    log("== ENGINE (end-to-end) ==")
    let kobold = KoboldGenerateProvider(baseURL: URL(string: koboldURL)!)
    let embedModel = env["LOOM_SPIKE_EMBED_MODEL"] ?? "bge-large:latest"
    let engineEmbedder = OllamaEmbedProvider(baseURL: URL(string: ollamaURL)!, model: embedModel)
    let engine = ContinuityAuditEngine(
        extractor: OllamaContinuityExtractor(provider: kobold),
        adjudicationProvider: kobold,
        entities: [],
        embedder: engineEmbedder
    )
    let sceneInputs = fixture.scenes.map {
        ContinuityAuditEngine.SceneInput(id: $0.id, prose: $0.prose)
    }
    let projectDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("cas-engine-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
    log("running full audit over \(sceneInputs.count) scenes (extraction + adjudication on Goetia) …")
    let started = Date()
    engine.audit(scenes: sceneInputs, projectURL: projectDir) { result in
        let elapsed = Date().timeIntervalSince(started)
        var r = "# ContinuityAuditSpike — engine (end-to-end)\n\n"
        r += "- **Extraction + adjudication**: Goetia (24B) @ \(koboldURL)\n"
        r += "- **Claim filter / knowledge similarity**: \(embedModel) @ \(ollamaURL)\n"
        r += "- **Scenes**: \(sceneInputs.count) · **Elapsed**: \(String(format: "%.0fs", elapsed))\n\n"
        switch result {
        case .failure(let e):
            r += "**Audit failed: \(e)**\n"
        case .success(let findings):
            r += "## \(findings.count) findings\n\n"
            let byKind = Dictionary(grouping: findings, by: { $0.kind.rawValue })
            for (kind, fs) in byKind.sorted(by: { $0.key < $1.key }) {
                r += "- **\(kind)**: \(fs.count)\n"
            }
            r += "\n"
            for f in findings {
                r += "### \(f.kind.rawValue) — \(f.severity.rawValue) (conf \(String(format: "%.2f", f.confidence)))\n"
                r += "- A (scene \(f.claimA.sourceSceneId)): \(f.claimA.value)\n"
                r += "- B (scene \(f.claimB.sourceSceneId)): \(f.claimB.value)\n"
                r += "- \(f.explanation)\n\n"
            }
        }
        print(r)
        exit(0)
    }
    dispatchMain()
}

// MARK: - Phase 1: extraction

if phase == "both" || phase == "extract" {
    log("== EXTRACTION ==")
    report += "## Extraction — recall of planted gold claims\n\n"
    report += "| scene | gold | extracted | matched | recall | content-recall |\n|---|---|---|---|---|---|\n"
    var totGold = 0, totMatched = 0, totContent = 0
    for scene in fixture.scenes {
        let gold = fixture.gold_claims.filter { $0.scene == scene.id }
        log("  scene \(scene.id) (\(scene.title)) …")
        let claims = extractClaims(prose: scene.prose, sceneId: scene.id)
        if env["LOOM_SPIKE_DUMP_CLAIMS"] != nil {
            for c in claims {
                log("    [\(c.type.rawValue)/\(c.source.rawValue)] \(c.subject) :: \(c.value)")
            }
        }
        var matched = 0, content = 0
        for g in gold {
            // typed match — same type AND value overlap
            if claims.contains(where: { $0.type.rawValue == g.type && jaccard($0.value, g.value) >= 0.34 }) {
                matched += 1
            }
            // content match — value overlap regardless of type (isolates
            // genuine extraction misses from type-classification disagreement)
            if claims.contains(where: { jaccard($0.value, g.value) >= 0.34 }) {
                content += 1
            }
        }
        totGold += gold.count; totMatched += matched; totContent += content
        let recall = gold.isEmpty ? 1 : Double(matched) / Double(gold.count)
        let cRecall = gold.isEmpty ? 1 : Double(content) / Double(gold.count)
        report += "| \(scene.id) \(scene.title) | \(gold.count) | \(claims.count) | \(matched) | \(Int(recall * 100))% | \(Int(cRecall * 100))% |\n"
    }
    let aggRecall = totGold == 0 ? 1 : Double(totMatched) / Double(totGold)
    let aggContent = totGold == 0 ? 1 : Double(totContent) / Double(totGold)
    report += "\n**Aggregate extraction recall: \(totMatched)/\(totGold) = \(Int(aggRecall * 100))% typed; "
    report += "\(totContent)/\(totGold) = \(Int(aggContent * 100))% content (type-agnostic)**\n\n"
}

// MARK: - Phase 2: adjudication

if phase == "both" || phase == "adjudicate" {
    log("== ADJUDICATION ==")
    report += "## Adjudication — pairwise verdict vs gold\n\n"
    report += "| pair | gold | predicted | conf | ok |\n|---|---|---|---|---|\n"

    let verdicts = ["contradiction", "consistent", "evolution"]
    var confusion: [String: [String: Int]] = [:]
    for g in verdicts { confusion[g] = ["contradiction": 0, "consistent": 0, "evolution": 0, "ERROR": 0] }
    var rows: [String] = []
    var falsePositives: [String] = []

    for pair in fixture.gold_pairs {
        log("  pair \(pair.id) …")
        let prompt = ContinuityAudit.buildAdjudicationPrompt(
            earlier: toClaim(pair.earlier), later: toClaim(pair.later))
        let raw = adjudicateRaw(prompt) ?? ""
        let adj = try? ContinuityAudit.parseAdjudication(raw)
        let pred = adj?.verdict.rawValue ?? "ERROR"
        let conf = adj.map { String(format: "%.2f", $0.confidence) } ?? "—"
        let ok = pred == pair.verdict
        confusion[pair.verdict]?[pred, default: 0] += 1
        rows.append("| \(pair.id) | \(pair.verdict) | \(pred) | \(conf) | \(ok ? "✓" : "✗") |")
        if pred == "contradiction" && pair.verdict != "contradiction" {
            falsePositives.append("\(pair.id) (gold \(pair.verdict)): \(pair.note)")
        }
    }
    report += rows.joined(separator: "\n") + "\n\n"

    // Confusion matrix
    report += "### Confusion (rows = gold, cols = predicted)\n\n"
    report += "| gold \\ pred | contradiction | consistent | evolution | ERROR |\n|---|---|---|---|---|\n"
    for g in verdicts {
        let c = confusion[g]!
        report += "| \(g) | \(c["contradiction"]!) | \(c["consistent"]!) | \(c["evolution"]!) | \(c["ERROR"]!) |\n"
    }
    report += "\n"

    // Headline metrics — contradiction class
    let tp = confusion["contradiction"]!["contradiction"]!
    let predContra = verdicts.reduce(0) { $0 + confusion[$1]!["contradiction"]! }
    let goldContra = fixture.gold_pairs.filter { $0.verdict == "contradiction" }.count
    let precision = predContra == 0 ? 1 : Double(tp) / Double(predContra)
    let recall = goldContra == 0 ? 1 : Double(tp) / Double(goldContra)
    let f1 = (precision + recall) == 0 ? 0 : 2 * precision * recall / (precision + recall)
    let correct = verdicts.reduce(0) { $0 + confusion[$1]![$1]! }
    let accuracy = Double(correct) / Double(fixture.gold_pairs.count)

    report += "### Headline — contradiction detection\n\n"
    report += "- **Precision**: \(tp)/\(predContra) = \(Int(precision * 100))%\n"
    report += "- **Recall**: \(tp)/\(goldContra) = \(Int(recall * 100))%\n"
    report += "- **F1**: \(String(format: "%.2f", f1))\n"
    report += "- **Overall verdict accuracy**: \(correct)/\(fixture.gold_pairs.count) = \(Int(accuracy * 100))%\n\n"
    if falsePositives.isEmpty {
        report += "No false positives — no non-contradiction pair was flagged.\n"
    } else {
        report += "**False positives (non-errors flagged as contradiction):**\n"
        for fp in falsePositives { report += "- \(fp)\n" }
    }
}

print(report)

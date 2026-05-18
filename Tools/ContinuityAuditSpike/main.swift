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
//   LOOM_SPIKE_PHASE        both | extract | adjudicate   (default both)
//   LOOM_SPIKE_ADJ_BACKEND  ollama | kobold               (default ollama)
//   LOOM_SPIKE_ADJ_MODEL    ollama adjudication model, default = extraction model
//   LOOM_SPIKE_KOBOLD_URL   default http://192.168.1.201:5001

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
        let body: [String: Any] = [
            "prompt": "[INST]\(prompt)[/INST]",
            "max_length": options.numPredict, "max_context_length": 8192,
            "temperature": 0.2, "top_p": 0.9, "min_p": 0.05, "rep_pen": 1.05,
            "stop_sequence": ["[INST]", "</s>"],
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
    let body: [String: Any] = [
        "prompt": "[INST]\(prompt)[/INST]",
        "max_length": 512, "max_context_length": 8192,
        "temperature": 0.2, "top_p": 0.9, "min_p": 0.05, "rep_pen": 1.05,
        "stop_sequence": ["[INST]", "</s>"],
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
report += "- **Extraction**: \(extractBackend == "kobold" ? "Goetia (24B) @ \(koboldURL)" : "\(extractModel) @ \(ollamaURL)")\n"
report += "- **Adjudication**: \(adjBackend == "kobold" ? "Goetia @ \(koboldURL)" : "\(adjModel) @ \(ollamaURL)")\n"
report += "- **Fixture**: \(fixture.scenes.count) scenes, \(fixture.gold_claims.count) gold claims, \(fixture.gold_pairs.count) gold pairs\n\n"

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

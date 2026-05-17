import Foundation
import LoomCore

// Relationship-discovery precision probe (HANDOFF §15.27). One-off
// runner: drives the two-stage pairwise relationship classifier
// against a live Ollama endpoint and measures whether the binary
// evidence gate (RelationshipDiscovery.buildRelationshipGatePrompt /
// parseGateResponse) cuts gemma's stable edge mis-classification.
//
// For every co-occurring character pair it runs:
//   - ungated: typed classification only (the current production path)
//   - gated:   the binary evidence gate first; typed classification
//              runs only for pairs the gate admits
// then reports both edge sets and which pairs the gate dropped.
//
// Run: `swift run RelationshipDiscoveryProbe`
//   LOOM_PROBE_OLLAMA_URL    default http://localhost:11434/
//   LOOM_PROBE_MODEL         default gemma4_2b:latest
//   LOOM_PROBE_CHARACTERS    comma-separated; default the test2 set
//   LOOM_PROBE_SCENE         fixture scene id; default t2-02

struct StderrStream: TextOutputStream {
    mutating func write(_ s: String) { FileHandle.standardError.write(Data(s.utf8)) }
}
var stderr = StderrStream()
func log(_ s: String) { print(s, to: &stderr) }

// MARK: - Config

let ollamaURLString = ProcessInfo.processInfo.environment["LOOM_PROBE_OLLAMA_URL"]
    ?? "http://localhost:11434/"
let model = ProcessInfo.processInfo.environment["LOOM_PROBE_MODEL"] ?? "gemma4_2b:latest"
let sceneId = ProcessInfo.processInfo.environment["LOOM_PROBE_SCENE"] ?? "t2-02"
let characterNames: [String] = {
    if let raw = ProcessInfo.processInfo.environment["LOOM_PROBE_CHARACTERS"] {
        return raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }
    return ["Abby", "Judy", "Allie", "Megan", "Lucas"]
}()

// MARK: - Fixture load

struct Fixture: Codable { let scenes: [FixtureScene] }
struct FixtureScene: Codable { let id: String; let title: String; let prose: String }

func loadScene() -> FixtureScene {
    let cwd = FileManager.default.currentDirectoryPath
    let url = URL(fileURLWithPath: cwd)
        .appendingPathComponent("Tools/EntityDiscoverySpike/test2-fixture.json")
    guard let data = try? Data(contentsOf: url),
          let fixture = try? JSONDecoder().decode(Fixture.self, from: data),
          let scene = fixture.scenes.first(where: { $0.id == sceneId }) else {
        log("ERROR: could not load scene \(sceneId) from test2-fixture.json")
        exit(1)
    }
    return scene
}

// MARK: - Ollama call (sync bridge)

let client = OllamaClient(baseURL: URL(string: ollamaURLString)!, model: model)
let callOptions = OllamaChatOptions(numPredict: 2048)

func callSync(prompt: String) -> String? {
    let sem = DispatchSemaphore(value: 0)
    var out: String?
    client.call(prompt: prompt, schema: [:], options: callOptions) { result in
        if case .success(let raw) = result { out = raw }
        sem.signal()
    }
    sem.wait()
    return out
}

/// Run a block over every pair in parallel, collecting results in
/// pair order.
func mapPairsParallel<T>(_ pairs: [[String]], _ body: @escaping ([String]) -> T) -> [T] {
    let group = DispatchGroup()
    let lock = NSLock()
    var byIndex: [Int: T] = [:]
    for (i, pair) in pairs.enumerated() {
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let r = body(pair)
            lock.lock(); byIndex[i] = r; lock.unlock()
            group.leave()
        }
    }
    group.wait()
    return (0..<pairs.count).map { byIndex[$0]! }
}

func edgeLine(_ r: RelationshipDiscovery.ProposedRelationship) -> String {
    "\(r.fromName) → \(r.toName)  [\(r.kind), \(r.status.rawValue)]"
}

// MARK: - Main

let scene = loadScene()
let prose = scene.prose
log("RelationshipDiscoveryProbe — evidence-gate eval")
log("  scene:      \(scene.id) — \(scene.title) (\(prose.split(separator: " ").count) words)")
log("  characters: \(characterNames.joined(separator: ", "))")
log("  model:      \(model) @ \(ollamaURLString)")

let pairs = RelationshipDiscovery.candidatePairs(
    characterNames: characterNames, scenePose: prose
)
log("  pairs:      \(pairs.count)\n")

// Ungated — typed classification for every pair (production path).
log("ungated: classifying \(pairs.count) pairs ...")
let ungatedStart = Date()
let ungatedByPair: [[RelationshipDiscovery.ProposedRelationship]] = mapPairsParallel(pairs) { pair in
    let prompt = RelationshipDiscovery.buildPairClassificationPrompt(
        characterA: pair[0], characterB: pair[1], scenePose: prose
    )
    guard let raw = callSync(prompt: prompt) else { return [] }
    return RelationshipDiscovery.parsePairClassification(
        raw, characterA: pair[0], characterB: pair[1]
    )
}
let ungatedEdges = RelationshipDiscovery.dedupRelationships(ungatedByPair.flatMap { $0 })
log("  → \(ungatedEdges.count) edges in \(String(format: "%.0fs", Date().timeIntervalSince(ungatedStart)))")

// Gated — binary evidence gate, then typed classification only for
// the pairs it admits.
log("gated: gating \(pairs.count) pairs ...")
let gatedStart = Date()
let gateEvidence: [String?] = mapPairsParallel(pairs) { pair in
    let prompt = RelationshipDiscovery.buildRelationshipGatePrompt(
        characterA: pair[0], characterB: pair[1], scenePose: prose
    )
    guard let raw = callSync(prompt: prompt) else { return nil }
    return RelationshipDiscovery.parseGateResponse(raw, scenePose: prose)
}
let admittedIdx = (0..<pairs.count).filter { gateEvidence[$0] != nil }
log("  gate admitted \(admittedIdx.count)/\(pairs.count) pairs; classifying ...")
let admittedPairs = admittedIdx.map { pairs[$0] }
let gatedClassified: [[RelationshipDiscovery.ProposedRelationship]] = mapPairsParallel(admittedPairs) { pair in
    let prompt = RelationshipDiscovery.buildPairClassificationPrompt(
        characterA: pair[0], characterB: pair[1], scenePose: prose
    )
    guard let raw = callSync(prompt: prompt) else { return [] }
    return RelationshipDiscovery.parsePairClassification(
        raw, characterA: pair[0], characterB: pair[1]
    )
}
let gatedEdges = RelationshipDiscovery.dedupRelationships(gatedClassified.flatMap { $0 })
log("  → \(gatedEdges.count) edges in \(String(format: "%.0fs", Date().timeIntervalSince(gatedStart)))")

// MARK: - Report

print("# RelationshipDiscoveryProbe — evidence-gate eval\n")
print("- **Scene**: \(scene.id) — \(scene.title)")
print("- **Characters**: \(characterNames.joined(separator: ", "))")
print("- **Model**: \(model)")
print("- **Pairs**: \(pairs.count)\n")

print("## Per-pair gate verdict\n")
print("| Pair | Gate | Evidence / reason |")
print("|---|---|---|")
for (i, pair) in pairs.enumerated() {
    let label = "\(pair[0]) ↔ \(pair[1])"
    if let ev = gateEvidence[i] {
        print("| \(label) | ADMIT | \(ev.prefix(90)) |")
    } else {
        print("| \(label) | DROP | no grounded evidence |")
    }
}
print("")

print("## Ungated edges (\(ungatedEdges.count)) — current production path\n")
if ungatedEdges.isEmpty { print("- _(none)_") }
for e in ungatedEdges.map(edgeLine).sorted() { print("- \(e)") }
print("")

print("## Gated edges (\(gatedEdges.count)) — evidence gate + typed classification\n")
if gatedEdges.isEmpty { print("- _(none)_") }
for e in gatedEdges.map(edgeLine).sorted() { print("- \(e)") }
print("")

let ungatedSet = Set(ungatedEdges.map { "\($0.fromName.lowercased())|\($0.toName.lowercased())|\($0.kind.lowercased())" })
let gatedSet = Set(gatedEdges.map { "\($0.fromName.lowercased())|\($0.toName.lowercased())|\($0.kind.lowercased())" })
print("## Read\n")
print("- Gate admitted \(admittedIdx.count) of \(pairs.count) pairs.")
print("- Ungated produced \(ungatedEdges.count) edges; gated produced \(gatedEdges.count).")
print("- Edges the gate removed: \(ungatedSet.subtracting(gatedSet).count); "
    + "edges only the gated path found: \(gatedSet.subtracting(ungatedSet).count).")

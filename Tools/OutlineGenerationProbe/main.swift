import Foundation
import LoomCore

// Planned Project mode — outline-generation probe (LOOM_PLANNED_PROJECT
// Phase 2). Runs the real OutlineGenerator against a live LLM and
// prints the resulting manuscript outline, for tuning the Stage 1
// (beats) and Stage 3 (scenes) prompts.
//
// Run: `swift run OutlineGenerationProbe`
//   LOOM_PROBE_BACKEND      kobold (default — the writer model) | ollama
//   LOOM_PROBE_KOBOLD_URL   default http://192.168.1.201:5001
//   LOOM_PROBE_OLLAMA_URL   default http://localhost:11434/
//   LOOM_PROBE_MODEL        label for the report (default depends on backend)
//   LOOM_PROBE_LENGTH       flashFiction|shortStory|novelette|novella|novel
//   LOOM_PROBE_PREMISE / LOOM_PROBE_SKETCH

struct StderrStream: TextOutputStream {
    mutating func write(_ s: String) { FileHandle.standardError.write(Data(s.utf8)) }
}
var stderr = StderrStream()
func log(_ s: String) { print(s, to: &stderr) }

/// Kobold-backed call provider — POSTs to KoboldCpp's `/api/v1/generate`
/// so the probe can drive the prose-tuned writer model (Goetia). The
/// prompt is wrapped in the Mistral instruct template; outline
/// generation is unconstrained, so `schema` is ignored.
final class KoboldOutlineProvider: OllamaCallProvider {
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
            "max_length": options.numPredict,
            "max_context_length": 8192,
            "temperature": 0.7,
            "top_p": 0.9,
            "min_p": 0.05,
            "rep_pen": 1.05,
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

let env = ProcessInfo.processInfo.environment
let backend = (env["LOOM_PROBE_BACKEND"] ?? "kobold").lowercased()
let premise = env["LOOM_PROBE_PREMISE"]
    ?? "A courier in a divided city smuggles a stolen memory she is forbidden to read — until the night she finally does."
let sketch = env["LOOM_PROBE_SKETCH"]
    ?? "Vesna, late thirties — a courier who has built her whole life on never reading what she carries."
let scenario = LengthScenario(rawValue: env["LOOM_PROBE_LENGTH"] ?? "novelette") ?? .novelette

let provider: OllamaCallProvider
let endpoint: String
let modelLabel: String
if backend == "ollama" {
    let url = env["LOOM_PROBE_OLLAMA_URL"] ?? "http://localhost:11434/"
    provider = OllamaClient(baseURL: URL(string: url)!, model: env["LOOM_PROBE_MODEL"] ?? "gemma4_2b:latest")
    endpoint = url
    modelLabel = env["LOOM_PROBE_MODEL"] ?? "gemma4_2b:latest"
} else {
    let url = env["LOOM_PROBE_KOBOLD_URL"] ?? "http://192.168.1.201:5001"
    provider = KoboldOutlineProvider(baseURL: URL(string: url)!)
    endpoint = url
    modelLabel = env["LOOM_PROBE_MODEL"] ?? "Goetia (writer model, KoboldCpp)"
}

let generator = OutlineGenerator(provider: provider)
let sizing = OutlineSizing.plan(for: scenario)

log("OutlineGenerationProbe")
log("  backend:  \(backend) @ \(endpoint)")
log("  model:    \(modelLabel)")
log("  scenario: \(scenario.displayName) — \(sizing.sceneCount) scenes, \(sizing.chapterCount) chapters")
log("running outline generation (1 + \(max(1, sizing.chapterCount)) LLM calls) ...")

let started = Date()
let sem = DispatchSemaphore(value: 0)
var captured: Result<OutlineGeneration.GeneratedOutline, Error>?
generator.generate(
    premise: premise,
    characterSketch: sketch,
    lengthScenario: scenario,
    framework: SaveTheCatFramework()
) { captured = $0; sem.signal() }
sem.wait()
let elapsed = Date().timeIntervalSince(started)

guard case .success(let outline)? = captured else {
    log("FAILED: \(String(describing: captured))")
    exit(1)
}
log("done in \(String(format: "%.0fs", elapsed)) — \(outline.scenes.count) scenes")

let sceneById = Dictionary(uniqueKeysWithValues: outline.scenes.map { ($0.id, $0) })

func printScene(_ id: UUID) {
    guard let scene = sceneById[id] else { return }
    let body = scene.summary.isEmpty ? "_(placeholder — Stage 3 under-delivered)_" : scene.summary
    print("- **\(scene.title)** — \(body)")
}

print("# OutlineGenerationProbe\n")
print("- **Model**: \(modelLabel)")
print("- **Scenario**: \(scenario.displayName) (\(sizing.sceneCount) scenes, \(sizing.chapterCount) chapters)")
print("- **Premise**: \(premise)")
print("- **Elapsed**: \(String(format: "%.0fs", elapsed))\n")

if outline.manuscript.parts.isEmpty {
    print("## Scenes (flat)\n")
    for id in outline.manuscript.orphanedSceneIds { printScene(id) }
} else {
    for part in outline.manuscript.parts {
        for chapter in part.chapters {
            print("## \(chapter.title)\n")
            for id in chapter.sceneIds { printScene(id) }
            print("")
        }
    }
}

let placeholders = outline.scenes.filter { $0.summary.isEmpty }.count
print("\n\(outline.scenes.count) scenes total; \(placeholders) placeholder (Stage 3 shortfall).")

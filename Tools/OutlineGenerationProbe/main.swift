import Foundation
import LoomCore

// Planned Project mode — outline-generation probe (LOOM_PLANNED_PROJECT
// Phase 2). Runs the real OutlineGenerator against a live Ollama
// endpoint and prints the resulting manuscript outline, so the Stage 1
// (beats) and Stage 3 (scenes) prompts can be tuned on the small model.
//
// Run: `swift run OutlineGenerationProbe`
//   LOOM_PROBE_OLLAMA_URL   default http://localhost:11434/
//   LOOM_PROBE_MODEL        default gemma4_2b:latest
//   LOOM_PROBE_LENGTH       flashFiction|shortStory|novelette|novella|novel
//   LOOM_PROBE_PREMISE      the plot premise
//   LOOM_PROBE_SKETCH       the character sketch

struct StderrStream: TextOutputStream {
    mutating func write(_ s: String) { FileHandle.standardError.write(Data(s.utf8)) }
}
var stderr = StderrStream()
func log(_ s: String) { print(s, to: &stderr) }

let env = ProcessInfo.processInfo.environment
let ollamaURL = env["LOOM_PROBE_OLLAMA_URL"] ?? "http://localhost:11434/"
let model = env["LOOM_PROBE_MODEL"] ?? "gemma4_2b:latest"
let premise = env["LOOM_PROBE_PREMISE"]
    ?? "A courier in a divided city smuggles a stolen memory she is forbidden to read — until the night she finally does."
let sketch = env["LOOM_PROBE_SKETCH"]
    ?? "Vesna, late thirties — a courier who has built her whole life on never reading what she carries."
let scenario = LengthScenario(rawValue: env["LOOM_PROBE_LENGTH"] ?? "novelette") ?? .novelette

let client = OllamaClient(baseURL: URL(string: ollamaURL)!, model: model)
let generator = OutlineGenerator(client: client)
let sizing = OutlineSizing.plan(for: scenario)

log("OutlineGenerationProbe")
log("  model:    \(model) @ \(ollamaURL)")
log("  scenario: \(scenario.displayName) — \(sizing.sceneCount) scenes, \(sizing.chapterCount) chapters")
log("  premise:  \(premise)")
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
print("- **Model**: \(model)")
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

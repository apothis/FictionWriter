import Foundation
import LoomCore

// Planned Project mode — outline-draft probe (LOOM_PLANNED_PROJECT
// Phase 5). Runs the real OutlineDraftCoordinator against the live
// writer model: one beat-planning pass over a scene summary, then one
// writer call per beat. Prints the drafted scene prose, for tuning
// the beat-plan + per-beat draft prompts.
//
// Run: `swift run OutlineDraftProbe`
//   LOOM_PROBE_KOBOLD_URL   default http://192.168.1.201:5001
//   LOOM_PROBE_SUMMARY      the outline scene summary to draft
//   LOOM_PROBE_TARGET       target word count (default 900)

struct StderrStream: TextOutputStream {
    mutating func write(_ s: String) { FileHandle.standardError.write(Data(s.utf8)) }
}
var stderr = StderrStream()
func log(_ s: String) { print(s, to: &stderr) }

/// Kobold-backed call provider — POSTs to KoboldCpp's `/api/v1/generate`
/// so the probe drives the prose-tuned writer model (Goetia), the
/// prompt wrapped in the Mistral instruct template.
final class KoboldDraftProvider: OllamaCallProvider {
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
let kbURL = env["LOOM_PROBE_KOBOLD_URL"] ?? "http://192.168.1.201:5001"
let summary = env["LOOM_PROBE_SUMMARY"]
    ?? "Vesna, holed up in her hideout, finally inserts the stolen memory chip and lives a stranger's life — a love story across the city's divide — as enforcers close in on the door."
let targetWords = Int(env["LOOM_PROBE_TARGET"] ?? "900") ?? 900

// An in-memory session with one outline scene to draft. A
// plannedConfig with assigned built-in styles so the draft is
// style-conditioned — the prompt's style block is exercised and the
// prose can be judged against the descriptors. The genre and register
// are selectable by name (LOOM_PROBE_GENRE / LOOM_PROBE_REGISTER) so a
// matrix of style pairs can be swept; an empty value drops that slot.
var project = Project(title: "DraftProbe")
let genreName = env["LOOM_PROBE_GENRE"] ?? "Noir"
let registerName = env["LOOM_PROBE_REGISTER"] ?? "Minimalist"
var assignedStyleIds: [UUID] = []
if !genreName.isEmpty {
    assignedStyleIds.append(StyleLibrary.stableStyleID(name: genreName, type: .genre))
}
if !registerName.isEmpty {
    assignedStyleIds.append(StyleLibrary.stableStyleID(name: registerName, type: .register))
}
project.plannedConfig = PlannedProjectConfig(
    premise: "A courier smuggles a stolen memory across a divided city.",
    characterSketch: "Vesna, a courier who never reads what she carries.",
    assignedStyleIds: assignedStyleIds
)
let session = ProjectSession(project: project)
let appliedStyles = StyleLibrary.resolve(
    project.plannedConfig!.assignedStyleIds, in: StyleLibraryStore().load()
)
let scene = session.addScene(title: "The Memory Unfolds")
session.setSceneSummary(id: scene.id, to: summary)
session.setSceneTargetWordCount(id: scene.id, to: targetWords)
session.setSceneStatus(id: scene.id, to: .todo)

let provider = KoboldDraftProvider(baseURL: URL(string: kbURL)!)
let coordinator = OutlineDraftCoordinator(session: session, provider: provider)
let beatCount = SceneBeatPlanning.beatCount(forTargetWords: targetWords)

log("OutlineDraftProbe")
log("  writer:   Goetia @ \(kbURL)")
log("  scene:    \(targetWords)w → \(beatCount) beats")
log("running outline draft (1 plan call + \(beatCount) beat calls) ...")

// `OutlineDraftCoordinator` marshals its provider completions onto
// the main queue, so this CLI tool must SERVICE the main queue —
// `dispatchMain()` does that and never returns. Blocking the main
// thread on a semaphore would deadlock (the coordinator's main-queue
// blocks could never run).
//
// The didFinish observer uses `queue: nil` deliberately: a non-nil
// `OperationQueue.main` delivers via the main RUN LOOP, which
// `dispatchMain()` does not run — only the main DISPATCH QUEUE. With
// `queue: nil` the block runs synchronously on the posting thread
// (the coordinator posts from its main-queue context), prints the
// report, and `exit()`s.
let started = Date()
NotificationCenter.default.addObserver(
    forName: OutlineDraftCoordinator.didFinishNotification,
    object: coordinator, queue: nil
) { _ in
    let elapsed = Date().timeIntervalSince(started)
    let drafted = session.scenes[scene.id]
    let prose = drafted?.prose ?? ""
    let status = drafted?.status ?? .todo
    let words = prose.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count

    print("# OutlineDraftProbe\n")
    print("- **Writer**: Goetia (KoboldCpp)")
    print("- **Scene summary**: \(summary)")
    print("- **Target / actual words**: \(targetWords) / \(words)")
    print("- **Beats**: \(beatCount)")
    print("- **Final status**: \(status.rawValue)")
    print("- **Elapsed**: \(String(format: "%.0fs", elapsed))\n")
    print("## Assigned styles\n")
    if appliedStyles.isEmpty {
        print("_(none resolved — style block was empty)_\n")
    } else {
        for st in appliedStyles {
            print("- **\(st.name)** (\(st.type.rawValue)) — \(st.descriptor)")
        }
        print("")
    }
    print("## Drafted prose\n")
    print(prose.isEmpty ? "_(empty — draft failed)_" : prose)
    exit(prose.isEmpty ? 1 : 0)
}
coordinator.start(sceneId: scene.id)
dispatchMain()

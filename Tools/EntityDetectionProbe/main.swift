import Foundation
import LoomCore

// GLiNER entity-detection probe. Loads a scene file, runs the GLiNER
// detector at a low threshold, and prints every candidate span with
// its sigmoid score and label — so a missed entity can be checked
// against the production 0.5 threshold.
//
// Run: `swift run EntityDetectionProbe <scene.md>`
//   LOOM_PROBE_THRESHOLD   default 0.01 (production is 0.5)

struct StderrStream: TextOutputStream {
    mutating func write(_ s: String) { FileHandle.standardError.write(Data(s.utf8)) }
}
var stderr = StderrStream()
func log(_ s: String) { print(s, to: &stderr) }

guard CommandLine.arguments.count > 1 else {
    log("usage: swift run EntityDetectionProbe <scene.md>")
    exit(2)
}
let scenePath = CommandLine.arguments[1]
let threshold = Double(ProcessInfo.processInfo.environment["LOOM_PROBE_THRESHOLD"] ?? "") ?? 0.01

guard let raw = try? String(contentsOfFile: scenePath, encoding: .utf8) else {
    log("ERROR: could not read \(scenePath)")
    exit(1)
}

// Strip a leading `--- ... ---` YAML frontmatter block, mirroring
// what the app feeds the detector (scene body only).
func stripFrontmatter(_ s: String) -> String {
    guard s.hasPrefix("---") else { return s }
    let lines = s.components(separatedBy: "\n")
    var idx = 1
    while idx < lines.count, lines[idx].trimmingCharacters(in: .whitespaces) != "---" {
        idx += 1
    }
    guard idx < lines.count else { return s }
    return lines[(idx + 1)...].joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
let prose = stripFrontmatter(raw)

// Load the GLiNER detector (async init bridged to sync).
let sem = DispatchSemaphore(value: 0)
final class Box: @unchecked Sendable { var detector: GLiNERDetector? }
let box = Box()
Task.detached {
    box.detector = try? await GLiNERDetector()
    sem.signal()
}
sem.wait()
guard let detector = box.detector else {
    log("ERROR: GLiNER detector failed to load — check the resource bundle")
    exit(3)
}

let labels = ["character", "place", "object"]
let entities: [GLiNEREntity]
do {
    entities = try detector.detect(text: prose, labels: labels, threshold: threshold)
} catch {
    log("ERROR: detection failed: \(error)")
    exit(4)
}

print("# EntityDetectionProbe — GLiNER\n")
print("- **Scene**: \(scenePath)")
print("- **Words**: \(prose.split(separator: " ").count)")
print("- **Probe threshold**: \(threshold)  (production keeps a span iff score > 0.5)\n")

print("| Span | Label | Score | Kept at 0.5? |")
print("|---|---|---|---|")
for e in entities.sorted(by: { $0.score > $1.score }) {
    let kept = e.score > 0.5 ? "✓" : "✗"
    let span = e.text.replacingOccurrences(of: "\n", with: " ")
    print("| \(span) | \(e.label) | \(String(format: "%.3f", e.score)) | \(kept) |")
}
print("")
let kept = entities.filter { $0.score > 0.5 }.count
print("\(entities.count) spans above \(threshold); \(kept) survive the production 0.5 threshold.")

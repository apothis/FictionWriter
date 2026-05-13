import Foundation
import LoomCore

// Phase 7.a.1 — Scene-Template Generation spike runner.
//
// Reads a fixture (or all of them), runs Pass A beat extraction against
// the local Ollama gemma4_2b extractor, emits a Markdown report to
// stdout AND to `Tools/SceneTemplateSpike/last-run/<fixture>.md` for
// hand-grading.
//
// Architecture pinned in LOOM_SCENE_TEMPLATE.md §7.1. Empirical results
// land in LOOM_SCENE_TEMPLATE_SPIKE.md (Phase 7.a.1 writeup).
//
// Usage:
//   swift run SceneTemplateSpike --extract Tools/SceneTemplateSpike/Fixtures/01_the_doorway_dialogue.md
//   swift run SceneTemplateSpike --extract-all
//
// Env:
//   LOOM_SPIKE_OLLAMA_URL   default http://localhost:11434/
//   LOOM_SPIKE_OLLAMA_MODEL default gemma4_2b:latest

// MARK: - Stderr helper

struct FileHandleOutputStream: TextOutputStream {
    let handle: FileHandle
    init(_ handle: FileHandle) { self.handle = handle }
    mutating func write(_ string: String) { handle.write(Data(string.utf8)) }
}
var stderrStream = FileHandleOutputStream(FileHandle.standardError)
func log(_ s: String) { print(s, to: &stderrStream) }

// MARK: - Config

let ollamaURLString = ProcessInfo.processInfo.environment["LOOM_SPIKE_OLLAMA_URL"]
    ?? "http://localhost:11434/"
let ollamaModel = ProcessInfo.processInfo.environment["LOOM_SPIKE_OLLAMA_MODEL"]
    ?? "gemma4_2b:latest"
let fixturesDir = "Tools/SceneTemplateSpike/Fixtures"
let outputDir = "Tools/SceneTemplateSpike/last-run"

// MARK: - Fixture loader

/// Strip the YAML frontmatter from a fixture .md file, return the
/// raw body + the parsed frontmatter dictionary. Simple parser — splits
/// on the second `---` line, parses `key: value` pairs. Sufficient for
/// the spike's fixed-shape frontmatter.
struct Fixture {
    let path: URL
    let frontmatter: [String: String]
    let body: String
}

func loadFixture(path: URL) throws -> Fixture {
    let text = try String(contentsOf: path, encoding: .utf8)
    guard text.hasPrefix("---\n") else {
        return Fixture(path: path, frontmatter: [:], body: text)
    }
    let afterFirst = text.dropFirst(4)
    guard let closeRange = afterFirst.range(of: "\n---\n") else {
        return Fixture(path: path, frontmatter: [:], body: text)
    }
    let fmBlock = String(afterFirst[..<closeRange.lowerBound])
    let body = String(afterFirst[closeRange.upperBound...])
    var fm: [String: String] = [:]
    for line in fmBlock.split(separator: "\n") {
        if let colon = line.firstIndex(of: ":") {
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let val = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            fm[key] = val
        }
    }
    return Fixture(path: path, frontmatter: fm, body: body.trimmingCharacters(in: .whitespacesAndNewlines))
}

// MARK: - Ollama call (synchronous wrapper)

func ollamaExtract(prompt: String, schema: [String: Any]) -> Result<String, Error> {
    guard let url = URL(string: "api/chat", relativeTo: URL(string: ollamaURLString))?.absoluteURL else {
        return .failure(NSError(domain: "Spike", code: -1, userInfo: [NSLocalizedDescriptionKey: "bad ollama URL"]))
    }
    let body: [String: Any] = [
        "model": ollamaModel,
        "messages": [["role": "user", "content": prompt]],
        "stream": false,
        "options": [
            // Low temperature — extraction wants deterministic JSON,
            // not creative variation. Matches LedgerSpike's tight-sampler
            // posture (Tools/LedgerSpike/main.swift §sampler-rationale).
            "temperature": 0.2,
            // Large numPredict because the schema is sizable
            // (8 beat fields × ~10 beats + pacingStats + character list)
            // — a tight budget here causes deterministic-empty completion
            // per the LOOM_LEDGER_SPIKE §11 finding.
            "num_predict": 4096,
            "repeat_penalty": 1.1,
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
    let session = URLSession(configuration: cfg)
    let sem = DispatchSemaphore(value: 0)
    var result: Result<String, Error> = .failure(NSError(domain: "Spike", code: -1))
    session.dataTask(with: req) { data, _, err in
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

// MARK: - Report rendering

struct ExtractionResult {
    let fixture: Fixture
    let rawResponse: String
    let elapsedSeconds: Double
    let parsed: ExtractedSceneSkeleton?
    let parseError: String?
    let groundTruthPacing: PacingStats
}

func renderReport(_ r: ExtractionResult) -> String {
    let fixtureID = r.fixture.frontmatter["fixture_id"] ?? r.fixture.path.lastPathComponent
    let title = r.fixture.frontmatter["title"] ?? "(untitled)"
    let intendedModality = r.fixture.frontmatter["modality_emphasis"] ?? "?"
    let intendedBeats = r.fixture.frontmatter["intended_beats"] ?? "?"

    var out = ""
    out += "# Pass-A extraction report — \(fixtureID)\n\n"
    out += "**Title:** \(title)\n\n"
    out += "**Authored modality emphasis:** \(intendedModality)\n\n"
    out += "**Authored beat count target:** \(intendedBeats)\n\n"
    out += "**Source word count:** \(r.fixture.body.split(whereSeparator: { $0.isWhitespace }).count)\n\n"
    out += "**Extractor:** `\(ollamaModel)` at `\(ollamaURLString)`\n\n"
    out += "**Latency:** \(String(format: "%.2fs", r.elapsedSeconds))\n\n"

    out += "## Ground-truth pacing (computed from source)\n\n"
    out += pacingStatsLines(r.groundTruthPacing)
    out += "\n"

    if let err = r.parseError {
        out += "## ⚠ PARSE FAILURE\n\n"
        out += "```\n\(err)\n```\n\n"
        out += "### Raw response\n\n```\n\(r.rawResponse)\n```\n"
        return out
    }
    guard let parsed = r.parsed else {
        out += "## ⚠ NO PARSED RESULT\n\n"
        return out
    }

    out += "## Extractor-reported pacing\n\n"
    out += pacingStatsLines(parsed.pacingStats)
    out += "\n"

    out += "**Pacing divergence (extractor vs. computed):**\n\n"
    let g = r.groundTruthPacing
    let e = parsed.pacingStats
    out += "- sentenceCount: \(g.sentenceCount) vs \(e.sentenceCount) (Δ \(e.sentenceCount - g.sentenceCount))\n"
    out += "- meanSentenceLengthWords: \(String(format: "%.2f", g.meanSentenceLengthWords)) vs \(String(format: "%.2f", e.meanSentenceLengthWords)) (Δ \(String(format: "%+.2f", e.meanSentenceLengthWords - g.meanSentenceLengthWords)))\n"
    out += "- dialogueRatio: \(String(format: "%.2f", g.dialogueRatio)) vs \(String(format: "%.2f", e.dialogueRatio)) (Δ \(String(format: "%+.2f", e.dialogueRatio - g.dialogueRatio)))\n\n"

    out += "## Source characters\n\n"
    out += parsed.sourceCharacters.isEmpty ? "_(none extracted)_\n\n" : "- " + parsed.sourceCharacters.joined(separator: "\n- ") + "\n\n"

    out += "## Source setting markers\n\n"
    out += parsed.sourceSettingMarkers.isEmpty ? "_(none extracted)_\n\n" : "- " + parsed.sourceSettingMarkers.joined(separator: "\n- ") + "\n\n"

    out += "## Extracted beats (\(parsed.beats.count))\n\n"
    if parsed.beats.isEmpty {
        out += "_(no beats extracted)_\n\n"
    } else {
        out += "| # | function | modality | target | tension | summary |\n"
        out += "|---|---|---|---|---|---|\n"
        for b in parsed.beats {
            out += "| \(b.index) | \(b.function.rawValue) | \(b.modality.rawValue) | \(b.targetWords)w | \(b.tensionDelta > 0 ? "+" : "")\(b.tensionDelta) | \(b.summary.replacingOccurrences(of: "|", with: "\\|")) |\n"
        }
        out += "\n"
        // Modality distribution.
        var modCounts: [String: Int] = [:]
        for b in parsed.beats { modCounts[b.modality.rawValue, default: 0] += 1 }
        out += "**Modality distribution:** "
        out += modCounts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        out += "\n\n"
        // Modality vs. authored intent.
        if let intended = NarrativeMode(rawValue: intendedModality) {
            let intendedCount = modCounts[intended.rawValue, default: 0]
            let ratio = Double(intendedCount) / Double(parsed.beats.count)
            out += "**Authored-emphasis match rate:** \(intendedCount)/\(parsed.beats.count) beats are `\(intended.rawValue)` (\(String(format: "%.0f%%", ratio * 100)))\n\n"
        }
        // STRAP stripping check.
        let summaryText = parsed.beats.map(\.summary).joined(separator: " ")
        var leakedNames: [String] = []
        for name in parsed.sourceCharacters {
            if summaryText.contains(name) { leakedNames.append(name) }
        }
        if leakedNames.isEmpty {
            out += "**Content-stripping (D4):** ✓ no source character names leaked into beat summaries\n\n"
        } else {
            out += "**Content-stripping (D4):** ⚠ leaked names in beat summaries: \(leakedNames.joined(separator: ", "))\n\n"
        }
    }

    out += "## Raw response\n\n<details><summary>JSON</summary>\n\n```json\n\(r.rawResponse)\n```\n\n</details>\n"
    return out
}

func pacingStatsLines(_ p: PacingStats) -> String {
    return """
    - sentenceCount: \(p.sentenceCount)
    - meanSentenceLengthWords: \(String(format: "%.2f", p.meanSentenceLengthWords))
    - sentenceLengthStdDev: \(String(format: "%.2f", p.sentenceLengthStdDev))
    - shortSentenceRatio: \(String(format: "%.2f", p.shortSentenceRatio))
    - longSentenceRatio: \(String(format: "%.2f", p.longSentenceRatio))
    - dialogueRatio: \(String(format: "%.2f", p.dialogueRatio))
    """
}

// MARK: - Extraction driver

func extract(fixturePath: URL) -> ExtractionResult {
    let fixture: Fixture
    do {
        fixture = try loadFixture(path: fixturePath)
    } catch {
        log("[load] failed: \(error)")
        return ExtractionResult(
            fixture: Fixture(path: fixturePath, frontmatter: [:], body: ""),
            rawResponse: "",
            elapsedSeconds: 0,
            parsed: nil,
            parseError: "fixture load failed: \(error)",
            groundTruthPacing: .zero
        )
    }
    let groundTruth = PacingStats.compute(text: fixture.body)
    let prompt = BeatExtraction.buildExtractionPrompt(sourceProse: fixture.body)
    let schema = BeatExtraction.jsonSchema()

    log("[\(fixture.path.lastPathComponent)] extracting (~\(fixture.body.split(whereSeparator: { $0.isWhitespace }).count)w)...")
    let start = Date()
    let raw: String
    switch ollamaExtract(prompt: prompt, schema: schema) {
    case .success(let s): raw = s
    case .failure(let e):
        return ExtractionResult(
            fixture: fixture,
            rawResponse: "",
            elapsedSeconds: Date().timeIntervalSince(start),
            parsed: nil,
            parseError: "ollama: \(e)",
            groundTruthPacing: groundTruth
        )
    }
    let elapsed = Date().timeIntervalSince(start)
    log("[\(fixture.path.lastPathComponent)] response in \(String(format: "%.2fs", elapsed))")
    do {
        let parsed = try BeatExtraction.parseExtractedSkeleton(raw)
        log("[\(fixture.path.lastPathComponent)] parsed \(parsed.beats.count) beats")
        return ExtractionResult(
            fixture: fixture,
            rawResponse: raw,
            elapsedSeconds: elapsed,
            parsed: parsed,
            parseError: nil,
            groundTruthPacing: groundTruth
        )
    } catch {
        return ExtractionResult(
            fixture: fixture,
            rawResponse: raw,
            elapsedSeconds: elapsed,
            parsed: nil,
            parseError: "parse: \(error)",
            groundTruthPacing: groundTruth
        )
    }
}

func writeReport(_ result: ExtractionResult) {
    let report = renderReport(result)
    let outName = result.fixture.path.deletingPathExtension().lastPathComponent + ".md"
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let outPath = cwd.appendingPathComponent(outputDir).appendingPathComponent(outName)
    try? FileManager.default.createDirectory(at: outPath.deletingLastPathComponent(), withIntermediateDirectories: true)
    do {
        try report.write(to: outPath, atomically: true, encoding: .utf8)
        log("[\(result.fixture.path.lastPathComponent)] wrote \(outPath.path)")
    } catch {
        log("[\(result.fixture.path.lastPathComponent)] failed to write report: \(error)")
    }
    // Also stream to stdout for live-runner viewing.
    print(report)
    print("\n---\n")
}

// MARK: - Main

let args = CommandLine.arguments

if args.count < 2 {
    log("Usage:")
    log("  swift run SceneTemplateSpike --extract <path/to/fixture.md>")
    log("  swift run SceneTemplateSpike --extract-all")
    exit(1)
}

let cmd = args[1]
let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

switch cmd {
case "--extract":
    guard args.count >= 3 else {
        log("--extract requires a path argument")
        exit(1)
    }
    let path = URL(fileURLWithPath: args[2], relativeTo: cwd)
    let result = extract(fixturePath: path)
    writeReport(result)
case "--extract-all":
    let fixturesURL = cwd.appendingPathComponent(fixturesDir)
    guard let entries = try? FileManager.default.contentsOfDirectory(at: fixturesURL, includingPropertiesForKeys: nil) else {
        log("can't read \(fixturesURL.path)")
        exit(1)
    }
    let mdFiles = entries.filter { $0.pathExtension == "md" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    log("running \(mdFiles.count) fixtures...")
    for f in mdFiles {
        let result = extract(fixturePath: f)
        writeReport(result)
    }
    log("done.")
default:
    log("Unknown command: \(cmd)")
    exit(1)
}

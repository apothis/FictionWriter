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
let koboldURLString = ProcessInfo.processInfo.environment["LOOM_SPIKE_BASE_URL"]
    ?? "http://192.168.1.201:5001/"
let fixturesDir = "Tools/SceneTemplateSpike/Fixtures"
let outputDir = "Tools/SceneTemplateSpike/last-run"

// MARK: - Cast mappings for §7.a.2 generation runs.
//
// One per fixture for which we run Pass B in this spike. Each mapping
// is free-form v1 (per planning-doc D7). The mappings are deliberately
// chosen to be *distant* from the source's content domain so plot
// leakage is easy to spot — if Maya somehow ends up in a doorway
// holding a bag of letters, we know D4 failed.

let castMappings: [String: String] = [
    "01_the_doorway_dialogue.md": """
        New cast and setting:
        - PROTAGONIST: Yusuf, 38, a former software engineer.
        - ANTAGONIST: Inez, 41, his ex-business-partner, now CEO of the company they founded.
        - Setting: the lobby of a glass-walled tech office at 9pm on a Friday. Security has gone home. Inez is on her way out.
        - Yusuf is carrying a USB drive instead of a bag of letters. The USB drive contains six years of source-code commits with his name on them that the company is now denying he wrote.
        - The scene is the moment he confronts her about the erasure.
        """,
    "03_the_cathedral_description.md": """
        New cast and setting:
        - PROTAGONIST: Tomas, 29, a graduate student studying maritime archaeology.
        - Setting: an abandoned shipyard at low tide. A decommissioned freighter the size of a city block sits on its side in the mud, the hull rust-streaked, the deck tilted thirty degrees. Tomas is walking around the seaward side toward an open hatch he's been told about.
        - No second character in this scene.
        - The "door" at the end of the scene is the hatch he reaches.
        """,
    "04_burn_the_tape_action.md": """
        New cast and setting:
        - PROTAGONIST: Anya, 33, a network engineer.
        - ALLY_1: Anya's older sister Petra, 39, an investigative reporter.
        - Setting: a colocation data centre that is rapidly flooding from a burst sprinkler main. Anya has come in to recover a single encrypted hard drive that holds evidence linking a senator to a financial fraud. Petra was supposed to wait in the car.
        - The "tape" object maps to the hard drive. The "fire" maps to the flood. The "Bible" maps to a server rack in row 7.
        """,
]

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

// MARK: - Kobold writer call (synchronous wrapper)

/// Fire a single non-streaming completion against the writer server.
/// Returns the raw response text or an error.
func koboldGenerate(prompt: String, maxLength: Int) -> Result<String, Error> {
    guard let url = URL(string: "api/v1/generate", relativeTo: URL(string: koboldURLString))?.absoluteURL else {
        return .failure(NSError(domain: "Spike", code: -1, userInfo: [NSLocalizedDescriptionKey: "bad kobold URL"]))
    }
    // Sampler — matches Loom's GenerationDefaults.phase1Defaults shape
    // (creative-writing-tuned: temp 1.0, top-p 0.95, min-p 0.05, DRY 0.8).
    let body: [String: Any] = [
        "prompt": prompt,
        "max_length": maxLength,
        "max_context_length": 16384,
        "temperature": 1.0,
        "top_p": 0.95,
        "top_k": 0,
        "min_p": 0.05,
        "rep_pen": 1.07,
        "rep_pen_range": 1024,
        "sampler_order": [6, 0, 1, 3, 4, 2, 5],
        "dry_multiplier": 0.8,
        "dry_base": 1.75,
        "dry_allowed_length": 2,
        // Stop sequences — common end-of-beat markers. The model
        // typically pauses at a natural sentence boundary near the
        // target length, but the stops below prevent it from
        // continuing into a second beat or echoing prompt sections.
        "stop_sequence": ["[BEAT", "===", "[INSTRUCTION", "[SYSTEM"],
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
            if let results = obj?["results"] as? [[String: Any]],
               let text = results.first?["text"] as? String {
                result = .success(text)
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

// MARK: - Per-beat generation driver

struct BeatGenerationOutput {
    let beatIndex: Int
    let prompt: String
    let prose: String
    let elapsedSeconds: Double
    let actualWords: Int
    let targetWords: Int
    let error: String?
}

struct GenerationRun {
    let fixture: Fixture
    let skeleton: ExtractedSceneSkeleton
    let castMapping: String
    let groundTruthPacing: PacingStats
    let beatOutputs: [BeatGenerationOutput]
    let totalElapsedSeconds: Double
}

/// Run Pass B end-to-end for one fixture: parse the prior `--extract`
/// output back into a skeleton, then loop per-beat through the writer
/// with the cast mapping. Returns the full run for hand-grading.
func runPassB(
    fixture: Fixture,
    extracted: ExtractedSceneSkeleton,
    castMapping: String
) -> GenerationRun {
    let groundTruthPacing = PacingStats.compute(text: fixture.body)
    var outputs: [BeatGenerationOutput] = []
    var rollingProse = ""
    let totalStart = Date()
    for (idx, _) in extracted.beats.enumerated() {
        let beat = extracted.beats[idx]
        let prompt = BeatGeneration.buildBeatPrompt(
            templateBody: fixture.body,
            skeleton: extracted,
            castMapping: castMapping,
            currentBeatIndex: idx,
            priorBeatsProse: rollingProse,
            groundTruthPacing: groundTruthPacing
        )
        // Give the model ~2x the target word count of headroom (one
        // word ≈ 1.4 tokens, plus the prompt itself ends with the
        // beat's prefix, so the response is just the body).
        let maxLength = max(64, beat.targetWords * 2)
        log("[\(fixture.path.lastPathComponent)] beat \(idx)/\(extracted.beats.count - 1) (\(beat.modality.rawValue), \(beat.function.rawValue), target \(beat.targetWords)w)...")
        let start = Date()
        let result = koboldGenerate(prompt: prompt, maxLength: maxLength)
        let elapsed = Date().timeIntervalSince(start)
        switch result {
        case .success(let raw):
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let words = trimmed.split(whereSeparator: { $0.isWhitespace }).count
            log("  → \(words)w (target \(beat.targetWords)) in \(String(format: "%.1fs", elapsed))")
            outputs.append(BeatGenerationOutput(
                beatIndex: idx, prompt: prompt, prose: trimmed,
                elapsedSeconds: elapsed, actualWords: words,
                targetWords: beat.targetWords, error: nil
            ))
            // Append to rolling buffer for next-beat context.
            if rollingProse.isEmpty {
                rollingProse = trimmed
            } else {
                rollingProse += "\n\n" + trimmed
            }
        case .failure(let err):
            log("  → ERROR \(err.localizedDescription)")
            outputs.append(BeatGenerationOutput(
                beatIndex: idx, prompt: prompt, prose: "",
                elapsedSeconds: elapsed, actualWords: 0,
                targetWords: beat.targetWords,
                error: err.localizedDescription
            ))
        }
    }
    return GenerationRun(
        fixture: fixture,
        skeleton: extracted,
        castMapping: castMapping,
        groundTruthPacing: groundTruthPacing,
        beatOutputs: outputs,
        totalElapsedSeconds: Date().timeIntervalSince(totalStart)
    )
}

func renderGenerationReport(_ run: GenerationRun) -> String {
    let fixtureID = run.fixture.frontmatter["fixture_id"] ?? run.fixture.path.lastPathComponent
    let title = run.fixture.frontmatter["title"] ?? "(untitled)"
    var out = ""
    out += "# Pass-B generation report — \(fixtureID)\n\n"
    out += "**Title:** \(title)\n\n"
    out += "**Cast mapping:**\n\n```\n\(run.castMapping)\n```\n\n"
    out += "**Writer:** Kobold at `\(koboldURLString)` (gemma-4-31B uncensored)\n\n"
    out += "**Total elapsed:** \(String(format: "%.1fs", run.totalElapsedSeconds))\n\n"

    out += "## Per-beat outputs\n\n"

    let totalWords = run.beatOutputs.reduce(0) { $0 + $1.actualWords }
    let totalTargetWords = run.beatOutputs.reduce(0) { $0 + $1.targetWords }
    out += "**Aggregate word count:** \(totalWords) (target \(totalTargetWords); Δ \(totalWords - totalTargetWords))\n\n"

    for o in run.beatOutputs {
        let beat = run.skeleton.beats[o.beatIndex]
        let withinBudget = abs(o.actualWords - o.targetWords) <= max(20, o.targetWords / 5)
        let budgetMark = withinBudget ? "✓" : "⚠"
        out += "### Beat \(o.beatIndex): \(beat.function.rawValue) / \(beat.modality.rawValue) — \(o.actualWords)w / target \(o.targetWords)w \(budgetMark) (\(String(format: "%.1fs", o.elapsedSeconds)))\n\n"
        out += "_Skeleton summary:_ \(beat.summary)\n\n"
        if let err = o.error {
            out += "**⚠ Error:** \(err)\n\n"
        } else {
            out += "```\n\(o.prose)\n```\n\n"
        }
    }

    // Plot-leakage check: any source character name reappear in the
    // generated prose?
    out += "## Plot-leakage check\n\n"
    let allProse = run.beatOutputs.map(\.prose).joined(separator: "\n")
    var leaks: [(String, Int)] = []
    for name in run.skeleton.sourceCharacters {
        let count = allProse.components(separatedBy: name).count - 1
        if count > 0 { leaks.append((name, count)) }
    }
    if leaks.isEmpty {
        out += "✓ No source character names appear in the generated prose.\n\n"
    } else {
        out += "⚠ Source names leaked:\n\n"
        for (n, c) in leaks { out += "- `\(n)` × \(c)\n" }
        out += "\n"
    }
    var settingLeaks: [(String, Int)] = []
    for marker in run.skeleton.sourceSettingMarkers {
        let count = allProse.lowercased().components(separatedBy: marker.lowercased()).count - 1
        if count > 0 { settingLeaks.append((marker, count)) }
    }
    if settingLeaks.isEmpty {
        out += "✓ No source setting markers appear in the generated prose.\n\n"
    } else {
        out += "⚠ Source setting markers appearing in generated prose (may or may not be coincidental — needs hand-eye):\n\n"
        for (n, c) in settingLeaks { out += "- `\(n)` × \(c)\n" }
        out += "\n"
    }

    // Modality verification — heuristic (full NarrativeMode result)
    // per beat. For Phase 7.b production this is composed with the
    // LLM classifier (Kobold side-call); for the spike report we
    // use heuristic only — the LLM check would double the cost.
    out += "## Modality post-hoc check (heuristic)\n\n"
    out += "_Note: heuristic accuracy is ~56% per LOOM_NARRATIVE_MODE_SPIKE §10; treat mismatches as suggestive, not authoritative._\n\n"
    var heuristicMatches = 0
    out += "| beat | target | heuristic | matches |\n"
    out += "|---|---|---|---|\n"
    for o in run.beatOutputs {
        let target = run.skeleton.beats[o.beatIndex].modality
        let heuristic = NarrativeModeHeuristic.classify(o.prose)
        let isMatch = heuristic == target
        if isMatch { heuristicMatches += 1 }
        let marker = isMatch ? "✓" : "—"
        out += "| \(o.beatIndex) | \(target.rawValue) | \(heuristic.rawValue) | \(marker) |\n"
    }
    out += "\n**Heuristic-modality match:** \(heuristicMatches)/\(run.beatOutputs.count) beats\n\n"

    // Aggregate budget compliance
    let withinBudgetCount = run.beatOutputs.filter { o in
        let target = o.targetWords
        return abs(o.actualWords - target) <= max(20, target / 5)
    }.count
    out += "**Beat word-count compliance:** \(withinBudgetCount)/\(run.beatOutputs.count) beats within ±20% of target\n\n"

    out += "## Combined output (read as a scene)\n\n"
    out += "<details><summary>Full assembled scene</summary>\n\n"
    out += run.beatOutputs.map(\.prose).joined(separator: "\n\n")
    out += "\n\n</details>\n"

    return out
}

func writeGenerationReport(_ run: GenerationRun) {
    let report = renderGenerationReport(run)
    let outName = run.fixture.path.deletingPathExtension().lastPathComponent + ".generated.md"
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let outPath = cwd.appendingPathComponent(outputDir).appendingPathComponent(outName)
    try? FileManager.default.createDirectory(at: outPath.deletingLastPathComponent(), withIntermediateDirectories: true)
    do {
        try report.write(to: outPath, atomically: true, encoding: .utf8)
        log("[\(run.fixture.path.lastPathComponent)] wrote \(outPath.path)")
    } catch {
        log("[\(run.fixture.path.lastPathComponent)] failed to write report: \(error)")
    }
    print(report)
    print("\n---\n")
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
    log("  swift run SceneTemplateSpike --generate <fixture-basename>      (runs Pass A then Pass B with hardcoded cast mapping)")
    log("  swift run SceneTemplateSpike --generate-all                     (runs all fixtures in castMappings)")
    exit(1)
}

/// Run Pass A then Pass B end-to-end for one fixture. Reuses the
/// extraction logic; if the cast mapping for the fixture isn't
/// registered, errors out (the spike has 3 hardcoded mappings).
func runFullPipeline(fixtureFilename: String) {
    guard let mapping = castMappings[fixtureFilename] else {
        log("[\(fixtureFilename)] no cast mapping registered; skipping. Edit Tools/SceneTemplateSpike/main.swift `castMappings`.")
        return
    }
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let fixturePath = cwd
        .appendingPathComponent(fixturesDir)
        .appendingPathComponent(fixtureFilename)
    let extraction = extract(fixturePath: fixturePath)
    writeReport(extraction)
    guard let skeleton = extraction.parsed else {
        log("[\(fixtureFilename)] extraction failed; skipping Pass B.")
        return
    }
    log("[\(fixtureFilename)] Pass B begins (\(skeleton.beats.count) beats)...")
    let run = runPassB(fixture: extraction.fixture, extracted: skeleton, castMapping: mapping)
    writeGenerationReport(run)
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
case "--generate":
    guard args.count >= 3 else {
        log("--generate requires a fixture basename (e.g. 01_the_doorway_dialogue.md)")
        exit(1)
    }
    runFullPipeline(fixtureFilename: args[2])
case "--generate-all":
    let keys = castMappings.keys.sorted()
    log("running \(keys.count) full pipelines: \(keys.joined(separator: ", "))")
    for k in keys { runFullPipeline(fixtureFilename: k) }
    log("done.")
default:
    log("Unknown command: \(cmd)")
    exit(1)
}

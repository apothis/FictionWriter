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

// MARK: - (Pass A) Ollama call — production wrapper used directly

// Phase 7.b.3 refactor: the spike runner used to hand-roll the
// `/api/chat` request here. That code moved into the production
// `OllamaBeatExtractor` (which inherits the retry-on-empty +
// scaled-budget pattern from `OllamaLedgerExtractor`). The spike
// runner now wraps `OllamaBeatExtractor` in a semaphore — see
// `extract(fixturePath:)`.

// MARK: - Kobold writer call (synchronous wrapper)

/// Fire a single non-streaming completion against the writer server.
/// Returns the raw response text or an error.
func koboldGenerate(prompt: String, maxLength: Int) -> Result<String, Error> {
    guard let url = URL(string: "api/v1/generate", relativeTo: URL(string: koboldURLString))?.absoluteURL else {
        return .failure(NSError(domain: "Spike", code: -1, userInfo: [NSLocalizedDescriptionKey: "bad kobold URL"]))
    }
    // Instruct-wrap the prompt (mirrors production GenerationCoordinator).
    // BeatGeneration.buildBeatPrompt returns a template-agnostic body;
    // a Mistral writer (Goetia) emits EOS immediately on a raw,
    // unwrapped prompt — so Pass-B comes back empty without this.
    let adapter = InstructTemplates.adapter(for: .mistralV7)
    let prompt = adapter.wrap(system: "", userBody: prompt, prefill: "")
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
        "stop_sequence": ["[BEAT", "===", "[INSTRUCTION", "[SYSTEM"] + adapter.stopSequences,
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
/// `includeTemplateBody=false` activates §7.a.3 ablation arm B
/// (skeleton-only generation, no template prose injected).
func runPassB(
    fixture: Fixture,
    extracted: ExtractedSceneSkeleton,
    castMapping: String,
    includeTemplateBody: Bool = true,
    includeVoiceDescriptor: Bool = true
) -> GenerationRun {
    // Phase 7.b followup ablation seam: when includeVoiceDescriptor
    // is false, strip the descriptor from the skeleton before
    // building per-beat prompts. Lets the runner A/B the voice
    // injection without changing the upstream extractor output.
    var extracted = extracted
    if !includeVoiceDescriptor {
        extracted.voiceDescriptor = nil
    }
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
            groundTruthPacing: groundTruthPacing,
            includeTemplateBody: includeTemplateBody
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
            // Strip per-beat meta-commentary ([Length:...]/[Pacing
            // check]/etc.) exactly as production does
            // (TemplateGenerationCoordinator → BeatOutputSanitizer.strip),
            // so the spike's assembled scene matches the app's output.
            let trimmed = BeatOutputSanitizer.strip(raw.trimmingCharacters(in: .whitespacesAndNewlines))
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
    out += "**Writer:** Kobold at `\(koboldURLString)`\n\n"
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

    // Phase 7.b prompt-revision item 4: pacingStats dropped from
    // the extractor schema (§7.a.1 finding). Computed pacing only.
    _ = r.groundTruthPacing  // already rendered above as ground-truth

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
            out += "| \(b.index) | \(b.function.rawValue) | \(b.modality.rawValue) | \(b.targetWords)w | \(b.beatTensionChange > 0 ? "+" : "")\(b.beatTensionChange) | \(b.summary.replacingOccurrences(of: "|", with: "\\|")) |\n"
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

    log("[\(fixture.path.lastPathComponent)] extracting (~\(fixture.body.split(whereSeparator: { $0.isWhitespace }).count)w)...")
    let start = Date()

    // Phase 7.b.3 refactor: go through the production extractor
    // (OllamaBeatExtractor) instead of the hand-rolled HTTP path.
    // Wrap the async API in a semaphore for the CLI runner.
    guard let baseURL = URL(string: ollamaURLString) else {
        return ExtractionResult(
            fixture: fixture, rawResponse: "", elapsedSeconds: 0,
            parsed: nil, parseError: "bad ollama URL",
            groundTruthPacing: groundTruth
        )
    }
    let client = OllamaClient(baseURL: baseURL, model: ollamaModel)
    let extractor = OllamaBeatExtractor(client: client)
    let sem = DispatchSemaphore(value: 0)
    var skeletonResult: Result<ExtractedSceneSkeleton, Error>? = nil
    extractor.extractSkeleton(from: fixture.body) { result in
        skeletonResult = result
        sem.signal()
    }
    sem.wait()
    let elapsed = Date().timeIntervalSince(start)
    log("[\(fixture.path.lastPathComponent)] response in \(String(format: "%.2fs", elapsed))")
    guard let skeletonResult = skeletonResult else {
        return ExtractionResult(
            fixture: fixture, rawResponse: "", elapsedSeconds: elapsed,
            parsed: nil, parseError: "no result",
            groundTruthPacing: groundTruth
        )
    }
    do {
        let parsed = try skeletonResult.get()
        // Re-encode the parsed skeleton as the "raw response" surface
        // for the report renderer. OllamaBeatExtractor doesn't expose
        // the raw text from Ollama (it parses internally); the
        // canonical view is the round-tripped JSON.
        let rawJSON = (try? String(data: JSONEncoder.loomPretty.encode(parsed), encoding: .utf8)) ?? "{}"
        log("[\(fixture.path.lastPathComponent)] parsed \(parsed.beats.count) beats")
        return ExtractionResult(
            fixture: fixture,
            rawResponse: rawJSON,
            elapsedSeconds: elapsed,
            parsed: parsed,
            parseError: nil,
            groundTruthPacing: groundTruth
        )
    } catch {
        return ExtractionResult(
            fixture: fixture,
            rawResponse: "",
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

/// Phase 7.b followup ablation: run Pass A once, then Pass B TWICE
/// — once with the voice descriptor injected (Arm A, new default),
/// once with the descriptor stripped (Arm B, §7.a.3 baseline).
/// Both arms include the template body (§7.a.3 already established
/// that template inclusion is good).
func runVoiceAblation(fixtureFilename: String) {
    guard let mapping = castMappings[fixtureFilename] else {
        log("[\(fixtureFilename)] no cast mapping registered; skipping.")
        return
    }
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let fixturePath = cwd
        .appendingPathComponent(fixturesDir)
        .appendingPathComponent(fixtureFilename)
    let extraction = extract(fixturePath: fixturePath)
    writeReport(extraction)
    guard let skeleton = extraction.parsed else {
        log("[\(fixtureFilename)] extraction failed; skipping voice ablation.")
        return
    }
    guard skeleton.voiceDescriptor != nil else {
        log("[\(fixtureFilename)] no voiceDescriptor in skeleton; nothing to ablate. (Did Pass A emit it?)")
        return
    }
    log("[\(fixtureFilename)] ARM A — with voice descriptor (\(skeleton.beats.count) beats)...")
    let armA = runPassB(
        fixture: extraction.fixture, extracted: skeleton,
        castMapping: mapping,
        includeTemplateBody: true,
        includeVoiceDescriptor: true
    )
    log("[\(fixtureFilename)] ARM B — without voice descriptor (\(skeleton.beats.count) beats)...")
    let armB = runPassB(
        fixture: extraction.fixture, extracted: skeleton,
        castMapping: mapping,
        includeTemplateBody: true,
        includeVoiceDescriptor: false
    )
    writeAblationReport(armA: armA, armB: armB)
}

/// Phase 7.a.3 ablation: run Pass A once, then Pass B TWICE — once
/// with the template body included (Arm A) and once skeleton-only
/// (Arm B). Render a side-by-side comparison report.
func runAblation(fixtureFilename: String) {
    guard let mapping = castMappings[fixtureFilename] else {
        log("[\(fixtureFilename)] no cast mapping registered; skipping.")
        return
    }
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let fixturePath = cwd
        .appendingPathComponent(fixturesDir)
        .appendingPathComponent(fixtureFilename)
    let extraction = extract(fixturePath: fixturePath)
    writeReport(extraction)
    guard let skeleton = extraction.parsed else {
        log("[\(fixtureFilename)] extraction failed; skipping ablation.")
        return
    }
    log("[\(fixtureFilename)] ARM A — template included (\(skeleton.beats.count) beats)...")
    let armA = runPassB(
        fixture: extraction.fixture, extracted: skeleton,
        castMapping: mapping, includeTemplateBody: true
    )
    log("[\(fixtureFilename)] ARM B — skeleton-only (\(skeleton.beats.count) beats)...")
    let armB = runPassB(
        fixture: extraction.fixture, extracted: skeleton,
        castMapping: mapping, includeTemplateBody: false
    )
    writeAblationReport(armA: armA, armB: armB)
}

func writeAblationReport(armA: GenerationRun, armB: GenerationRun) {
    let fixtureID = armA.fixture.frontmatter["fixture_id"] ?? armA.fixture.path.lastPathComponent
    var out = ""
    out += "# Pass-B ablation report — \(fixtureID)\n\n"
    out += "**Arm A:** template body included as voice exemplar (default 7.a.2 behaviour).\n"
    out += "**Arm B:** skeleton-only — no template prose injected. Tests Tripto 2025 long-exemplar surface-mimicry hypothesis.\n\n"
    out += "**Cast mapping (identical for both arms):**\n\n```\n\(armA.castMapping)\n```\n\n"

    let aWords = armA.beatOutputs.reduce(0) { $0 + $1.actualWords }
    let bWords = armB.beatOutputs.reduce(0) { $0 + $1.actualWords }
    let aEmpty = armA.beatOutputs.filter { $0.actualWords == 0 }.count
    let bEmpty = armB.beatOutputs.filter { $0.actualWords == 0 }.count
    let aLatency = armA.totalElapsedSeconds
    let bLatency = armB.totalElapsedSeconds

    out += "## Aggregate comparison\n\n"
    out += "| metric | Arm A (template included) | Arm B (skeleton only) |\n"
    out += "|---|---|---|\n"
    out += "| total words generated | \(aWords) | \(bWords) |\n"
    out += "| empty beats (0 words) | \(aEmpty) / \(armA.beatOutputs.count) | \(bEmpty) / \(armB.beatOutputs.count) |\n"
    out += "| total latency | \(String(format: "%.1fs", aLatency)) | \(String(format: "%.1fs", bLatency)) |\n"

    // Pacing-fidelity check: compute pacing stats over each arm's
    // assembled prose and compare to ground truth.
    let aProse = armA.beatOutputs.map(\.prose).joined(separator: "\n\n")
    let bProse = armB.beatOutputs.map(\.prose).joined(separator: "\n\n")
    let aPacing = PacingStats.compute(text: aProse)
    let bPacing = PacingStats.compute(text: bProse)
    let target = armA.groundTruthPacing
    out += "| mean sentence length | \(String(format: "%.1f", aPacing.meanSentenceLengthWords)) | \(String(format: "%.1f", bPacing.meanSentenceLengthWords)) |\n"
    out += "| short-sentence ratio | \(String(format: "%.2f", aPacing.shortSentenceRatio)) | \(String(format: "%.2f", bPacing.shortSentenceRatio)) |\n"
    out += "| long-sentence ratio | \(String(format: "%.2f", aPacing.longSentenceRatio)) | \(String(format: "%.2f", bPacing.longSentenceRatio)) |\n"
    out += "| dialogue ratio | \(String(format: "%.2f", aPacing.dialogueRatio)) | \(String(format: "%.2f", bPacing.dialogueRatio)) |\n\n"

    out += "**Target pacing (from source):** mean \(String(format: "%.1f", target.meanSentenceLengthWords))w, short \(String(format: "%.2f", target.shortSentenceRatio)), long \(String(format: "%.2f", target.longSentenceRatio)), dialogue \(String(format: "%.2f", target.dialogueRatio)).\n\n"

    // Pacing-deviation (signed Δ from target).
    let aMeanDelta = aPacing.meanSentenceLengthWords - target.meanSentenceLengthWords
    let bMeanDelta = bPacing.meanSentenceLengthWords - target.meanSentenceLengthWords
    out += "**Mean sentence length divergence from target:** Arm A \(String(format: "%+.1f", aMeanDelta))w, Arm B \(String(format: "%+.1f", bMeanDelta))w. Closer to zero = better pacing fidelity.\n\n"

    // Plot-leakage check, both arms.
    out += "## Plot-leakage comparison\n\n"
    func leaksFor(_ prose: String, sourceCharacters: [String]) -> [(String, Int)] {
        var leaks: [(String, Int)] = []
        for n in sourceCharacters {
            let c = prose.components(separatedBy: n).count - 1
            if c > 0 { leaks.append((n, c)) }
        }
        return leaks
    }
    let aLeaks = leaksFor(aProse, sourceCharacters: armA.skeleton.sourceCharacters)
    let bLeaks = leaksFor(bProse, sourceCharacters: armB.skeleton.sourceCharacters)
    out += "**Arm A character-name leakage:** \(aLeaks.isEmpty ? "✓ none" : aLeaks.map { "\($0.0)×\($0.1)" }.joined(separator: ", "))\n\n"
    out += "**Arm B character-name leakage:** \(bLeaks.isEmpty ? "✓ none" : bLeaks.map { "\($0.0)×\($0.1)" }.joined(separator: ", "))\n\n"

    // Modality post-hoc (heuristic) for both arms.
    out += "## Heuristic modality match\n\n"
    func modMatchCount(_ run: GenerationRun) -> Int {
        run.beatOutputs.reduce(0) { acc, o in
            let target = run.skeleton.beats[o.beatIndex].modality
            return acc + (NarrativeModeHeuristic.classify(o.prose) == target ? 1 : 0)
        }
    }
    out += "- Arm A: \(modMatchCount(armA)) / \(armA.beatOutputs.count)\n"
    out += "- Arm B: \(modMatchCount(armB)) / \(armB.beatOutputs.count)\n\n"

    // Per-beat side-by-side prose.
    out += "## Per-beat side-by-side prose\n\n"
    for i in 0..<armA.beatOutputs.count {
        let beat = armA.skeleton.beats[i]
        let aOut = armA.beatOutputs[i]
        let bOut = armB.beatOutputs[i]
        out += "### Beat \(i): \(beat.function.rawValue) / \(beat.modality.rawValue) (target \(beat.targetWords)w)\n\n"
        out += "_Summary:_ \(beat.summary)\n\n"
        out += "**Arm A (template included)** — \(aOut.actualWords)w, \(String(format: "%.1fs", aOut.elapsedSeconds)):\n\n"
        out += aOut.prose.isEmpty ? "_(empty)_\n\n" : "> \(aOut.prose.replacingOccurrences(of: "\n", with: "\n> "))\n\n"
        out += "**Arm B (skeleton only)** — \(bOut.actualWords)w, \(String(format: "%.1fs", bOut.elapsedSeconds)):\n\n"
        out += bOut.prose.isEmpty ? "_(empty)_\n\n" : "> \(bOut.prose.replacingOccurrences(of: "\n", with: "\n> "))\n\n"
        out += "---\n\n"
    }

    out += "## Assembled scenes\n\n"
    out += "<details><summary>Arm A — full assembled scene</summary>\n\n"
    out += armA.beatOutputs.map(\.prose).joined(separator: "\n\n") + "\n\n</details>\n\n"
    out += "<details><summary>Arm B — full assembled scene</summary>\n\n"
    out += armB.beatOutputs.map(\.prose).joined(separator: "\n\n") + "\n\n</details>\n"

    let outName = armA.fixture.path.deletingPathExtension().lastPathComponent + ".ablation.md"
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let outPath = cwd.appendingPathComponent(outputDir).appendingPathComponent(outName)
    try? FileManager.default.createDirectory(at: outPath.deletingLastPathComponent(), withIntermediateDirectories: true)
    do {
        try out.write(to: outPath, atomically: true, encoding: .utf8)
        log("[\(armA.fixture.path.lastPathComponent)] wrote \(outPath.path)")
    } catch {
        log("[\(armA.fixture.path.lastPathComponent)] failed to write report: \(error)")
    }
    print(out)
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

// MARK: - Goetia 6-way Pass-A transport bake-off (2026-05-22)
//
// Pass-A beat extraction failed every transport on a *Thinking* 31B
// writer + gemma4_2b (memory: feedback_beat_extraction_model_wall).
// Goetia (Mistral-Small-3 24B, non-thinking) is now loaded on Kobold;
// this command runs all 6 methods against the SAME source scene and
// prints a comparison table to decide which transport (if any) is
// usable. No production default is changed by this command.
//
//   swift run SceneTemplateSpike --goetia-compare
//
// Source scene: largest .md under /Volumes/SSD1/test5/templates|references.

let goetiaScenePaths = [
    "/Volumes/SSD1/test5/templates/10807B14-A7FD-482A-876A-EB5E8B4CCCB8.md",
    "/Volumes/SSD1/test5/references/10807B14-A7FD-482A-876A-EB5E8B4CCCB8.md",
]

struct MethodResult {
    let name: String
    let detail: String
    let raw: String
    let elapsed: Double
    let skeleton: ExtractedSceneSkeleton?
    let error: String?
}

/// One non-streaming Kobold completion, raw text out. `grammar: nil`
/// runs unconstrained. Mirrors `KoboldBeatExtractor`'s sampler posture
/// (temp 0.2, source-scaled maxLength) but captures the raw roll.
func goetiaKoboldRaw(prompt: String, grammar: String?, maxContext: Int) -> Result<String, Error> {
    guard let base = URL(string: koboldURLString) else {
        return .failure(NSError(domain: "spike", code: -1, userInfo: [NSLocalizedDescriptionKey: "bad kobold URL"]))
    }
    let adapter = InstructTemplates.adapter(for: .mistralV7)
    let wrapped = adapter.wrap(system: "", userBody: prompt, prefill: "")
    var params = SamplerParams.phase1Defaults
    params.temperature = 0.2
    let promptTokens = TokenEstimator.estimate(wrapped)
    params.maxLength = max(2048, min(maxContext - promptTokens - 256, 12288))
    let client = KoboldClient(baseURL: base)
    let sem = DispatchSemaphore(value: 0)
    var out: Result<String, Error> = .failure(NSError(domain: "spike", code: -1))
    client.generate(
        prompt: wrapped,
        stopSequences: adapter.stopSequences,
        params: params,
        maxContextLength: maxContext,
        grammar: grammar
    ) { r in out = r; sem.signal() }
    sem.wait()
    return out
}

/// One Ollama `/api/chat` call, raw text out. `schema` empty → omitted
/// (unconstrained); non-empty → sent as `format`. Mirrors
/// `OllamaBeatExtractor`'s sampler posture.
func goetiaOllamaRaw(model: String, prompt: String, schema: [String: Any], sourceProse: String) -> Result<String, Error> {
    guard let base = URL(string: ollamaURLString) else {
        return .failure(NSError(domain: "spike", code: -1, userInfo: [NSLocalizedDescriptionKey: "bad ollama URL"]))
    }
    let client = OllamaClient(baseURL: base, model: model)
    let options = OllamaChatOptions(
        temperature: 0.2,
        numPredict: OllamaBeatExtractor.budgetForProse(sourceProse),
        repeatPenalty: 1.1
    )
    let sem = DispatchSemaphore(value: 0)
    var out: Result<String, Error> = .failure(NSError(domain: "spike", code: -1))
    client.extract(prompt: prompt, schema: schema, options: options) { r in
        out = r.mapError { $0 as Error }; sem.signal()
    }
    sem.wait()
    return out
}

enum GoetiaParser { case nested, flat }

func goetiaParse(_ raw: String, with parser: GoetiaParser) -> (ExtractedSceneSkeleton?, String?) {
    let cleaned = ThinkBlockStripper.strip(raw)
    do {
        let skel = parser == .nested
            ? try BeatExtraction.parseExtractedSkeleton(cleaned)
            : try BeatExtraction.parseFlatSkeleton(cleaned)
        return (skel, nil)
    } catch {
        return (nil, String(describing: error))
    }
}

func runGoetiaMethod(
    name: String,
    detail: String,
    parser: GoetiaParser,
    call: () -> Result<String, Error>
) -> MethodResult {
    log("[goetia] \(name) — \(detail)...")
    let start = Date()
    let result = call()
    let elapsed = Date().timeIntervalSince(start)
    switch result {
    case .success(let raw):
        let (skel, perr) = goetiaParse(raw, with: parser)
        if let skel = skel {
            log("  → parsed \(skel.beats.count) beats in \(String(format: "%.1fs", elapsed))")
        } else {
            log("  → PARSE FAIL (\(perr ?? "?")) in \(String(format: "%.1fs", elapsed)); raw len=\(raw.count)")
        }
        return MethodResult(name: name, detail: detail, raw: raw, elapsed: elapsed, skeleton: skel, error: perr)
    case .failure(let err):
        log("  → TRANSPORT FAIL: \(err.localizedDescription)")
        return MethodResult(name: name, detail: detail, raw: "", elapsed: elapsed, skeleton: nil, error: "transport: \(err.localizedDescription)")
    }
}

func renderGoetiaComparison(modelName: String, scenePath: String, sourceWords: Int, results: [MethodResult]) -> String {
    func score(_ r: MethodResult) -> (parsed: String, beats: String, fns: String, tw: String, voice: String, secs: String) {
        let secs = String(format: "%.1f", r.elapsed)
        guard let s = r.skeleton else {
            return ("**no**", "—", "—", "—", "—", secs)
        }
        let funcs = s.beats.map { $0.function.rawValue }
        let distinct = Set(funcs).count
        let fnSummary = "\(distinct) (\(Set(funcs).sorted().joined(separator: ",")))"
        let tws = s.beats.map { $0.targetWords }
        let zero = tws.filter { $0 == 0 }.count
        let twSummary = tws.isEmpty ? "—" : "min \(tws.min()!) / max \(tws.max()!) / zero \(zero)"
        let voice: String
        if let v = s.voiceDescriptor {
            voice = "yes (\(v.sentenceCadence.rawValue))"
        } else {
            voice = "no"
        }
        return ("yes", "\(s.beats.count)", fnSummary, twSummary, voice, secs)
    }

    var out = ""
    out += "# Goetia Pass-A transport bake-off — \(dateStamp())\n\n"
    out += "**Writer model:** `\(modelName)` on KoboldCpp `\(koboldURLString)`\n\n"
    out += "**Extractor server:** Ollama `\(ollamaURLString)`\n\n"
    out += "**Source scene:** `\(scenePath)` (\(sourceWords) words)\n\n"
    out += "**Scoring:** USABLE = parses + 5–12 beats + ≥3 distinct functions + non-zero targetWords + voiceDescriptor present.\n\n"

    out += "| # | Method | Parsed | Beats | Distinct fns | targetWords | Voice (cadence) | Secs |\n"
    out += "|---|---|---|---|---|---|---|---|\n"
    for (i, r) in results.enumerated() {
        let sc = score(r)
        out += "| \(i + 1) | \(r.name) — \(r.detail) | \(sc.parsed) | \(sc.beats) | \(sc.fns) | \(sc.tw) | \(sc.voice) | \(sc.secs) |\n"
    }
    out += "\n"

    // Verdict per method.
    out += "## Verdict\n\n"
    for (i, r) in results.enumerated() {
        let usable: Bool
        var notes: [String] = []
        if let s = r.skeleton {
            let bc = s.beats.count
            let distinct = Set(s.beats.map { $0.function.rawValue }).count
            let nonZeroTW = s.beats.contains { $0.targetWords > 0 }
            let voice = s.voiceDescriptor != nil
            if bc < 5 || bc > 12 { notes.append("beatCount \(bc) outside 5–12") }
            if distinct < 3 { notes.append("only \(distinct) distinct function(s) — degenerate") }
            if !nonZeroTW { notes.append("all targetWords zero") }
            if !voice { notes.append("no voiceDescriptor") }
            usable = bc >= 5 && bc <= 12 && distinct >= 3 && nonZeroTW && voice
        } else {
            usable = false
            notes.append(r.error ?? "no skeleton")
        }
        out += "- **\(i + 1). \(r.name)** — \(usable ? "✅ USABLE" : "❌ unusable")\(notes.isEmpty ? "" : " — " + notes.joined(separator: "; "))\n"
    }
    out += "\n"

    // Failure dumps + parsed-beat tables.
    out += "## Per-method detail\n\n"
    for (i, r) in results.enumerated() {
        out += "### \(i + 1). \(r.name) — \(r.detail)\n\n"
        out += "_elapsed: \(String(format: "%.1fs", r.elapsed))_\n\n"
        if let s = r.skeleton {
            out += "| # | function | modality | targetWords | summary |\n"
            out += "|---|---|---|---|---|\n"
            for b in s.beats.prefix(14) {
                out += "| \(b.index) | \(b.function.rawValue) | \(b.modality.rawValue) | \(b.targetWords) | \(b.summary.replacingOccurrences(of: "|", with: "\\|").prefix(90)) |\n"
            }
            if let v = s.voiceDescriptor {
                out += "\n_voice:_ cadence=\(v.sentenceCadence.rawValue), dialogue=\(v.dialogueDensity.rawValue), flourish=\(v.rhetoricalFlourish.rawValue), register=\"\(v.register)\"\n\n"
            }
        } else {
            out += "**FAILED** — \(r.error ?? "unknown")\n\n"
            let dump = String(r.raw.prefix(800)).replacingOccurrences(of: "```", with: "`\u{200b}``")
            out += "Raw (first 800 chars):\n\n```\n\(dump.isEmpty ? "(empty / transport failure)" : dump)\n```\n\n"
        }
    }
    return out
}

func dateStamp() -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f.string(from: Date())
}

/// Confirm Goetia is live + read the context budget. Returns nil on a
/// bad URL; otherwise (modelName, maxContext) with sensible fallbacks.
func probeGoetia() -> (modelName: String, maxContext: Int)? {
    guard let base = URL(string: koboldURLString) else { return nil }
    let probe = KoboldClient(baseURL: base)
    var modelName = "?"
    var maxContext = 16384
    let s1 = DispatchSemaphore(value: 0)
    probe.fetchModel { if case .success(let n) = $0 { modelName = n }; s1.signal() }
    s1.wait()
    let s2 = DispatchSemaphore(value: 0)
    probe.fetchTrueMaxContext { if case .success(let c) = $0 { maxContext = c }; s2.signal() }
    s2.wait()
    return (modelName, maxContext)
}

func goetiaModelIsLoaded(_ modelName: String) -> Bool {
    let lower = modelName.lowercased()
    return lower.contains("goetia") || lower.contains("mistral-small") || lower.contains("mistral_small")
}

/// Pass-A via the production winner (Goetia + GBNF, nested schema).
/// Returns the parsed skeleton, or nil on transport/parse failure.
func extractViaGoetiaGBNF(sceneBody: String, maxContext: Int) -> ExtractedSceneSkeleton? {
    let prompt = BeatExtraction.buildExtractionPrompt(sourceProse: sceneBody)
    switch goetiaKoboldRaw(prompt: prompt, grammar: BeatExtraction.gbnfGrammar(), maxContext: maxContext) {
    case .success(let raw):
        let (skel, err) = goetiaParse(raw, with: .nested)
        if let err = err { log("[goetia-gen] Pass-A parse fail: \(err)") }
        return skel
    case .failure(let e):
        log("[goetia-gen] Pass-A transport fail: \(e.localizedDescription)")
        return nil
    }
}

/// End-to-end smoke: Pass-A via Goetia+GBNF on a registered fixture,
/// then Pass-B per-beat on the writer with the fixture's cast mapping.
/// Confirms the full Write-Scene-From-Template flow now produces usable
/// prose with the new default route.
func runGoetiaGenerate(fixtureFilename: String) {
    guard let mapping = castMappings[fixtureFilename] else {
        log("[\(fixtureFilename)] no cast mapping registered; skipping. (Registered: \(castMappings.keys.sorted().joined(separator: ", ")))")
        return
    }
    guard let probe = probeGoetia() else { log("ABORT: bad kobold URL \(koboldURLString)"); exit(1) }
    log("[goetia-gen] writer model: \(probe.modelName), maxContext: \(probe.maxContext)")
    guard goetiaModelIsLoaded(probe.modelName) else {
        log("ABORT: Kobold model \"\(probe.modelName)\" is not Goetia / Mistral-Small."); exit(1)
    }
    let fixturePath = cwd.appendingPathComponent(fixturesDir).appendingPathComponent(fixtureFilename)
    guard let fixture = try? loadFixture(path: fixturePath) else {
        log("ABORT: can't load fixture \(fixturePath.path)"); exit(1)
    }
    log("[goetia-gen] Pass-A via Goetia+GBNF (\(fixture.body.split(whereSeparator: { $0.isWhitespace }).count)w source)...")
    guard let skeleton = extractViaGoetiaGBNF(sceneBody: fixture.body, maxContext: probe.maxContext) else {
        log("[goetia-gen] Pass-A produced no skeleton; aborting Pass-B."); exit(1)
    }
    log("[goetia-gen] Pass-A → \(skeleton.beats.count) beats; running Pass-B per-beat...")
    let run = runPassB(fixture: fixture, extracted: skeleton, castMapping: mapping)
    writeGenerationReport(run)
}

// New-scene cast mapping for the test5 exemplar. Deliberately distant
// from the source's concrete content (different protagonist, venue,
// objects) so plot leakage is easy to spot, while preserving the
// register + multi-partner escalation structure the exemplar's voice
// and skeleton embody. The exemplar is the user's own adult-fiction
// scene — this transposes its STRUCTURE + VOICE onto a new cast.
let goetiaTest5Mapping = """
    New cast and setting:
    - PROTAGONIST: Mara, 27, a touring cellist. First-person narrator, the same confessional voice as the exemplar.
    - The other characters: three musicians from her chamber ensemble she has toured with for months — map them onto the source's partners as they arrive one at a time.
    - Setting: the green room of a concert hall, an hour after a sold-out late performance. The building is otherwise empty; the crew has gone home.
    - The protagonist has wanted this with the ensemble for the whole tour and tonight decides to act on it — map this onto the source's "deciding to make a private fantasy real."
    - Replace every concrete object/place from the source (party, balcony, bedroom, etc.) with green-room / backstage equivalents.
    - Keep the first-person, colloquial-confessional register and the escalating multi-partner arc; change the cast and place, not the shape.
    """

/// Generate a brand-new scene from the test5 exemplar: Pass-A (Goetia +
/// GBNF) extracts the exemplar's skeleton + voice, then Pass-B writes a
/// new scene under `goetiaTest5Mapping`. Validates the template pipeline
/// on the user's real exemplar rather than a spike fixture.
func runGoetiaTest5Generate() {
    guard let probe = probeGoetia() else { log("ABORT: bad kobold URL \(koboldURLString)"); exit(1) }
    log("[goetia-test5] writer model: \(probe.modelName), maxContext: \(probe.maxContext)")
    guard goetiaModelIsLoaded(probe.modelName) else {
        log("ABORT: Kobold model \"\(probe.modelName)\" is not Goetia / Mistral-Small."); exit(1)
    }
    var fixture: Fixture?
    for p in goetiaScenePaths where FileManager.default.fileExists(atPath: p) {
        fixture = try? loadFixture(path: URL(fileURLWithPath: p))
        if fixture != nil { break }
    }
    guard let fixture = fixture, !fixture.body.isEmpty else {
        log("ABORT: no test5 exemplar found at \(goetiaScenePaths.joined(separator: " | "))"); exit(1)
    }
    log("[goetia-test5] exemplar: \(fixture.path.path) (\(fixture.body.split(whereSeparator: { $0.isWhitespace }).count)w)")
    log("[goetia-test5] Pass-A via Goetia+GBNF...")
    guard let skeleton = extractViaGoetiaGBNF(sceneBody: fixture.body, maxContext: probe.maxContext) else {
        log("[goetia-test5] Pass-A produced no skeleton; aborting."); exit(1)
    }
    log("[goetia-test5] Pass-A → \(skeleton.beats.count) beats; running Pass-B with new cast mapping...")
    let run = runPassB(fixture: fixture, extracted: skeleton, castMapping: goetiaTest5Mapping)
    writeGenerationReport(run)
}

func runGoetiaCompare() {
    // Confirm Goetia is live + read the context budget.
    guard let probe = probeGoetia() else {
        log("ABORT: bad kobold URL \(koboldURLString)"); exit(1)
    }
    let modelName = probe.modelName
    let maxContext = probe.maxContext
    log("[goetia] writer model: \(modelName), maxContext: \(maxContext)")
    let lower = modelName.lowercased()
    guard lower.contains("goetia") || lower.contains("mistral-small") || lower.contains("mistral_small") else {
        log("ABORT: Kobold model \"\(modelName)\" is not Goetia / Mistral-Small. Load Goetia before running --goetia-compare.")
        exit(1)
    }

    // Load the source scene.
    var scenePath = ""
    var sceneBody = ""
    for p in goetiaScenePaths {
        if FileManager.default.fileExists(atPath: p),
           let fx = try? loadFixture(path: URL(fileURLWithPath: p)) {
            scenePath = p; sceneBody = fx.body; break
        }
    }
    if sceneBody.isEmpty {
        // Fall back to the largest spike fixture.
        let fixturesURL = cwd.appendingPathComponent(fixturesDir)
        if let entries = try? FileManager.default.contentsOfDirectory(at: fixturesURL, includingPropertiesForKeys: nil) {
            let md = entries.filter { $0.pathExtension == "md" }
                .compactMap { try? loadFixture(path: $0) }
                .max { $0.body.count < $1.body.count }
            if let md = md { scenePath = md.path.path; sceneBody = md.body }
        }
    }
    guard !sceneBody.isEmpty else {
        log("ABORT: no source scene found (test5 dir empty + no fixtures)."); exit(1)
    }
    let sourceWords = sceneBody.split(whereSeparator: { $0.isWhitespace }).count
    log("[goetia] source scene: \(scenePath) (\(sourceWords) words)")

    let nestedPrompt = BeatExtraction.buildExtractionPrompt(sourceProse: sceneBody)
    let flatPrompt = BeatExtraction.buildFlatPrompt(sourceProse: sceneBody)

    var results: [MethodResult] = []
    // 1. Goetia + GBNF (nested grammar).
    results.append(runGoetiaMethod(
        name: "Goetia + GBNF", detail: "nested grammar", parser: .nested
    ) { goetiaKoboldRaw(prompt: nestedPrompt, grammar: BeatExtraction.gbnfGrammar(), maxContext: maxContext) })
    // 2. Goetia + unconstrained, FLAT.
    results.append(runGoetiaMethod(
        name: "Goetia + unconstrained", detail: "flat prompt", parser: .flat
    ) { goetiaKoboldRaw(prompt: flatPrompt, grammar: nil, maxContext: maxContext) })
    // 3. Goetia + unconstrained, NESTED.
    results.append(runGoetiaMethod(
        name: "Goetia + unconstrained", detail: "nested prompt", parser: .nested
    ) { goetiaKoboldRaw(prompt: nestedPrompt, grammar: nil, maxContext: maxContext) })
    // 4. gemma4_2b + flat `format` schema.
    results.append(runGoetiaMethod(
        name: "gemma4_2b + format", detail: "flat schema", parser: .flat
    ) { goetiaOllamaRaw(model: "gemma4_2b:latest", prompt: flatPrompt, schema: BeatExtraction.flatJSONSchema(), sourceProse: sceneBody) })
    // 5. gemma4_4b + flat `format` schema.
    results.append(runGoetiaMethod(
        name: "gemma4_4b + format", detail: "flat schema", parser: .flat
    ) { goetiaOllamaRaw(model: "gemma4_4b:latest", prompt: flatPrompt, schema: BeatExtraction.flatJSONSchema(), sourceProse: sceneBody) })
    // 6. gemma4_2b + NESTED `format` schema (the 2026-05-22 failure combo, control).
    results.append(runGoetiaMethod(
        name: "gemma4_2b + format", detail: "nested schema (control)", parser: .nested
    ) { goetiaOllamaRaw(model: "gemma4_2b:latest", prompt: nestedPrompt, schema: BeatExtraction.jsonSchema(), sourceProse: sceneBody) })

    let report = renderGoetiaComparison(modelName: modelName, scenePath: scenePath, sourceWords: sourceWords, results: results)
    let outPath = cwd.appendingPathComponent(outputDir).appendingPathComponent("goetia-comparison.md")
    try? FileManager.default.createDirectory(at: outPath.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? report.write(to: outPath, atomically: true, encoding: .utf8)
    log("[goetia] wrote \(outPath.path)")
    print(report)
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
case "--ablate":
    guard args.count >= 3 else {
        log("--ablate requires a fixture basename (e.g. 01_the_doorway_dialogue.md)")
        exit(1)
    }
    runAblation(fixtureFilename: args[2])
case "--ablate-voice":
    guard args.count >= 3 else {
        log("--ablate-voice requires a fixture basename")
        exit(1)
    }
    runVoiceAblation(fixtureFilename: args[2])
case "--goetia-compare":
    runGoetiaCompare()
case "--goetia-generate":
    guard args.count >= 3 else {
        log("--goetia-generate requires a fixture basename (e.g. 01_the_doorway_dialogue.md)")
        exit(1)
    }
    runGoetiaGenerate(fixtureFilename: args[2])
case "--goetia-generate-test5":
    runGoetiaTest5Generate()
default:
    log("Unknown command: \(cmd)")
    exit(1)
}

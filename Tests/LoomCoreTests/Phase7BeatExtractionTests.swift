import Foundation
@testable import LoomCore

/// Phase 7.a.1 — beat extraction (Pass A) pure-data layer.
/// Mirrors the `Phase4LedgerExtractionTests` shape for the load-bearing
/// prompt-builder + JSON-Schema + response-parser triad. The runner
/// (`Tools/SceneTemplateSpike --extract`) wires these into a live
/// Ollama call against gemma4_2b and emits a Markdown report; the
/// spike writeup ([`LOOM_SCENE_TEMPLATE_SPIKE.md`](LOOM_SCENE_TEMPLATE_SPIKE.md))
/// hand-grades the reports against fixtures.
///
/// Architecturally pinned in [`LOOM_SCENE_TEMPLATE.md`](LOOM_SCENE_TEMPLATE.md)
/// §4 D1–D8 + §6 (data model) + §7 (prompt strategy).
func phase7BeatExtractionTests() -> TestSuite {
    let s = TestSuite("Phase7BeatExtraction")

    // MARK: - SceneBeat Codable round-trip

    s.test("SceneBeat round-trips Codable with all fields") {
        let beat = SceneBeat(
            index: 2,
            summary: "{PROTAGONIST} enters the kitchen and finds {ANTAGONIST} waiting.",
            modality: .action,
            function: .arrival,
            targetWords: 120,
            wordRangeStart: 240,
            wordRangeEnd: 350,
            beatTensionChange: 1
        )
        let data = try JSONEncoder().encode(beat)
        let decoded = try JSONDecoder().decode(SceneBeat.self, from: data)
        try expectEqual(decoded, beat)
    }

    // Phase 7.b prompt-revision punchlist item 5: tensionDelta renamed.
    s.test("SceneBeat decodes both `beatTensionChange` (new) and `tensionDelta` (legacy) keys") {
        let newKey = #"{"index":0,"summary":"x","modality":"action","function":"arrival","targetWords":50,"wordRangeStart":0,"wordRangeEnd":50,"beatTensionChange":2}"#
        let legacyKey = #"{"index":0,"summary":"x","modality":"action","function":"arrival","targetWords":50,"wordRangeStart":0,"wordRangeEnd":50,"tensionDelta":2}"#
        let a = try JSONDecoder().decode(SceneBeat.self, from: newKey.data(using: .utf8)!)
        let b = try JSONDecoder().decode(SceneBeat.self, from: legacyKey.data(using: .utf8)!)
        try expectEqual(a.beatTensionChange, 2)
        try expectEqual(b.beatTensionChange, 2)
    }

    // MARK: - BeatFunction enum

    s.test("BeatFunction.allCases covers the 8-tag taxonomy") {
        // The taxonomy is locked at the planning-doc level; if it
        // changes, the spike rubric needs updating in lockstep.
        try expectEqual(BeatFunction.allCases.map(\.rawValue).sorted(), [
            "arrival", "conflict", "escalation", "exit",
            "reaction", "resolution", "reveal", "setup",
        ])
    }

    // MARK: - PacingStats

    s.test("PacingStats.compute on simple paragraph") {
        let prose = "She walked. The road was long. She kept walking, eyes on the horizon, hoping for something."
        let stats = PacingStats.compute(text: prose)
        // 3 sentences:
        //   "She walked." → 2 words
        //   "The road was long." → 4 words
        //   "She kept walking, eyes on the horizon, hoping for something." → 10 words
        try expectEqual(stats.sentenceCount, 3)
        try expectTrue(abs(stats.meanSentenceLengthWords - (2.0 + 4.0 + 10.0) / 3.0) < 0.01)
        // 2 of 3 are under 8 words → 0.667 short ratio.
        try expectTrue(abs(stats.shortSentenceRatio - 2.0 / 3.0) < 0.01)
    }

    s.test("PacingStats.compute on empty text returns zero stats") {
        let stats = PacingStats.compute(text: "")
        try expectEqual(stats.sentenceCount, 0)
        try expectEqual(stats.meanSentenceLengthWords, 0)
    }

    s.test("PacingStats.compute counts dialogue ratio") {
        let prose = """
            "Hello," she said. He frowned. "Goodbye."
            """
        let stats = PacingStats.compute(text: prose)
        // "Hello," + "Goodbye" are quoted; "she said" + "He frowned" are not.
        // Crude word count inside straight double quotes.
        try expectTrue(stats.dialogueRatio > 0)
        try expectTrue(stats.dialogueRatio < 1.0)
    }

    // MARK: - BeatExtraction prompt builder

    s.test("BeatExtraction.buildExtractionPrompt includes the source prose") {
        let prompt = BeatExtraction.buildExtractionPrompt(
            sourceProse: "She walked into the room."
        )
        try expectTrue(prompt.contains("She walked into the room."))
        // Verify it asks for the load-bearing structural fields.
        try expectTrue(prompt.contains("beats"))
        try expectTrue(prompt.contains("modality"))
        try expectTrue(prompt.contains("function"))
        // Per D4 (STRAP content stripping) — the prompt must explicitly
        // ask for character-name replacement with role tokens.
        try expectTrue(prompt.lowercased().contains("{protagonist}")
                    || prompt.contains("role token")
                    || prompt.contains("placeholder"))
    }

    // MARK: - BeatExtraction JSON Schema

    s.test("BeatExtraction.jsonSchema returns a top-level object schema") {
        let schema = BeatExtraction.jsonSchema()
        try expectEqual(schema["type"] as? String, "object")
        let props = schema["properties"] as? [String: Any]
        try expectNotNil(props)
        // Required top-level keys.
        try expectNotNil(props?["beats"])
        try expectNotNil(props?["sourceCharacters"])
        try expectNotNil(props?["sourceSettingMarkers"])
        // Phase 7.b prompt-revision punchlist item 4: pacingStats
        // dropped — LLM-reported pacing was unreliable (under-counts
        // sentences by 40-60% in §7.a.1). Computed via
        // `PacingStats.compute(text:)` from the source instead.
        try expectTrue(props?["pacingStats"] == nil, "pacingStats should not be in the schema (dropped post-§7.a.1)")
    }

    s.test("BeatExtraction.jsonSchema constrains beat function + modality to enums") {
        let schema = BeatExtraction.jsonSchema()
        let props = schema["properties"] as! [String: Any]
        let beats = props["beats"] as! [String: Any]
        try expectEqual(beats["type"] as? String, "array")
        let items = beats["items"] as! [String: Any]
        let beatProps = items["properties"] as! [String: Any]
        let funcField = beatProps["function"] as! [String: Any]
        let funcEnum = funcField["enum"] as! [String]
        // All 8 BeatFunction cases present.
        try expectEqual(Set(funcEnum), Set(BeatFunction.allCases.map(\.rawValue)))
        // Modality enum matches the 6-value NarrativeMode taxonomy.
        let modField = beatProps["modality"] as! [String: Any]
        let modEnum = modField["enum"] as! [String]
        try expectEqual(Set(modEnum), Set(NarrativeMode.allCases.map(\.rawValue)))
    }

    // MARK: - Response parser

    s.test("BeatExtraction.parseExtractedSkeleton parses a clean response (post-§7.a.1: no pacingStats)") {
        let raw = """
        {
          "beats": [
            {"index": 0, "function": "setup", "modality": "description", "summary": "Empty room.", "targetWords": 60, "wordRangeStart": 0, "wordRangeEnd": 60, "beatTensionChange": 0},
            {"index": 1, "function": "arrival", "modality": "action", "summary": "{PROTAGONIST} enters.", "targetWords": 80, "wordRangeStart": 60, "wordRangeEnd": 140, "beatTensionChange": 1}
          ],
          "sourceCharacters": ["Maya", "John"],
          "sourceSettingMarkers": ["kitchen", "winter"]
        }
        """
        let skeleton = try BeatExtraction.parseExtractedSkeleton(raw)
        try expectEqual(skeleton.beats.count, 2)
        try expectEqual(skeleton.beats[0].function, .setup)
        try expectEqual(skeleton.beats[1].modality, .action)
        try expectEqual(skeleton.sourceCharacters, ["Maya", "John"])
    }

    s.test("BeatExtraction.parseExtractedSkeleton tolerates preamble + postamble") {
        // gemma4_2b often wraps structured output in chatty preamble.
        // Mirrors LedgerExtraction.parseExtractedFacts behaviour.
        let raw = """
        Here is the extracted skeleton:

        {
          "beats": [
            {"index": 0, "function": "arrival", "modality": "action", "summary": "x", "targetWords": 50, "wordRangeStart": 0, "wordRangeEnd": 50, "beatTensionChange": 0}
          ],
          "sourceCharacters": [],
          "sourceSettingMarkers": []
        }

        That should cover the structural skeleton.
        """
        let skeleton = try BeatExtraction.parseExtractedSkeleton(raw)
        try expectEqual(skeleton.beats.count, 1)
    }

    s.test("BeatExtraction.parseExtractedSkeleton throws on missing top-level object") {
        // Stale heuristic that grabbed only a substring should fail
        // gracefully — the spike runner catches + reports.
        do {
            _ = try BeatExtraction.parseExtractedSkeleton("not json at all")
            try expectFalse(true, "expected throw for non-JSON input")
        } catch {
            // pass
        }
    }

    return s
}

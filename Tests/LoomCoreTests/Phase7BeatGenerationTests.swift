import Foundation
@testable import LoomCore

/// Phase 7.a.2 — beat generation (Pass B) pure-data layer.
///
/// `BeatGeneration` builds the per-beat writer prompt from an
/// `ExtractedSceneSkeleton` (Pass A output) + a cast mapping +
/// the current beat index + the running prior-prose buffer.
/// Pinned in [`LOOM_SCENE_TEMPLATE.md`](LOOM_SCENE_TEMPLATE.md) §7.2.
func phase7BeatGenerationTests() -> TestSuite {
    let s = TestSuite("Phase7BeatGeneration")

    func makeSkeleton() -> ExtractedSceneSkeleton {
        ExtractedSceneSkeleton(
            beats: [
                SceneBeat(
                    index: 0, summary: "{PROTAGONIST} arrives in {INDOOR_PRIVATE_SPACE}.",
                    modality: .description, function: .setup,
                    targetWords: 80, wordRangeStart: 0, wordRangeEnd: 80,
                    tensionDelta: 0
                ),
                SceneBeat(
                    index: 1, summary: "{ANTAGONIST} confronts {PROTAGONIST} about the missed call.",
                    modality: .dialogue, function: .conflict,
                    targetWords: 120, wordRangeStart: 80, wordRangeEnd: 200,
                    tensionDelta: 2
                ),
                SceneBeat(
                    index: 2, summary: "{PROTAGONIST} reveals what was actually happening.",
                    modality: .dialogue, function: .reveal,
                    targetWords: 100, wordRangeStart: 200, wordRangeEnd: 300,
                    tensionDelta: 1
                ),
            ],
            sourceCharacters: ["Mara", "Daniel"],
            sourceSettingMarkers: ["doorway", "rain"],
            pacingStats: PacingStats(
                sentenceCount: 24, meanSentenceLengthWords: 12.0,
                sentenceLengthStdDev: 6.0, shortSentenceRatio: 0.4,
                longSentenceRatio: 0.15, paragraphLengthMean: 30,
                paragraphLengthStdDev: 10, dialogueRatio: 0.5
            )
        )
    }

    s.test("BeatGeneration.buildBeatPrompt includes template body, skeleton, cast, beat instruction") {
        let skeleton = makeSkeleton()
        let prompt = BeatGeneration.buildBeatPrompt(
            templateBody: "She walked into the doorway.",
            skeleton: skeleton,
            castMapping: "Maya is the protagonist; the setting is a server room.",
            currentBeatIndex: 0,
            priorBeatsProse: "",
            groundTruthPacing: skeleton.pacingStats
        )
        // Template prose present (D3 - first-class slot).
        try expectTrue(prompt.contains("She walked into the doorway."))
        // Skeleton present.
        try expectTrue(prompt.contains("{PROTAGONIST} arrives in {INDOOR_PRIVATE_SPACE}."))
        try expectTrue(prompt.contains("{ANTAGONIST} confronts"))
        // Cast mapping present.
        try expectTrue(prompt.contains("Maya is the protagonist"))
        // Beat-specific instruction at recency.
        try expectTrue(prompt.contains("Write beat 0"))
        try expectTrue(prompt.contains("description"))
        try expectTrue(prompt.contains("80"))  // target word count
        // Template explicitly framed as voice exemplar (D4).
        try expectTrue(prompt.lowercased().contains("voice")
                    || prompt.lowercased().contains("style"))
        try expectTrue(prompt.lowercased().contains("do not reuse"))
    }

    s.test("BeatGeneration.buildBeatPrompt for middle beat includes prior-beat prose") {
        let skeleton = makeSkeleton()
        let prompt = BeatGeneration.buildBeatPrompt(
            templateBody: "T",
            skeleton: skeleton,
            castMapping: "C",
            currentBeatIndex: 1,
            priorBeatsProse: "Maya walked into the server room. The lights were off.",
            groundTruthPacing: skeleton.pacingStats
        )
        try expectTrue(prompt.contains("Maya walked into the server room."))
        try expectTrue(prompt.contains("Write beat 1"))
    }

    s.test("BeatGeneration.buildBeatPrompt instruction includes pacing target") {
        let skeleton = makeSkeleton()
        let prompt = BeatGeneration.buildBeatPrompt(
            templateBody: "T",
            skeleton: skeleton,
            castMapping: "C",
            currentBeatIndex: 0,
            priorBeatsProse: "",
            groundTruthPacing: skeleton.pacingStats
        )
        // Pacing constraints expressed as positive numerical targets (D6).
        try expectTrue(prompt.contains("12") || prompt.contains("12.0"))  // mean sentence length
        try expectTrue(prompt.contains("sentence"))
    }

    s.test("BeatGeneration.buildBeatPrompt last beat instruction notes 'end the scene'") {
        let skeleton = makeSkeleton()
        let prompt = BeatGeneration.buildBeatPrompt(
            templateBody: "T",
            skeleton: skeleton,
            castMapping: "C",
            currentBeatIndex: 2,  // last beat (index 2 of 3 beats)
            priorBeatsProse: "X",
            groundTruthPacing: skeleton.pacingStats
        )
        // Final beat should not say "leads into beat N+1".
        try expectFalse(prompt.contains("leads into beat 3"))
        try expectTrue(prompt.lowercased().contains("end the scene")
                    || prompt.lowercased().contains("final beat"))
    }

    s.test("BeatGeneration.buildBeatPrompt throws-or-empty on out-of-range index") {
        let skeleton = makeSkeleton()
        // Out-of-range index is a programmer error; we return empty
        // string (the runner caller checks bounds before invoking).
        let prompt = BeatGeneration.buildBeatPrompt(
            templateBody: "T",
            skeleton: skeleton,
            castMapping: "C",
            currentBeatIndex: 99,
            priorBeatsProse: "",
            groundTruthPacing: skeleton.pacingStats
        )
        try expectEqual(prompt, "")
    }

    // MARK: - Phase 7.a.3 ablation: includeTemplateBody = false

    s.test("BeatGeneration.buildBeatPrompt with includeTemplateBody=false omits template + voice-exemplar framing") {
        let skeleton = makeSkeleton()
        let prompt = BeatGeneration.buildBeatPrompt(
            templateBody: "She walked into the doorway.",
            skeleton: skeleton,
            castMapping: "C",
            currentBeatIndex: 0,
            priorBeatsProse: "",
            groundTruthPacing: skeleton.pacingStats,
            includeTemplateBody: false
        )
        // Template body NOT present.
        try expectFalse(prompt.contains("She walked into the doorway."))
        try expectFalse(prompt.contains("TEMPLATE SCENE"))
        // Voice-exemplar framing replaced with skeleton-only framing.
        try expectFalse(prompt.contains("voice reference"))
        // Skeleton + cast + instruction still present.
        try expectTrue(prompt.contains("{PROTAGONIST} arrives"))
        try expectTrue(prompt.contains("Write beat 0"))
    }

    s.test("BeatGeneration.buildBeatPrompt defaults to includeTemplateBody=true") {
        // Existing tests already check default behaviour; this pins
        // the default contract explicitly so flipping the default
        // requires touching this test.
        let skeleton = makeSkeleton()
        let withDefault = BeatGeneration.buildBeatPrompt(
            templateBody: "She walked.",
            skeleton: skeleton, castMapping: "C",
            currentBeatIndex: 0, priorBeatsProse: "",
            groundTruthPacing: skeleton.pacingStats
        )
        let explicit = BeatGeneration.buildBeatPrompt(
            templateBody: "She walked.",
            skeleton: skeleton, castMapping: "C",
            currentBeatIndex: 0, priorBeatsProse: "",
            groundTruthPacing: skeleton.pacingStats,
            includeTemplateBody: true
        )
        try expectEqual(withDefault, explicit)
    }

    return s
}

import Foundation
@testable import LoomCore

// Phase 8.b.8 — D4 soft toggle ("imitate content"). When the user sets
// imitateContent=true, the system-framing block drops the "Do NOT
// reuse plot/characters/settings/specific events" prohibition and
// replaces it with a positive-constraint phrasing per the memory rule
// about prompt blacklists ("Substitute the cast below; preserve the
// source's content register, vocabulary, and act patterns where
// appropriate"). Default-off preserves Phase 7 behaviour.

private func _skeleton() -> ExtractedSceneSkeleton {
    ExtractedSceneSkeleton(
        beats: [SceneBeat(
            index: 0, summary: "{PROTAGONIST} arrives.", modality: .action, function: .setup,
            targetWords: 50, wordRangeStart: 0, wordRangeEnd: 50, beatTensionChange: 0
        )],
        sourceCharacters: ["{PROTAGONIST}"], sourceSettingMarkers: [], voiceDescriptor: nil
    )
}

private func _pacing() -> PacingStats {
    PacingStats(sentenceCount: 10, meanSentenceLengthWords: 12, sentenceLengthStdDev: 4,
                shortSentenceRatio: 0.3, longSentenceRatio: 0.2,
                paragraphLengthMean: 4, paragraphLengthStdDev: 1, dialogueRatio: 0.4)
}

func phase8SoftD4PromptTests() -> TestSuite {
    let s = TestSuite("Phase8SoftD4Prompt")

    s.test("default (imitateContent=false) keeps strict 'Do NOT reuse' phrasing") {
        let prompt = BeatGeneration.buildBeatPrompt(
            templateBody: "Template body.",
            skeleton: _skeleton(),
            castMapping: "PROTAGONIST: Maya.",
            currentBeatIndex: 0,
            priorBeatsProse: "",
            groundTruthPacing: _pacing()
        )
        try expectTrue(prompt.contains("Do NOT reuse"),
                       "Phase 7 strict phrasing should remain by default")
        try expectFalse(prompt.localizedCaseInsensitiveContains("preserve the source's"),
                       "soft phrasing should not appear in default mode")
    }

    s.test("imitateContent=true drops 'Do NOT reuse' and uses positive constraint") {
        let prompt = BeatGeneration.buildBeatPrompt(
            templateBody: "Template body.",
            skeleton: _skeleton(),
            castMapping: "PROTAGONIST: Maya.",
            currentBeatIndex: 0,
            priorBeatsProse: "",
            groundTruthPacing: _pacing(),
            imitateContent: true
        )
        try expectFalse(prompt.contains("Do NOT reuse"),
                        "strict prohibition must be absent in soft mode")
        try expectTrue(prompt.localizedCaseInsensitiveContains("preserve the source"),
                       "positive constraint phrasing should appear in soft mode")
    }

    s.test("imitateContent=true still substitutes the cast (no character-name leakage guard rail)") {
        // The character-name leakage guard is upstream — STRAP
        // content-stripping in Pass-A. Soft mode targets surface
        // vocabulary + act patterns, not character names. We assert
        // that the [NEW CAST] block is still present.
        let prompt = BeatGeneration.buildBeatPrompt(
            templateBody: "Template body.",
            skeleton: _skeleton(),
            castMapping: "PROTAGONIST: Maya, 32, journalist.",
            currentBeatIndex: 0,
            priorBeatsProse: "",
            groundTruthPacing: _pacing(),
            imitateContent: true
        )
        try expectTrue(prompt.contains("[NEW CAST]"))
        try expectTrue(prompt.contains("Maya, 32, journalist"))
    }

    s.test("imitateContent works with includeTemplateBody=false (skeleton-only ablation)") {
        let prompt = BeatGeneration.buildBeatPrompt(
            templateBody: "Template body that should NOT appear.",
            skeleton: _skeleton(),
            castMapping: "PROTAGONIST: Maya.",
            currentBeatIndex: 0,
            priorBeatsProse: "",
            groundTruthPacing: _pacing(),
            includeTemplateBody: false,
            imitateContent: true
        )
        try expectFalse(prompt.contains("Template body that should NOT appear"))
        // No template block means no "Do NOT reuse plot" guard rail to
        // strip — but the soft variant should ALSO not include any
        // strict-mode phrasing left over from the system framing.
        try expectFalse(prompt.contains("Do NOT reuse"))
    }

    return s
}

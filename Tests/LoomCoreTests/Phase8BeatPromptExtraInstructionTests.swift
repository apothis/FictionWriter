import Foundation
@testable import LoomCore

// Phase 8.b.x — `BeatGeneration.buildBeatPrompt` accepts an optional
// `extraInstruction` per-call hint. Renders as an
// `[ADDITIONAL INSTRUCTION` block immediately before
// `[INSTRUCTION]` (after `[STYLE EXEMPLARS]`), so the hint sits at
// recency next to the per-beat directive without displacing the
// load-bearing modality/function/word-count instruction.
//
// Mirrors the Continue/Expand flow's "per-call instruction box"
// affordance (Phase 1.5 add). The cast-mapping textarea is doing
// double duty as cast + situation today; this slot is for hints
// like "skip dialogue this beat" or "lean into the tension" that
// don't belong in the cast description.

private func _skeleton() -> ExtractedSceneSkeleton {
    ExtractedSceneSkeleton(
        beats: [SceneBeat(
            index: 0, summary: "{PROTAGONIST} arrives.", modality: .action, function: .setup,
            targetWords: 50, wordRangeStart: 0, wordRangeEnd: 50, beatTensionChange: 0
        )],
        sourceCharacters: [], sourceSettingMarkers: [], voiceDescriptor: nil
    )
}

private func _pacing() -> PacingStats {
    PacingStats(sentenceCount: 10, meanSentenceLengthWords: 12, sentenceLengthStdDev: 4,
                shortSentenceRatio: 0.3, longSentenceRatio: 0.2,
                paragraphLengthMean: 4, paragraphLengthStdDev: 1, dialogueRatio: 0.4)
}

func phase8BeatPromptExtraInstructionTests() -> TestSuite {
    let s = TestSuite("Phase8BeatPromptExtraInstruction")

    s.test("default empty extraInstruction omits [ADDITIONAL INSTRUCTION block (Phase 7 back-compat)") {
        let prompt = BeatGeneration.buildBeatPrompt(
            templateBody: "Template.",
            skeleton: _skeleton(),
            castMapping: "PROTAGONIST: Maya.",
            currentBeatIndex: 0,
            priorBeatsProse: "",
            groundTruthPacing: _pacing()
        )
        try expectFalse(prompt.contains("[ADDITIONAL INSTRUCTION"))
    }

    s.test("non-empty extraInstruction renders an [ADDITIONAL INSTRUCTION block") {
        let prompt = BeatGeneration.buildBeatPrompt(
            templateBody: "Template.",
            skeleton: _skeleton(),
            castMapping: "PROTAGONIST: Maya.",
            currentBeatIndex: 0,
            priorBeatsProse: "",
            groundTruthPacing: _pacing(),
            extraInstruction: "Skip dialogue this beat; lean into the tension."
        )
        try expectTrue(prompt.contains("[ADDITIONAL INSTRUCTION"))
        try expectTrue(prompt.contains("Skip dialogue this beat; lean into the tension."))
    }

    s.test("[ADDITIONAL INSTRUCTION lands BEFORE [INSTRUCTION]") {
        let prompt = BeatGeneration.buildBeatPrompt(
            templateBody: "Template.",
            skeleton: _skeleton(),
            castMapping: "PROTAGONIST: Maya.",
            currentBeatIndex: 0,
            priorBeatsProse: "",
            groundTruthPacing: _pacing(),
            extraInstruction: "Hint."
        )
        guard let hintIdx = prompt.range(of: "[ADDITIONAL INSTRUCTION")?.lowerBound,
              let instructionIdx = prompt.range(of: "[INSTRUCTION]")?.lowerBound else {
            throw TestFailure(
                message: "expected both blocks present",
                file: #file, line: #line
            )
        }
        try expectTrue(hintIdx < instructionIdx)
    }

    s.test("extraInstruction trims surrounding whitespace; whitespace-only counts as empty") {
        let pad = "   \n\n   "
        let prompt = BeatGeneration.buildBeatPrompt(
            templateBody: "Template.",
            skeleton: _skeleton(),
            castMapping: "PROTAGONIST: Maya.",
            currentBeatIndex: 0,
            priorBeatsProse: "",
            groundTruthPacing: _pacing(),
            extraInstruction: pad
        )
        try expectFalse(prompt.contains("[ADDITIONAL INSTRUCTION"),
                       "whitespace-only hint should not render the block")
    }

    return s
}

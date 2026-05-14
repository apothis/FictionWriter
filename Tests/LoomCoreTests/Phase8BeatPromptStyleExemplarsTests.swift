import Foundation
@testable import LoomCore

// Phase 8.b.3 — extend `BeatGeneration.buildBeatPrompt` to accept
// per-beat retrieved style exemplars. The new parameter is optional
// + defaults to empty so existing Phase 7 callers continue to compile
// without change. When non-empty, the exemplars render via the
// existing `StyleExemplarsLayer.format` and land in the prompt BEFORE
// the [INSTRUCTION] block per the §6.2 placement note.

private func makeSkeleton() -> ExtractedSceneSkeleton {
    return ExtractedSceneSkeleton(
        beats: [
            SceneBeat(index: 0, summary: "Setup.", modality: .action, function: .setup,
                      targetWords: 50, wordRangeStart: 0, wordRangeEnd: 50, beatTensionChange: 0),
            SceneBeat(index: 1, summary: "Reveal.", modality: .dialogue, function: .reveal,
                      targetWords: 60, wordRangeStart: 50, wordRangeEnd: 110, beatTensionChange: 1),
        ],
        sourceCharacters: ["{PROTAGONIST}"],
        sourceSettingMarkers: [],
        voiceDescriptor: nil
    )
}

private func makePacing() -> PacingStats {
    return PacingStats(
        sentenceCount: 12,
        meanSentenceLengthWords: 12,
        sentenceLengthStdDev: 4,
        shortSentenceRatio: 0.3,
        longSentenceRatio: 0.2,
        paragraphLengthMean: 4,
        paragraphLengthStdDev: 1,
        dialogueRatio: 0.4
    )
}

private func ex(_ text: String, name: String, modality: NarrativeMode? = nil) -> StyleExemplar {
    return StyleExemplar(
        referenceId: UUID(),
        referenceName: name,
        chunkIndex: 0,
        text: text,
        modality: modality,
        rrfScore: 1.0
    )
}

func phase8BeatPromptStyleExemplarsTests() -> TestSuite {
    let s = TestSuite("Phase8BeatPromptStyleExemplars")

    s.test("default-empty styleExemplars omits the [STYLE EXEMPLARS] block (Phase 7 back-compat)") {
        let prompt = BeatGeneration.buildBeatPrompt(
            templateBody: "Template body.",
            skeleton: makeSkeleton(),
            castMapping: "PROTAGONIST: Maya.",
            currentBeatIndex: 0,
            priorBeatsProse: "",
            groundTruthPacing: makePacing()
        )
        try expectFalse(prompt.contains("[STYLE EXEMPLARS]"),
                       "Phase 7 callers shouldn't see the new block by default")
        // Sanity: the existing layers are still present
        try expectTrue(prompt.contains("[BEAT SKELETON"))
        try expectTrue(prompt.contains("[INSTRUCTION]"))
    }

    s.test("non-empty styleExemplars renders the block via StyleExemplarsLayer") {
        let exemplars = [
            ex("She walked the road. The road was long.", name: "Hemingway sample", modality: .action),
            ex("The corridors stretched away in shadow.", name: "gothic excerpt", modality: .description),
        ]
        let prompt = BeatGeneration.buildBeatPrompt(
            templateBody: "Template body.",
            skeleton: makeSkeleton(),
            castMapping: "PROTAGONIST: Maya.",
            currentBeatIndex: 0,
            priorBeatsProse: "",
            groundTruthPacing: makePacing(),
            styleExemplars: exemplars
        )
        try expectTrue(prompt.contains("[STYLE EXEMPLARS]"))
        try expectTrue(prompt.contains("Hemingway sample"))
        try expectTrue(prompt.contains("gothic excerpt"))
        try expectTrue(prompt.contains("She walked the road"))
        // Modality tags come through
        try expectTrue(prompt.contains("(action)"))
        try expectTrue(prompt.contains("(description)"))
    }

    s.test("[STYLE EXEMPLARS] lands BEFORE [INSTRUCTION]") {
        let exemplars = [ex("Sample text.", name: "ref1")]
        let prompt = BeatGeneration.buildBeatPrompt(
            templateBody: "Template body.",
            skeleton: makeSkeleton(),
            castMapping: "PROTAGONIST: Maya.",
            currentBeatIndex: 0,
            priorBeatsProse: "",
            groundTruthPacing: makePacing(),
            styleExemplars: exemplars
        )
        guard let styleIdx = prompt.range(of: "[STYLE EXEMPLARS]")?.lowerBound,
              let instructionIdx = prompt.range(of: "[INSTRUCTION]")?.lowerBound else {
            throw TestFailure(
                message: "missing one of the two blocks",
                file: #file, line: #line
            )
        }
        try expectTrue(styleIdx < instructionIdx,
                       "[STYLE EXEMPLARS] must precede [INSTRUCTION]")
    }

    s.test("styleExemplars work with includeTemplateBody=false") {
        let exemplars = [ex("Sample.", name: "ref1")]
        let prompt = BeatGeneration.buildBeatPrompt(
            templateBody: "Template body that should NOT appear.",
            skeleton: makeSkeleton(),
            castMapping: "PROTAGONIST: Maya.",
            currentBeatIndex: 0,
            priorBeatsProse: "",
            groundTruthPacing: makePacing(),
            includeTemplateBody: false,
            styleExemplars: exemplars
        )
        try expectFalse(prompt.contains("Template body that should NOT appear"))
        try expectTrue(prompt.contains("[STYLE EXEMPLARS]"))
        try expectTrue(prompt.contains("Sample."))
    }

    return s
}

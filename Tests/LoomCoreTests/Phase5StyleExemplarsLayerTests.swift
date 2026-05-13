import Foundation
@testable import LoomCore

/// Pure-data tests for the prompt block that injects retrieved style
/// exemplars (StyleExemplar — output of RetrievalService) as few-shot
/// "voice cues" in the writer prompt. This is the Phase 5 production
/// integration into the existing PromptBuilder layer pipeline.
///
/// The framing matters: per [LOOM_RAG_SPIKE.md §13.3(d)](LOOM_RAG_SPIKE.md),
/// retrieved chunks share *style* with the query but may share *content*
/// (especially via the NSFW-content-as-topic failure mode of A/B
/// embedders). The block must instruct the model to use the
/// exemplars as voice cues — NOT to quote or paraphrase them — or
/// generation regresses to plagiarism.
func phase5StyleExemplarsLayerTests() -> TestSuite {
    let s = TestSuite("Phase5StyleExemplarsLayer")

    func makeExemplar(
        referenceName: String,
        modality: NarrativeMode,
        text: String,
        rrfScore: Double = 0.1
    ) -> StyleExemplar {
        StyleExemplar(
            referenceId: UUID(),
            referenceName: referenceName,
            chunkIndex: 0,
            text: text,
            modality: modality,
            rrfScore: rrfScore
        )
    }

    s.test("format on empty exemplars returns the empty string") {
        try expectEqual(StyleExemplarsLayer.format([]), "")
    }

    s.test("format on one exemplar includes voice-cues-not-content guidance") {
        // The failure mode the spike found: retrieved chunks may
        // share NSFW vocabulary with the scene-in-progress, which
        // tempts the model to plagiarise. The guidance line is
        // load-bearing.
        let block = StyleExemplarsLayer.format([
            makeExemplar(referenceName: "Hemingway", modality: .action,
                         text: "He walked the road.")
        ])
        let lower = block.lowercased()
        try expectTrue(
            lower.contains("voice") || lower.contains("style"),
            "block must frame exemplars as style/voice cues"
        )
        try expectTrue(
            lower.contains("not") && (lower.contains("quote") || lower.contains("copy") || lower.contains("paraphrase")),
            "block must forbid quoting/paraphrasing"
        )
    }

    s.test("format includes each exemplar's text verbatim") {
        let exemplars = [
            makeExemplar(referenceName: "A", modality: .action,
                         text: "He walked the road."),
            makeExemplar(referenceName: "B", modality: .description,
                         text: "The rain fell."),
        ]
        let block = StyleExemplarsLayer.format(exemplars)
        try expectTrue(block.contains("He walked the road."))
        try expectTrue(block.contains("The rain fell."))
    }

    s.test("format labels each exemplar with reference name + modality") {
        let block = StyleExemplarsLayer.format([
            makeExemplar(referenceName: "Hemingway sample", modality: .action,
                         text: "He walked.")
        ])
        try expectTrue(block.contains("Hemingway sample"))
        try expectTrue(block.contains("action"))
    }

    s.test("format places exemplars in input order (caller has already RRF-ranked)") {
        let exemplars = [
            makeExemplar(referenceName: "first", modality: .action, text: "ALPHA"),
            makeExemplar(referenceName: "second", modality: .action, text: "BETA"),
            makeExemplar(referenceName: "third", modality: .action, text: "GAMMA"),
        ]
        let block = StyleExemplarsLayer.format(exemplars)
        let alphaIdx = block.range(of: "ALPHA")!.lowerBound
        let betaIdx = block.range(of: "BETA")!.lowerBound
        let gammaIdx = block.range(of: "GAMMA")!.lowerBound
        try expectTrue(alphaIdx < betaIdx)
        try expectTrue(betaIdx < gammaIdx)
    }

    s.test("format handles a nil modality gracefully (legacy / pre-tag chunks)") {
        // The schema allows nil modality for chunks ingested before
        // scope-lock #5 tagging landed. The block should still
        // render but omit the modality label.
        let exemplar = StyleExemplar(
            referenceId: UUID(), referenceName: "ref",
            chunkIndex: 0, text: "Some prose.", modality: nil, rrfScore: 0.1
        )
        let block = StyleExemplarsLayer.format([exemplar])
        try expectTrue(block.contains("Some prose."))
        try expectTrue(block.contains("ref"))
    }

    s.test("format wraps the block in clear delimiters (parseable in History)") {
        // The History inspector + generation-log readers need to
        // identify the style block. Use bracketed markers consistent
        // with other Loom prompt layers (e.g. [KNOWLEDGE-LEDGER]).
        let block = StyleExemplarsLayer.format([
            makeExemplar(referenceName: "x", modality: .action, text: "Test.")
        ])
        try expectTrue(
            block.contains("[STYLE EXEMPLARS]") || block.contains("[STYLE-EXEMPLARS]"),
            "block must have a recognisable opening marker"
        )
    }

    // MARK: - PromptBuilder integration

    func ctx(prose: String, exemplars: [StyleExemplar] = []) -> PromptContext {
        let scene = Scene.empty(id: UUID(), title: "Scene 1")
        var sceneCopy = scene
        sceneCopy.prose = prose
        let project = Project(title: "Test")
        var p = project
        p.manuscript.orphanedSceneIds = [scene.id]
        return PromptContext(
            mode: .continueProse,
            project: p,
            scenes: [scene.id: sceneCopy],
            currentSceneId: scene.id,
            cursorOffset: prose.count,
            selectionRange: nil,
            modelName: nil,
            contextBudgetTokens: project.settings.contextBudgetTokens,
            replyBudgetTokens: 1024,
            styleExemplars: exemplars
        )
    }

    s.test("PromptContext.styleExemplars defaults to empty when omitted (backwards compat)") {
        let prose = "She walked into the room."
        let scene = Scene.empty(id: UUID(), title: "Scene 1")
        var sceneCopy = scene
        sceneCopy.prose = prose
        var p = Project(title: "Test")
        p.manuscript.orphanedSceneIds = [scene.id]
        let context = PromptContext(
            mode: .continueProse,
            project: p,
            scenes: [scene.id: sceneCopy],
            currentSceneId: scene.id,
            cursorOffset: prose.count,
            selectionRange: nil,
            modelName: nil,
            contextBudgetTokens: p.settings.contextBudgetTokens,
            replyBudgetTokens: 1024
        )
        try expectEqual(context.styleExemplars.count, 0)
    }

    s.test("empty styleExemplars produces no fewShotStyleExample chiclet") {
        let result = PromptBuilder.build(ctx(prose: "She walked.", exemplars: []))
        try expectFalse(result.chiclets.contains { $0.sourceKind == .fewShotStyleExample })
        try expectFalse(result.fullPrompt.contains("[STYLE EXEMPLARS]"))
    }

    s.test("non-empty styleExemplars produces a fewShotStyleExample chiclet") {
        let exemplars = [
            makeExemplar(referenceName: "Hemingway", modality: .action,
                         text: "He walked the road. The road was long.")
        ]
        let result = PromptBuilder.build(ctx(prose: "She walked.", exemplars: exemplars))
        let styleChiclets = result.chiclets.filter { $0.sourceKind == .fewShotStyleExample }
        try expectEqual(styleChiclets.count, 1)
        try expectTrue(styleChiclets[0].fullContent.contains("[STYLE EXEMPLARS]"))
        try expectTrue(styleChiclets[0].fullContent.contains("He walked the road."))
    }

    s.test("style-exemplars block appears in the user block (below cache), not the system block") {
        let exemplars = [
            makeExemplar(referenceName: "ref", modality: .action, text: "EXEMPLAR_TEXT")
        ]
        let result = PromptBuilder.build(ctx(prose: "She walked.", exemplars: exemplars))
        try expectTrue(result.userBlock.contains("EXEMPLAR_TEXT"))
        try expectFalse(result.systemBlock.contains("EXEMPLAR_TEXT"))
    }

    s.test("chiclet label includes the exemplar count") {
        let exemplars = [
            makeExemplar(referenceName: "a", modality: .action, text: "x"),
            makeExemplar(referenceName: "b", modality: .description, text: "y"),
            makeExemplar(referenceName: "c", modality: .interiority, text: "z"),
        ]
        let result = PromptBuilder.build(ctx(prose: "She walked.", exemplars: exemplars))
        let style = try expectNotNil(result.chiclets.first { $0.sourceKind == .fewShotStyleExample })
        try expectTrue(style.label.contains("3"), "label was: \(style.label)")
    }

    s.test("style-exemplars block appears BEFORE the recent-prose content in the user block") {
        let prose = "RECENT_PROSE_MARKER\n\nMore prose here."
        let exemplars = [
            makeExemplar(referenceName: "ref", modality: .action, text: "EXEMPLAR_MARKER")
        ]
        let result = PromptBuilder.build(ctx(prose: prose, exemplars: exemplars))
        let exemplarIdx = result.userBlock.range(of: "EXEMPLAR_MARKER")!.lowerBound
        let proseIdx = result.userBlock.range(of: "RECENT_PROSE_MARKER")!.lowerBound
        try expectTrue(
            exemplarIdx < proseIdx,
            "style exemplars should appear before recent prose so they prime the model's voice"
        )
    }

    return s
}

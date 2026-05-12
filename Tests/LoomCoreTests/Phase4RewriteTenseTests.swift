import Foundation
@testable import LoomCore

/// Phase 4 §14.1 #6 — rewriteTense sub-mode.
///
/// Mirrors `rewriteVoice` (commit `3101de3`): selection-replace
/// shape, target-tense descriptor on `PromptContext.perCallInstruction`,
/// no schema change. The descriptor is one of "past" / "present"
/// (the picker UI hands the user those choices; the prompt layer
/// accepts any freeform string so the contract stays open for
/// future tenses like "literary present" or "historical present").
func phase4RewriteTenseTests() -> TestSuite {
    let s = TestSuite("Phase4RewriteTense")

    // MARK: - Availability

    s.test("rewriteTense enabled when selection is non-empty") {
        let state = EditorState(hasProse: true, hasSelection: true)
        try expectTrue(GenerationModeAvailability.isEnabled(.rewriteTense, in: state))
    }

    s.test("rewriteTense disabled with no selection") {
        let state = EditorState(hasProse: true, hasSelection: false)
        try expectFalse(GenerationModeAvailability.isEnabled(.rewriteTense, in: state))
    }

    // MARK: - System prompt

    s.test("rewriteTense system prompt explicitly handles the no-op-target case") {
        // 2026-05-13 live test surfaced: when source tense already
        // matches target, the model invents a different tense shift
        // (past+past→present; present+present→future). Loophole was
        // the prompt's "rewrite in a different tense" framing
        // priming the model to think the task is to *change* tense
        // rather than *match* a target. The fix is explicit no-op
        // handling.
        let result = buildTenseResult(prose: "She walks into the room.", descriptor: nil)
        let lower = result.systemBlock.lowercased()
        let mentionsNoOp =
            lower.contains("regardless of") ||
            lower.contains("if a verb is already") ||
            lower.contains("if the passage is already") ||
            lower.contains("every verb in the target") ||
            lower.contains("every verb in target")
        try expectTrue(
            mentionsNoOp,
            "rewriteTense system prompt should explicitly handle the no-op case so the model doesn't invent an unrelated tense shift; got: \(result.systemBlock)"
        )
    }

    s.test("rewriteTense system prompt frames the task as a tense rewrite") {
        let result = buildTenseResult(prose: "She walked into the room.", descriptor: nil)
        try expectTrue(
            result.systemBlock.lowercased().contains("tense"),
            "rewriteTense system prompt should mention tense; got: \(result.systemBlock)"
        )
        try expectTrue(
            result.systemBlock.lowercased().contains("preserve") ||
            result.systemBlock.lowercased().contains("do not add"),
            "rewriteTense system prompt should commit to preserving plot/dialogue beats"
        )
    }

    // MARK: - Mode instruction

    s.test("rewriteTense mode instruction injects the selection as the passage to rewrite") {
        let result = buildTenseResult(prose: "She walked into the room.", descriptor: nil)
        try expectTrue(
            result.userBlock.contains("She walked into the room"),
            "selection should appear in the user block as the passage to reshape"
        )
        try expectTrue(
            result.userBlock.lowercased().contains("tense"),
            "mode instruction should frame this as a tense rewrite"
        )
    }

    s.test("rewriteTense carries the target-tense descriptor via perCallInstruction") {
        let result = buildTenseResult(prose: "She walked into the room.", descriptor: "present")
        try expectTrue(
            result.userBlock.contains("present"),
            "target tense descriptor should appear in userBlock; got: \(result.userBlock)"
        )
    }

    s.test("rewriteTense without a descriptor still produces a sensible tense frame") {
        let result = buildTenseResult(prose: "She walked into the room.", descriptor: nil)
        try expectTrue(result.userBlock.lowercased().contains("tense"))
        try expectFalse(
            result.userBlock.contains("Per-call instruction:"),
            "no descriptor → no per-call instruction layer"
        )
    }

    // MARK: - Layer ordering (recency wins)

    s.test("rewriteTense mode instruction lands AFTER recent-prose context") {
        let prose = "Background prose before. She walked into the room and looked around."
        let selStart = (prose as NSString).range(of: "She walked").location
        let selLen = (prose as NSString).length - selStart
        let result = buildTenseResult(
            prose: prose,
            selection: NSRange(location: selStart, length: selLen),
            descriptor: "present"
        )
        let proseIdx = try expectNotNil(result.userBlock.range(of: "Background prose before")?.lowerBound)
        let lower = result.userBlock.lowercased()
        let lastRewrite = try expectNotNil(lower.range(of: "rewrite", options: .backwards)?.lowerBound)
        let modeIdx = result.userBlock.index(
            result.userBlock.startIndex,
            offsetBy: lower.distance(from: lower.startIndex, to: lastRewrite)
        )
        try expectTrue(
            modeIdx > proseIdx,
            "rewriteTense mode instruction must land below the recent-prose layer"
        )
    }

    return s
}

private func buildTenseResult(
    prose: String,
    selection: NSRange? = nil,
    descriptor: String?
) -> AssembledPrompt {
    let scene = Scene.empty(id: UUID(), title: "Scene 1")
    var sceneCopy = scene
    sceneCopy.prose = prose
    var project = Project(title: "T")
    project.manuscript.orphanedSceneIds = [scene.id]
    let range = selection ?? NSRange(location: 0, length: (prose as NSString).length)
    let ctx = PromptContext(
        mode: .rewriteTense,
        project: project,
        scenes: [scene.id: sceneCopy],
        currentSceneId: scene.id,
        cursorOffset: NSMaxRange(range),
        selectionRange: range,
        modelName: nil,
        contextBudgetTokens: project.settings.contextBudgetTokens,
        replyBudgetTokens: 1024,
        perCallInstruction: descriptor
    )
    return PromptBuilder.build(ctx)
}

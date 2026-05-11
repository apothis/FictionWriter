import Foundation
@testable import LoomCore

/// Phase 4 §14.1 #1 — rewriteVoice sub-mode.
///
/// First Rewrite sub-variant to land. Reuses the existing rewrite
/// plumbing (selection-replace, snapshot-before-rewrite, acceptance
/// window) but ships a voice-specific system prompt + mode instruction
/// per LOOM_GENERATION_MODES.md §4.1.
///
/// The target-voice descriptor is carried via `PromptContext.perCallInstruction`
/// — no schema change. When the descriptor is empty/nil the prompt falls
/// back to a generic voice frame (still narrows the rewrite intent, just
/// without a named target).
func phase4RewriteVoiceTests() -> TestSuite {
    let s = TestSuite("Phase4RewriteVoice")

    // MARK: - Availability

    s.test("rewriteVoice enabled when selection is non-empty") {
        let state = EditorState(hasProse: true, hasSelection: true)
        try expectTrue(GenerationModeAvailability.isEnabled(.rewriteVoice, in: state))
    }

    s.test("rewriteVoice disabled with no selection") {
        let state = EditorState(hasProse: true, hasSelection: false)
        try expectFalse(GenerationModeAvailability.isEnabled(.rewriteVoice, in: state))
    }

    // MARK: - System prompt

    s.test("rewriteVoice system prompt frames the task as a voice rewrite") {
        let project = Project(title: "T")
        let scene = Scene.empty(id: UUID(), title: "Scene 1")
        let prose = "She walked into the room and looked around."
        let ctx = makeRewriteVoiceContext(
            project: project,
            scene: scene,
            prose: prose,
            selection: NSRange(location: 0, length: (prose as NSString).length),
            descriptor: nil
        )
        let result = PromptBuilder.build(ctx)
        // Voice-specific framing — must mention "voice" so the model
        // knows this is a stylistic rewrite, not a generic reshape.
        try expectTrue(
            result.systemBlock.lowercased().contains("voice"),
            "rewriteVoice system prompt should mention voice; got: \(result.systemBlock)"
        )
        // Preserves the existing rewrite contract: do not invent or
        // skip beats / dialogue.
        try expectTrue(
            result.systemBlock.lowercased().contains("preserve") ||
            result.systemBlock.lowercased().contains("do not add"),
            "rewriteVoice system prompt should commit to preserving plot/dialogue beats"
        )
    }

    // MARK: - Mode instruction

    s.test("rewriteVoice mode instruction injects the selection as the passage to rewrite") {
        let project = Project(title: "T")
        let scene = Scene.empty(id: UUID(), title: "Scene 1")
        let prose = "She walked into the room and looked around."
        let ctx = makeRewriteVoiceContext(
            project: project,
            scene: scene,
            prose: prose,
            selection: NSRange(location: 0, length: (prose as NSString).length),
            descriptor: nil
        )
        let result = PromptBuilder.build(ctx)
        try expectTrue(
            result.userBlock.contains("She walked into the room"),
            "selection should appear in the user block as the passage to reshape"
        )
        try expectTrue(
            result.userBlock.lowercased().contains("voice"),
            "mode instruction should frame this as a voice rewrite"
        )
    }

    s.test("rewriteVoice carries the target-voice descriptor via perCallInstruction") {
        let project = Project(title: "T")
        let scene = Scene.empty(id: UUID(), title: "Scene 1")
        let prose = "She walked into the room and looked around."
        let ctx = makeRewriteVoiceContext(
            project: project,
            scene: scene,
            prose: prose,
            selection: NSRange(location: 0, length: (prose as NSString).length),
            descriptor: "hardboiled, terse, Chandler-flavoured"
        )
        let result = PromptBuilder.build(ctx)
        // The descriptor should land in the prompt somewhere so the
        // model can read it. The exact carrier (perCallInstruction
        // layer vs. inlined in the mode instruction) is intentionally
        // unconstrained by this test — only that the words make it
        // through to userBlock.
        try expectTrue(
            result.userBlock.contains("hardboiled, terse, Chandler-flavoured"),
            "target voice descriptor should appear in userBlock; got: \(result.userBlock)"
        )
    }

    s.test("rewriteVoice without a descriptor still produces a sensible voice frame") {
        // No perCallInstruction → generic voice frame. The system
        // prompt + mode instruction should still narrow intent to a
        // voice rewrite (not a generic reshape).
        let project = Project(title: "T")
        let scene = Scene.empty(id: UUID(), title: "Scene 1")
        let prose = "She walked into the room and looked around."
        let ctx = makeRewriteVoiceContext(
            project: project,
            scene: scene,
            prose: prose,
            selection: NSRange(location: 0, length: (prose as NSString).length),
            descriptor: nil
        )
        let result = PromptBuilder.build(ctx)
        try expectTrue(result.userBlock.lowercased().contains("voice"))
        // Should not advertise a "Per-call instruction:" layer when
        // the descriptor wasn't supplied — that layer is reserved for
        // explicit ad-hoc steering.
        try expectFalse(
            result.userBlock.contains("Per-call instruction:"),
            "no descriptor → no per-call instruction layer"
        )
    }

    // MARK: - Layer ordering (recency wins)

    s.test("rewriteVoice mode instruction lands AFTER recent-prose context") {
        let project = Project(title: "T")
        let scene = Scene.empty(id: UUID(), title: "Scene 1")
        let prose = "Background prose before. She walked into the room and looked around."
        let selStart = (prose as NSString).range(of: "She walked").location
        let selLen = (prose as NSString).length - selStart
        let ctx = makeRewriteVoiceContext(
            project: project,
            scene: scene,
            prose: prose,
            selection: NSRange(location: selStart, length: selLen),
            descriptor: "lyrical, slow"
        )
        let result = PromptBuilder.build(ctx)
        let proseIdx = try expectNotNil(result.userBlock.range(of: "Background prose before")?.lowerBound)
        // Find the mode-instruction landmark. The exact phrasing is
        // intentionally not nailed down; "rewrite" near the end is
        // enough to identify the post-prose injection.
        let lower = result.userBlock.lowercased()
        let lastRewrite = try expectNotNil(lower.range(of: "rewrite", options: .backwards)?.lowerBound)
        // Map back to the original-case string for index comparison.
        let modeIdx = result.userBlock.index(result.userBlock.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: lastRewrite))
        try expectTrue(
            modeIdx > proseIdx,
            "rewriteVoice mode instruction must land below the recent-prose layer (recency wins)"
        )
    }

    return s
}

// MARK: - Helpers

private func makeRewriteVoiceContext(
    project: Project,
    scene: Scene,
    prose: String,
    selection: NSRange,
    descriptor: String?
) -> PromptContext {
    var sceneCopy = scene
    sceneCopy.prose = prose
    var p = project
    if !p.manuscript.orphanedSceneIds.contains(scene.id) {
        p.manuscript.orphanedSceneIds.append(scene.id)
    }
    return PromptContext(
        mode: .rewriteVoice,
        project: p,
        scenes: [scene.id: sceneCopy],
        currentSceneId: scene.id,
        cursorOffset: NSMaxRange(selection),
        selectionRange: selection,
        modelName: nil,
        contextBudgetTokens: project.settings.contextBudgetTokens,
        replyBudgetTokens: 1024,
        perCallInstruction: descriptor
    )
}

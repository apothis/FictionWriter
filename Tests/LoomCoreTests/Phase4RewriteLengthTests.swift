import Foundation
@testable import LoomCore

/// Phase 4 §14.1 #6 — rewriteLength sub-mode.
///
/// Mirrors `rewriteVoice` (commit `3101de3`): selection-replace
/// shape, target-length descriptor on `PromptContext.perCallInstruction`,
/// no schema change. The descriptor is the target length, typically
/// expressed as a percentage of the original ("50%", "80%", "120%",
/// "150%" per LOOM_GENERATION_MODES.md §4.4); the prompt layer
/// accepts any freeform string so future length descriptors
/// ("half", "twice as long", word counts) stay supported.
func phase4RewriteLengthTests() -> TestSuite {
    let s = TestSuite("Phase4RewriteLength")

    // MARK: - Availability

    s.test("rewriteLength enabled when selection is non-empty") {
        let state = EditorState(hasProse: true, hasSelection: true)
        try expectTrue(GenerationModeAvailability.isEnabled(.rewriteLength, in: state))
    }

    s.test("rewriteLength disabled with no selection") {
        let state = EditorState(hasProse: true, hasSelection: false)
        try expectFalse(GenerationModeAvailability.isEnabled(.rewriteLength, in: state))
    }

    // MARK: - System prompt

    s.test("rewriteLength system prompt frames the task as a length rewrite") {
        let result = buildLengthResult(prose: "She walked into the room.", descriptor: nil)
        try expectTrue(
            result.systemBlock.lowercased().contains("length"),
            "rewriteLength system prompt should mention length; got: \(result.systemBlock)"
        )
        try expectTrue(
            result.systemBlock.lowercased().contains("preserve") ||
            result.systemBlock.lowercased().contains("do not add"),
            "rewriteLength system prompt should commit to preserving plot/dialogue beats"
        )
    }

    // MARK: - Mode instruction

    s.test("rewriteLength mode instruction injects the selection as the passage to rewrite") {
        let result = buildLengthResult(prose: "She walked into the room.", descriptor: nil)
        try expectTrue(
            result.userBlock.contains("She walked into the room"),
            "selection should appear in the user block as the passage to reshape"
        )
        try expectTrue(
            result.userBlock.lowercased().contains("length"),
            "mode instruction should frame this as a length rewrite"
        )
    }

    s.test("rewriteLength carries the target-length descriptor via perCallInstruction") {
        let result = buildLengthResult(prose: "She walked into the room.", descriptor: "150%")
        try expectTrue(
            result.userBlock.contains("150%"),
            "target length descriptor should appear in userBlock; got: \(result.userBlock)"
        )
    }

    s.test("rewriteLength without a descriptor still produces a sensible length frame") {
        let result = buildLengthResult(prose: "She walked into the room.", descriptor: nil)
        try expectTrue(result.userBlock.lowercased().contains("length"))
        try expectFalse(
            result.userBlock.contains("Per-call instruction:"),
            "no descriptor → no per-call instruction layer"
        )
    }

    // MARK: - Layer ordering (recency wins)

    s.test("rewriteLength mode instruction lands AFTER recent-prose context") {
        let prose = "Background prose before. She walked into the room and looked around."
        let selStart = (prose as NSString).range(of: "She walked").location
        let selLen = (prose as NSString).length - selStart
        let result = buildLengthResult(
            prose: prose,
            selection: NSRange(location: selStart, length: selLen),
            descriptor: "80%"
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
            "rewriteLength mode instruction must land below the recent-prose layer"
        )
    }

    return s
}

private func buildLengthResult(
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
        mode: .rewriteLength,
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

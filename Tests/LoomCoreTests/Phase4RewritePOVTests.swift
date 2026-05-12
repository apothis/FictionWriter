import Foundation
@testable import LoomCore

/// Phase 4 §14.1 #8 — rewritePOV sub-mode.
///
/// Mirrors `rewriteVoice` / `rewriteTense` / `rewriteLength`:
/// selection-replace shape, target descriptor on
/// `PromptContext.perCallInstruction`, no schema change. The
/// descriptor here is the structured POV-hint string produced by
/// `RewritePOVDescriptor.build(...)` — picker glue computes it at
/// click time from `LedgerKnowledge.compute` so the
/// `KNOWLEDGE_LEDGER_HINT` slot in LOOM_GENERATION_MODES.md §4.3
/// gets real data instead of staying empty.
func phase4RewritePOVTests() -> TestSuite {
    let s = TestSuite("Phase4RewritePOV")

    // MARK: - Availability

    s.test("rewritePOV enabled when selection is non-empty") {
        let state = EditorState(hasProse: true, hasSelection: true)
        try expectTrue(GenerationModeAvailability.isEnabled(.rewritePOV, in: state))
    }

    s.test("rewritePOV disabled with no selection") {
        let state = EditorState(hasProse: true, hasSelection: false)
        try expectFalse(GenerationModeAvailability.isEnabled(.rewritePOV, in: state))
    }

    // MARK: - System prompt

    s.test("rewritePOV system prompt frames the task as a POV rewrite") {
        let result = buildPOVResult(prose: "She walked into the room.", descriptor: nil)
        try expectTrue(
            result.systemBlock.uppercased().contains("POV") ||
            result.systemBlock.lowercased().contains("point of view"),
            "rewritePOV system prompt should mention POV; got: \(result.systemBlock)"
        )
        try expectTrue(
            result.systemBlock.lowercased().contains("preserve") ||
            result.systemBlock.lowercased().contains("do not add"),
            "rewritePOV system prompt should commit to preserving plot/dialogue beats"
        )
    }

    s.test("rewritePOV system prompt warns against inventing knowledge the new POV lacks") {
        let result = buildPOVResult(prose: "She walked into the room.", descriptor: nil)
        // The §4.3 spec is explicit: "the new POV character may not
        // have access to all internal thoughts of the original —
        // adjust interiority accordingly". Without this guidance,
        // POV swaps invent things the character couldn't know.
        let lowered = result.systemBlock.lowercased()
        try expectTrue(
            lowered.contains("interiority") || lowered.contains("invent") || lowered.contains("know"),
            "rewritePOV system prompt should warn against inventing knowledge; got: \(result.systemBlock)"
        )
    }

    // MARK: - Mode instruction

    s.test("rewritePOV mode instruction injects the selection as the passage to rewrite") {
        let result = buildPOVResult(prose: "She walked into the room.", descriptor: nil)
        try expectTrue(
            result.userBlock.contains("She walked into the room"),
            "selection should appear in the user block as the passage to reshape"
        )
        try expectTrue(
            result.userBlock.uppercased().contains("POV") ||
            result.userBlock.lowercased().contains("point of view"),
            "mode instruction should frame this as a POV rewrite"
        )
    }

    s.test("rewritePOV carries the structured descriptor via perCallInstruction") {
        let descriptor = "Target POV: Iris (third-person, limited).\n\nIris KNOWS as of this scene:\n- Daniel is married to Cora"
        let result = buildPOVResult(prose: "She walked into the room.", descriptor: descriptor)
        try expectTrue(result.userBlock.contains("Target POV: Iris"))
        try expectTrue(result.userBlock.contains("Daniel is married to Cora"))
    }

    s.test("rewritePOV without a descriptor still produces a sensible POV frame") {
        let result = buildPOVResult(prose: "She walked into the room.", descriptor: nil)
        try expectTrue(
            result.userBlock.uppercased().contains("POV") ||
            result.userBlock.lowercased().contains("point of view")
        )
        try expectFalse(
            result.userBlock.contains("Per-call instruction:"),
            "no descriptor → no per-call instruction layer"
        )
    }

    // MARK: - Layer ordering (recency wins)

    s.test("rewritePOV mode instruction lands AFTER recent-prose context") {
        let prose = "Background prose before. She walked into the room and looked around."
        let selStart = (prose as NSString).range(of: "She walked").location
        let selLen = (prose as NSString).length - selStart
        let result = buildPOVResult(
            prose: prose,
            selection: NSRange(location: selStart, length: selLen),
            descriptor: "Target POV: Iris (third-person, limited)."
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
            "rewritePOV mode instruction must land below the recent-prose layer"
        )
    }

    return s
}

private func buildPOVResult(
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
        mode: .rewritePOV,
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

import Foundation
@testable import LoomCore

/// Phase 4 §14.1 #9 — show-don't-tell sub-mode.
///
/// Per LOOM_GENERATION_MODES.md §4.5: take finished prose and
/// dramatise its told/summary/internal statements through action,
/// dialogue, gesture, sensory detail, and concrete observation. No
/// new plot. Approximately 120% length (mild expansion — the
/// dramatisation needs room without ballooning pacing).
///
/// Same selection-replace shape as the rest of the rewrite family;
/// snapshots before the rewrite via `SnapshotPolicy.shouldSnapshot`.
/// No descriptor needed at this stage — the 120% guidance lives in
/// the system prompt. Power users override via the tray instruction
/// field at call time.
func phase4ShowDontTellTests() -> TestSuite {
    let s = TestSuite("Phase4ShowDontTell")

    // MARK: - Availability

    s.test("showDontTell enabled when selection is non-empty") {
        let state = EditorState(hasProse: true, hasSelection: true)
        try expectTrue(GenerationModeAvailability.isEnabled(.showDontTell, in: state))
    }

    s.test("showDontTell disabled with no selection") {
        let state = EditorState(hasProse: true, hasSelection: false)
        try expectFalse(GenerationModeAvailability.isEnabled(.showDontTell, in: state))
    }

    // MARK: - Snapshot policy

    s.test("showDontTell warrants a pre-rewrite snapshot (selection-replace insurance)") {
        try expectTrue(SnapshotPolicy.shouldSnapshot(beforeMode: .showDontTell))
    }

    // MARK: - System prompt

    s.test("showDontTell system prompt frames the task as a show-don't-tell rewrite") {
        let result = buildSDTResult(prose: "She felt sad and then walked into the room.", descriptor: nil)
        let lower = result.systemBlock.lowercased()
        try expectTrue(
            lower.contains("show") && (lower.contains("don't tell") || lower.contains("dramatis") || lower.contains("dramatiz")),
            "show-don't-tell system prompt should mention show/dramatise; got: \(result.systemBlock)"
        )
        try expectTrue(
            lower.contains("preserve") || lower.contains("do not add"),
            "system prompt should commit to preserving plot/dialogue beats"
        )
    }

    s.test("showDontTell system prompt forbids forward-extrapolation past the source's narrative moment") {
        // 2026-05-13 Test 7 retest surfaced: the generic
        // scope-discipline clause (added across all rewrite-family
        // modes) bit on cross-scene character pulling + invented
        // relationship history, but did NOT stop SDT from
        // re-anchoring the scene at a new location ("her apartment
        // door"), inventing arrival-with-keys content not in the
        // source, or extrapolating future intimate contact
        // ("his palms sliding under her clothes"). SDT's task
        // structure ("expand to show") competes with the scope
        // clause's "stay inside"; on sparse told-emotion sources
        // the model invents concrete material to have something
        // to show. This bullet specifically forbids those.
        let result = buildSDTResult(prose: "She felt sad and then walked into the room.", descriptor: nil)
        let lower = result.systemBlock.lowercased()
        let mentionsExactMoment =
            lower.contains("exact narrative moment") ||
            lower.contains("exact moment") ||
            lower.contains("same physical and temporal slice") ||
            lower.contains("same physical and temporal") ||
            lower.contains("same moment")
        try expectTrue(
            mentionsExactMoment,
            "showDontTell system prompt should pin output to the exact moment the source depicts; got: \(result.systemBlock)"
        )
        let mentionsNoLocationInvention =
            lower.contains("do not invent new locations") ||
            lower.contains("do not invent locations") ||
            lower.contains("do not invent settings") ||
            lower.contains("not invent new locations")
        try expectTrue(
            mentionsNoLocationInvention,
            "showDontTell system prompt should explicitly forbid inventing new locations/settings; got: \(result.systemBlock)"
        )
        let mentionsNoFutureExtrapolation =
            lower.contains("do not extrapolate future") ||
            lower.contains("not extrapolate future") ||
            lower.contains("imagined") ||
            lower.contains("about to") ||
            lower.contains("future sensations")
        try expectTrue(
            mentionsNoFutureExtrapolation,
            "showDontTell system prompt should explicitly forbid extrapolating future sensations / 'imagined' / 'about to' content; got: \(result.systemBlock)"
        )
    }

    s.test("showDontTell system prompt anchors the ~120% length target") {
        let result = buildSDTResult(prose: "She felt sad and then walked into the room.", descriptor: nil)
        // §4.5 explicitly calls for ~120% expansion. Without this
        // anchor the model either rewrites at parity (too little
        // dramatisation room) or balloons to 200%+.
        try expectTrue(
            result.systemBlock.contains("120%"),
            "show-don't-tell system prompt should anchor 120% length target; got: \(result.systemBlock)"
        )
    }

    // MARK: - Mode instruction

    s.test("showDontTell mode instruction injects the selection as the passage to dramatise") {
        let result = buildSDTResult(
            prose: "She felt sad and then walked into the room.",
            descriptor: nil
        )
        try expectTrue(
            result.userBlock.contains("She felt sad"),
            "selection should appear in the user block as the passage to reshape"
        )
        let lower = result.userBlock.lowercased()
        try expectTrue(
            lower.contains("show") || lower.contains("dramatis") || lower.contains("dramatiz"),
            "mode instruction should frame this as a show-don't-tell rewrite"
        )
    }

    s.test("showDontTell carries the user's tray-typed instruction via perCallInstruction") {
        let result = buildSDTResult(
            prose: "She felt sad and then walked into the room.",
            descriptor: "lean into smell and texture"
        )
        try expectTrue(
            result.userBlock.contains("lean into smell and texture"),
            "tray-typed instruction should land in userBlock; got: \(result.userBlock)"
        )
    }

    s.test("showDontTell without a descriptor still produces a sensible SDT frame") {
        let result = buildSDTResult(
            prose: "She felt sad and then walked into the room.",
            descriptor: nil
        )
        let lower = result.userBlock.lowercased()
        try expectTrue(lower.contains("show") || lower.contains("dramatis") || lower.contains("dramatiz"))
        try expectFalse(
            result.userBlock.contains("Per-call instruction:"),
            "no descriptor → no per-call instruction layer"
        )
    }

    // MARK: - Layer ordering (recency wins)

    s.test("showDontTell mode instruction lands AFTER recent-prose context") {
        let prose = "Background prose before. She felt sad and then walked into the room and looked around."
        let selStart = (prose as NSString).range(of: "She felt sad").location
        let selLen = (prose as NSString).length - selStart
        let result = buildSDTResult(
            prose: prose,
            selection: NSRange(location: selStart, length: selLen),
            descriptor: nil
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
            "show-don't-tell mode instruction must land below the recent-prose layer"
        )
    }

    return s
}

private func buildSDTResult(
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
        mode: .showDontTell,
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

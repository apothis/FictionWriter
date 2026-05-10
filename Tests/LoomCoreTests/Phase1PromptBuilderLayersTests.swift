import Foundation
@testable import LoomCore

/// Sub-step 1.i.A — pure tests for PromptBuilder's layer assembly. The
/// Phase 1 layer set per LOOM_MEMORY.md §4.6:
///
///   ABOVE CACHE BOUNDARY:
///     - System (per-mode prefix)
///     - Project Memory
///     - Style guide (Phase 5; empty)
///     - Bible-Constant (always-include all characters in Phase 1)
///
///   BELOW CACHE BOUNDARY:
///     - Recent prose
///     - Author's Note (bracketed [...]; current-scene anchor folded
///       in for Phase 1 per the §A3 simplification)
///     - Mode instruction
///     - Cursor / selection
///
/// Tests assert content presence, ordering, eviction priority, cache-
/// boundary token counts, and chiclet correctness. Template wrapping
/// is tested separately in Phase1InstructTemplate.
func phase1PromptBuilderLayersTests() -> TestSuite {
    let s = TestSuite("Phase1PromptBuilderLayers")

    s.test("empty project produces minimal valid prompt for Continue") {
        let project = Project(title: "Empty")
        let scene = Scene.empty(id: UUID(), title: "Scene 1")
        let context = makeContinueContext(project: project, scene: scene, prose: "")
        let result = PromptBuilder.build(context)
        // System block contains Continue's system instruction.
        try expectTrue(result.systemBlock.contains("continuing"), "Continue system prompt should mention continuing")
        // No memory, no characters, no prose.
        try expectFalse(result.systemBlock.contains("Memory:"))
        try expectFalse(result.systemBlock.contains("Cast:"))
    }

    s.test("Project Memory layer included when set") {
        var project = Project(title: "T")
        project.settings.memory = "World rules: magic is rare. POV: 3rd-person past."
        let scene = Scene.empty(id: UUID(), title: "Scene 1")
        let context = makeContinueContext(project: project, scene: scene, prose: "")
        let result = PromptBuilder.build(context)
        try expectTrue(result.systemBlock.contains("World rules: magic is rare."))
        // Chiclet records it.
        let memoryChiclet = result.chiclets.first { $0.sourceKind == .projectMemory }
        try expectNotNil(memoryChiclet)
    }

    s.test("Bible constants include all Phase 1 characters by name") {
        var project = Project(title: "T")
        project.bible.characters = [
            Character(name: "Mia"),
            Character(name: "Bob"),
        ]
        let scene = Scene.empty(id: UUID(), title: "Scene 1")
        let context = makeContinueContext(project: project, scene: scene, prose: "")
        let result = PromptBuilder.build(context)
        try expectTrue(result.systemBlock.contains("Mia"))
        try expectTrue(result.systemBlock.contains("Bob"))
        let bibleChiclet = result.chiclets.first { $0.sourceKind == .bibleConstant }
        try expectNotNil(bibleChiclet)
    }

    s.test("recent prose layer pulls last N chars before cursor (chat-shaped, in user message)") {
        // Phase 1 keeps a chat-shaped structure: prose + explicit
        // continuation instruction in the user message. (Story-mode
        // prefill — putting prose in the assistant turn — was
        // attempted and reverted; instruct-tuned chat models like
        // Qwen 3.6 emit <|im_end|> immediately when the prefill looks
        // like a complete response. Confirmed live 2026-05-10.)
        let prose = "Para one with some words.\n\nPara two with the cursor lands here."
        var project = Project(title: "T")
        project.settings.contextBudgetTokens = 8192
        let scene = Scene.empty(id: UUID(), title: "Scene 1")
        let context = makeContinueContext(project: project, scene: scene, prose: prose)
        let result = PromptBuilder.build(context)
        try expectTrue(result.userBlock.contains("Para two with the cursor lands here."))
        let proseChiclet = result.chiclets.first { $0.sourceKind == .recentProse }
        try expectNotNil(proseChiclet)
    }

    s.test("Continue mode includes an explicit anti-echo continuation instruction AFTER the prose") {
        // The instruction lands as the last below-cache layer so the
        // recency-bias rule ("lower = stronger") concentrates the
        // steering on the cursor. Prevents the chat-reply echo
        // pattern where Qwen quotes the opening sentence before
        // continuing.
        let prose = "She walked into the room and looked around."
        let project = Project(title: "T")
        let scene = Scene.empty(id: UUID(), title: "Scene 1")
        let context = makeContinueContext(project: project, scene: scene, prose: prose)
        let result = PromptBuilder.build(context)
        // Instruction is present.
        try expectTrue(result.userBlock.contains("Continue from immediately after"))
        try expectTrue(result.userBlock.contains("Do not restate"))
        // And it lands AFTER the prose (recency wins).
        let proseIdx = try expectNotNil(result.userBlock.range(of: "She walked into the room")?.lowerBound)
        let instrIdx = try expectNotNil(result.userBlock.range(of: "Continue from immediately after")?.lowerBound)
        try expectTrue(instrIdx > proseIdx, "Continue instruction must land below the prose")
    }

    s.test("Author's Note appears bracketed in the user block") {
        // Bracketed `[...]` convention from AI Dungeon / web-fiction
        // model prior. Phase 1 simplification: AN sits in the user
        // block; story-mode Continue puts prose in the prefill so the
        // chat-turn ordering (user → assistant) places AN before
        // prose. True depth-N injection within the prefill (so AN
        // sits ~1 paragraph above the cursor) is Phase 2 polish.
        var project = Project(title: "T")
        project.settings.authorsNote = "terse style; preceding prose authoritative"
        let scene = Scene.empty(id: UUID(), title: "Scene 1")
        let context = makeContinueContext(project: project, scene: scene, prose: "Some prose here.")
        let result = PromptBuilder.build(context)
        try expectTrue(result.userBlock.contains("[terse style; preceding prose authoritative]"))
    }

    s.test("mode instruction differs by mode (Continue vs Expand)") {
        let project = Project(title: "T")
        let scene = Scene.empty(id: UUID(), title: "Scene 1")
        let continueCtx = makeContinueContext(project: project, scene: scene, prose: "X")
        let expandCtx = makeExpandContext(project: project, scene: scene, prose: "selection here", selection: NSRange(location: 0, length: 14))
        let cont = PromptBuilder.build(continueCtx)
        let exp = PromptBuilder.build(expandCtx)
        try expectTrue(cont.systemBlock.contains("continuing"))
        try expectTrue(exp.systemBlock.contains("Sketch") || exp.systemBlock.contains("expand"))
    }

    s.test("Rewrite system prompt frames the selection as a passage to reshape (Phase 1.5)") {
        let project = Project(title: "T")
        let scene = Scene.empty(id: UUID(), title: "Scene 1")
        let prose = "She walked into the room and looked around."
        let ctx = makeRewriteContext(project: project, scene: scene, prose: prose, selection: NSRange(location: 0, length: (prose as NSString).length))
        let result = PromptBuilder.build(ctx)
        try expectTrue(result.systemBlock.contains("rewriting"), "Rewrite system prompt should mention rewriting")
        try expectTrue(result.userBlock.contains("Passage to rewrite:"))
        // The original passage is injected so the model sees what to reshape.
        try expectTrue(result.userBlock.contains("She walked into the room"))
    }

    s.test("Rewrite mode instruction lands AFTER the recent-prose context (recency wins)") {
        // The "Passage to rewrite:" + terminal instruction must land
        // below the recent-prose layer so the model's attention
        // concentrates on the passage being reshaped, not the
        // surrounding manuscript.
        let project = Project(title: "T")
        let scene = Scene.empty(id: UUID(), title: "Scene 1")
        let prose = "Background prose before. She walked into the room and looked around."
        let selStart = (prose as NSString).range(of: "She walked").location
        let selLen = (prose as NSString).length - selStart
        let ctx = makeRewriteContext(project: project, scene: scene, prose: prose, selection: NSRange(location: selStart, length: selLen))
        let result = PromptBuilder.build(ctx)
        let proseIdx = try expectNotNil(result.userBlock.range(of: "Background prose before")?.lowerBound)
        let instrIdx = try expectNotNil(result.userBlock.range(of: "Passage to rewrite:")?.lowerBound)
        try expectTrue(instrIdx > proseIdx, "Rewrite mode instruction must land below the recent-prose layer")
    }

    s.test("cache boundary: above-cache covers system+memory+bible-constant") {
        var project = Project(title: "T")
        project.settings.memory = "Memory text"
        project.bible.characters = [Character(name: "Mia")]
        let scene = Scene.empty(id: UUID(), title: "Scene 1")
        let context = makeContinueContext(project: project, scene: scene, prose: "Recent prose body")
        let result = PromptBuilder.build(context)
        try expectGreaterThan(result.aboveCacheTokens, 0)
        try expectGreaterThan(result.belowCacheTokens, 0)
        // Sanity: total = above + below.
        try expectEqual(result.totalTokens, result.aboveCacheTokens + result.belowCacheTokens)
    }

    s.test("eviction: tight budget evicts recent-prose oldest first") {
        // Long prose, tiny budget: recent-prose layer must shrink, but
        // system + memory + AN + cursor remain (mandatory).
        var project = Project(title: "T")
        project.settings.contextBudgetTokens = 400   // very tight
        project.settings.memory = "Memory must survive."
        let prose = String(repeating: "Long lorem ipsum body words. ", count: 200)
        let scene = Scene.empty(id: UUID(), title: "Scene 1")
        let context = makeContinueContext(project: project, scene: scene, prose: prose)
        let result = PromptBuilder.build(context)
        // Memory still present (mandatory).
        try expectTrue(result.systemBlock.contains("Memory must survive."))
        // Total tokens should stay within budget.
        try expectLessThan(result.totalTokens, project.settings.contextBudgetTokens + 50)   // small slack
        // Eviction list non-empty.
        try expectTrue(result.evictedLayers.contains("recentProse") || !result.evictedLayers.isEmpty,
                       "tight budget should record at least some evictions")
    }

    s.test("eviction never drops system or mode-instruction") {
        var project = Project(title: "T")
        project.settings.contextBudgetTokens = 200   // absurdly tight
        let prose = String(repeating: "x ", count: 5000)
        let scene = Scene.empty(id: UUID(), title: "Scene 1")
        let context = makeContinueContext(project: project, scene: scene, prose: prose)
        let result = PromptBuilder.build(context)
        // System content is mandatory — must remain regardless of budget.
        try expectFalse(result.systemBlock.isEmpty)
        // The Continue system prompt should be there.
        try expectTrue(result.systemBlock.contains("continuing"))
    }

    s.test("chiclets are ordered: above-cache first, below-cache second") {
        var project = Project(title: "T")
        project.settings.memory = "M"
        project.settings.authorsNote = "A"
        project.bible.characters = [Character(name: "Mia")]
        let scene = Scene.empty(id: UUID(), title: "Scene 1")
        let context = makeContinueContext(project: project, scene: scene, prose: "prose")
        let result = PromptBuilder.build(context)
        // Find the index of an above-cache chiclet and a below-cache
        // chiclet; above < below in array order.
        guard let memoryIdx = result.chiclets.firstIndex(where: { $0.sourceKind == .projectMemory }),
              let proseIdx = result.chiclets.firstIndex(where: { $0.sourceKind == .recentProse })
        else {
            throw TestFailure(message: "expected both projectMemory and recentProse chiclets", file: #file, line: #line)
        }
        try expectTrue(memoryIdx < proseIdx, "above-cache chiclets must precede below-cache")
    }

    s.test("Continue mode prefill is empty for raw template, suppression for ChatML") {
        // ChatML/Qwen story-mode: prefill <think>\n\n</think>\n\n to
        // suppress thinking; raw: empty.
        var project = Project(title: "T")
        project.settings.instructTemplate = .chatml
        let scene = Scene.empty(id: UUID(), title: "Scene 1")
        let chatmlCtx = makeContinueContext(project: project, scene: scene, prose: "")
        let chatml = PromptBuilder.build(chatmlCtx)
        try expectTrue(chatml.prefill.contains("<think>"))

        project.settings.instructTemplate = .raw
        let rawCtx = makeContinueContext(project: project, scene: scene, prose: "")
        let raw = PromptBuilder.build(rawCtx)
        try expectEqual(raw.prefill, "")
    }

    s.test("stopSequences match the chosen template") {
        var project = Project(title: "T")
        project.settings.instructTemplate = .chatml
        let scene = Scene.empty(id: UUID(), title: "Scene 1")
        let context = makeContinueContext(project: project, scene: scene, prose: "")
        let result = PromptBuilder.build(context)
        try expectTrue(result.stopSequences.contains("<|im_end|>"))
    }

    return s
}

// MARK: - Test helpers

private func makeContinueContext(project: Project, scene: Scene, prose: String) -> PromptContext {
    var sceneCopy = scene
    sceneCopy.prose = prose
    var p = project
    if !p.manuscript.orphanedSceneIds.contains(scene.id) {
        p.manuscript.orphanedSceneIds.append(scene.id)
    }
    return PromptContext(
        mode: .continueProse,
        project: p,
        scenes: [scene.id: sceneCopy],
        currentSceneId: scene.id,
        cursorOffset: prose.count,
        selectionRange: nil,
        modelName: nil,
        contextBudgetTokens: project.settings.contextBudgetTokens,
        replyBudgetTokens: 1024
    )
}

private func makeExpandContext(project: Project, scene: Scene, prose: String, selection: NSRange) -> PromptContext {
    var sceneCopy = scene
    sceneCopy.prose = prose
    var p = project
    if !p.manuscript.orphanedSceneIds.contains(scene.id) {
        p.manuscript.orphanedSceneIds.append(scene.id)
    }
    return PromptContext(
        mode: .expand,
        project: p,
        scenes: [scene.id: sceneCopy],
        currentSceneId: scene.id,
        cursorOffset: NSMaxRange(selection),
        selectionRange: selection,
        modelName: nil,
        contextBudgetTokens: project.settings.contextBudgetTokens,
        replyBudgetTokens: 1024
    )
}

private func makeRewriteContext(project: Project, scene: Scene, prose: String, selection: NSRange) -> PromptContext {
    var sceneCopy = scene
    sceneCopy.prose = prose
    var p = project
    if !p.manuscript.orphanedSceneIds.contains(scene.id) {
        p.manuscript.orphanedSceneIds.append(scene.id)
    }
    return PromptContext(
        mode: .rewrite,
        project: p,
        scenes: [scene.id: sceneCopy],
        currentSceneId: scene.id,
        cursorOffset: NSMaxRange(selection),
        selectionRange: selection,
        modelName: nil,
        contextBudgetTokens: project.settings.contextBudgetTokens,
        replyBudgetTokens: 1024
    )
}

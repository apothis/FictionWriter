import Foundation
@testable import LoomCore

/// P0a — wire `WritingDirection` into generation (LOOM_NSFW.md §3.2 +
/// §3.5). The schema landed in Phase 2 but nothing consumed it; this
/// suite pins the missing behaviour:
///
///   - `WritingDirectionPrompt.systemAddendum` turns the direction
///     into positive/structural posture text appended to the per-mode
///     system prompt (never a blacklist — repo memory note).
///   - `.porn` kind shortens the Author's Note depth (stronger
///     steering) and lengthens the Continue word target.
///   - `.extreme` explicitness adds the no-soften clause.
///
/// Pure-data tests-first per the repo TDD posture.
func phase4WritingDirectionPromptTests() -> TestSuite {
    let s = TestSuite("Phase4WritingDirectionPrompt")

    // MARK: systemAddendum — pure function

    s.test("default direction yields no addendum") {
        try expectTrue(WritingDirectionPrompt.systemAddendum(.defaults).isEmpty)
    }

    s.test("extreme explicitness adds the no-soften clause") {
        let d = WritingDirection(explicitnessLevel: .extreme)
        let a = WritingDirectionPrompt.systemAddendum(d).lowercased()
        try expectTrue(a.contains("extreme"))
        try expectTrue(a.contains("do not soften") || a.contains("not soften"))
    }

    s.test("graphic explicitness adds a no-fade / sustained-detail clause") {
        let d = WritingDirection(explicitnessLevel: .graphic)
        let a = WritingDirectionPrompt.systemAddendum(d).lowercased()
        try expectTrue(a.contains("sensory") || a.contains("anatomical"))
        try expectTrue(a.contains("fade") || a.contains("cut away"))
    }

    s.test("porn kind foregrounds explicit content") {
        let d = WritingDirection(kind: .porn, explicitnessLevel: .graphic)
        let a = WritingDirectionPrompt.systemAddendum(d).lowercased()
        try expectTrue(a.contains("foreground") || a.contains("substance"))
    }

    s.test("a fadeToBlack scene suppresses the porn-foreground clause") {
        let d = WritingDirection(kind: .porn, explicitnessLevel: .fadeToBlack)
        let a = WritingDirectionPrompt.systemAddendum(d).lowercased()
        try expectFalse(a.contains("foreground"))
        try expectFalse(a.contains("substance"))
    }

    s.test("crude register adds register guidance") {
        let d = WritingDirection(register: .crude)
        let a = WritingDirectionPrompt.systemAddendum(d).lowercased()
        try expectTrue(a.contains("crude"))
        try expectTrue(a.contains("register"))
    }

    s.test("literary register is the no-op default — no register clause") {
        let d = WritingDirection(register: .literary)
        try expectFalse(WritingDirectionPrompt.systemAddendum(d).lowercased().contains("register"))
    }

    s.test("explicitForeground pacing adds pacing guidance") {
        let d = WritingDirection(explicitnessLevel: .graphic, pacing: .explicitForeground)
        let a = WritingDirectionPrompt.systemAddendum(d).lowercased()
        try expectTrue(a.contains("extend") || a.contains("sensory beat"))
    }

    s.test("never FTB policy adds an explicit no-fade clause") {
        let d = WritingDirection(explicitnessLevel: .graphic, fadeToBlackPolicy: .never)
        let a = WritingDirectionPrompt.systemAddendum(d).lowercased()
        try expectTrue(a.contains("never fade") || a.contains("fade to black"))
    }

    // MARK: authorsNoteDepth — pure function

    s.test("porn kind shortens A/N depth to at most 2") {
        let d = WritingDirection(kind: .porn)
        try expectEqual(WritingDirectionPrompt.authorsNoteDepth(d, projectDefault: 4), 2)
    }

    s.test("erotica kind shortens A/N depth to at most 3") {
        let d = WritingDirection(kind: .erotica)
        try expectEqual(WritingDirectionPrompt.authorsNoteDepth(d, projectDefault: 4), 3)
    }

    s.test("a user depth stronger than the direction default is honoured") {
        let d = WritingDirection(kind: .porn)
        try expectEqual(WritingDirectionPrompt.authorsNoteDepth(d, projectDefault: 1), 1)
    }

    s.test("depth 0 (A/N-as-own-layer) is left untouched") {
        let d = WritingDirection(kind: .porn)
        try expectEqual(WritingDirectionPrompt.authorsNoteDepth(d, projectDefault: 0), 0)
    }

    s.test("literary kind leaves the project A/N depth unchanged") {
        try expectEqual(WritingDirectionPrompt.authorsNoteDepth(.defaults, projectDefault: 4), 4)
    }

    // MARK: continueWordTarget — pure function

    s.test("porn kind lengthens the Continue word target") {
        try expectGreaterThan(WritingDirectionPrompt.continueWordTarget(WritingDirection(kind: .porn)), 500)
    }

    s.test("literary kind keeps the default Continue word target") {
        try expectEqual(WritingDirectionPrompt.continueWordTarget(.defaults), 500)
    }

    // MARK: cursorDirective — near-cursor anti-fade reinforcement

    s.test("default direction yields no cursor directive") {
        try expectNil(WritingDirectionPrompt.cursorDirective(.defaults))
    }

    s.test("extreme explicitness yields a bracketed cursor directive") {
        let d = WritingDirection(explicitnessLevel: .extreme)
        let directive = WritingDirectionPrompt.cursorDirective(d)
        try expectNotNil(directive)
        try expectTrue(directive!.hasPrefix("["))
        try expectTrue(directive!.lowercased().contains("fade"))
    }

    s.test("graphic explicitness yields a cursor directive") {
        try expectNotNil(WritingDirectionPrompt.cursorDirective(WritingDirection(explicitnessLevel: .graphic)))
    }

    s.test("porn kind yields a cursor directive when the scene depicts") {
        try expectNotNil(WritingDirectionPrompt.cursorDirective(
            WritingDirection(kind: .porn, explicitnessLevel: .onScreen)
        ))
    }

    s.test("a fadeToBlack scene yields no cursor directive even in a porn project") {
        try expectNil(WritingDirectionPrompt.cursorDirective(
            WritingDirection(kind: .porn, explicitnessLevel: .fadeToBlack)
        ))
    }

    s.test("effective() applies a scene's explicitness override") {
        let base = WritingDirection(kind: .porn, explicitnessLevel: .extreme)
        let toned = WritingDirectionPrompt.effective(base, sceneExplicitness: .fadeToBlack)
        try expectEqual(toned.explicitnessLevel, .fadeToBlack)
        try expectEqual(toned.kind, .porn)
        let unchanged = WritingDirectionPrompt.effective(base, sceneExplicitness: nil)
        try expectEqual(unchanged.explicitnessLevel, .extreme)
    }

    s.test("onScreen explicitness on a mainstream project yields no cursor directive") {
        let d = WritingDirection(kind: .mainstream, explicitnessLevel: .onScreen)
        try expectNil(WritingDirectionPrompt.cursorDirective(d))
    }

    // MARK: PromptBuilder wiring

    s.test("extreme project: the system block carries the addendum") {
        var project = Project(title: "T")
        project.settings.writingDirection = WritingDirection(explicitnessLevel: .extreme)
        let scene = Scene.empty(id: UUID(), title: "S")
        let result = PromptBuilder.build(makeWDContext(project: project, scene: scene))
        try expectTrue(result.systemBlock.lowercased().contains("extreme"))
    }

    s.test("default project: the system block carries no direction addendum") {
        let project = Project(title: "T")
        let scene = Scene.empty(id: UUID(), title: "S")
        let result = PromptBuilder.build(makeWDContext(project: project, scene: scene))
        try expectFalse(result.systemBlock.lowercased().contains("explicit fiction project"))
    }

    s.test("porn project: the Continue system prompt asks for a longer passage") {
        var project = Project(title: "T")
        project.settings.writingDirection = WritingDirection(kind: .porn)
        let scene = Scene.empty(id: UUID(), title: "S")
        let result = PromptBuilder.build(makeWDContext(project: project, scene: scene))
        // The baked "~500 words" target is replaced by the longer one.
        try expectFalse(result.systemBlock.contains("~500 words"))
    }

    s.test("extreme project: the cursor directive lands in the user block") {
        var project = Project(title: "T")
        project.settings.writingDirection = WritingDirection(explicitnessLevel: .extreme)
        let scene = Scene.empty(id: UUID(), title: "S")
        let result = PromptBuilder.build(makeWDContext(project: project, scene: scene))
        try expectTrue(result.userBlock.lowercased().contains("do not fade"))
        try expectNotNil(result.chiclets.first { $0.sourceKind == .directionDirective })
    }

    s.test("default project: no cursor directive in the user block") {
        let project = Project(title: "T")
        let scene = Scene.empty(id: UUID(), title: "S")
        let result = PromptBuilder.build(makeWDContext(project: project, scene: scene))
        try expectNil(result.chiclets.first { $0.sourceKind == .directionDirective })
    }

    s.test("a scene's fadeToBlack override suppresses an extreme project's posture") {
        var project = Project(title: "T")
        project.settings.writingDirection = WritingDirection(
            kind: .porn, explicitnessLevel: .extreme
        )
        var scene = Scene.empty(id: UUID(), title: "S")
        scene.explicitnessLevel = .fadeToBlack
        let result = PromptBuilder.build(makeWDContext(project: project, scene: scene))
        try expectFalse(result.systemBlock.lowercased().contains("explicit fiction project"))
        try expectNil(result.chiclets.first { $0.sourceKind == .directionDirective })
    }

    s.test("a scene's extreme override lifts a literary project's posture") {
        let project = Project(title: "T")  // literary / fadeToBlack defaults
        var scene = Scene.empty(id: UUID(), title: "S")
        scene.explicitnessLevel = .extreme
        let result = PromptBuilder.build(makeWDContext(project: project, scene: scene))
        try expectTrue(result.systemBlock.lowercased().contains("extreme"))
    }

    return s
}

private func makeWDContext(project: Project, scene: Scene) -> PromptContext {
    var p = project
    if !p.manuscript.orphanedSceneIds.contains(scene.id) {
        p.manuscript.orphanedSceneIds.append(scene.id)
    }
    return PromptContext(
        mode: .continueProse,
        project: p,
        scenes: [scene.id: scene],
        currentSceneId: scene.id,
        cursorOffset: 0,
        selectionRange: nil,
        modelName: nil,
        contextBudgetTokens: project.settings.contextBudgetTokens,
        replyBudgetTokens: 1024
    )
}

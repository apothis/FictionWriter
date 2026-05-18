import Foundation
@testable import LoomCore

/// Prefill-aware Continue — when the manuscript ends mid-sentence the
/// trailing fragment is routed into the assistant-turn prefill so the
/// model completes the sentence from inside its own turn (anti-refusal).
func phase4PrefillSeedTests() -> TestSuite {
    let s = TestSuite("Phase4PrefillSeed")

    // MARK: PrefillSeed.extract — pure function

    s.test("a mid-sentence tail is split off as the seed") {
        let r = PrefillSeed.extract(from: "She nodded. He")
        try expectEqual(r.head, "She nodded. ")
        try expectEqual(r.seed, "He")
    }

    s.test("prose ending on a clean boundary has an empty seed") {
        try expectEqual(PrefillSeed.extract(from: "She nodded.").seed, "")
        try expectEqual(PrefillSeed.extract(from: "She nodded. ").seed, "")
        try expectEqual(PrefillSeed.extract(from: "Who is it?").seed, "")
    }

    s.test("only the last unfinished sentence becomes the seed") {
        let r = PrefillSeed.extract(from: "First. Second. And then he")
        try expectEqual(r.head, "First. Second. ")
        try expectEqual(r.seed, "And then he")
    }

    s.test("a paragraph break is a boundary") {
        let r = PrefillSeed.extract(from: "End of para.\n\nShe walked")
        try expectEqual(r.seed, "She walked")
    }

    s.test("a terminator inside quotes does not split; the close-quote does") {
        let r = PrefillSeed.extract(from: "\"Who is it?\" She turned and")
        try expectEqual(r.seed, "She turned and")
    }

    s.test("prose that is one unfinished fragment yields an empty head") {
        let r = PrefillSeed.extract(from: "She walked to the door and")
        try expectEqual(r.head, "")
        try expectEqual(r.seed, "She walked to the door and")
    }

    s.test("head + seed reconstructs the input") {
        for input in ["She nodded. He", "First. Second. And then he", "plain", ""] {
            let r = PrefillSeed.extract(from: input)
            try expectEqual(r.head + r.seed, input)
        }
    }

    // MARK: PromptBuilder wiring

    s.test("Continue routes a mid-sentence tail into the prefill") {
        let prose = "She crossed the room. Her hand slid lower and"
        let result = PromptBuilder.build(makePrefillContext(prose: prose, mode: .continueProse))
        try expectTrue(result.prefill.contains("Her hand slid lower and"))
        // The fragment left the user-context (no duplication).
        try expectFalse(result.userBlock.contains("Her hand slid lower and"))
        try expectTrue(result.userBlock.contains("She crossed the room."))
    }

    s.test("Continue on clean-ending prose adds no prefill seed") {
        let result = PromptBuilder.build(
            makePrefillContext(prose: "She crossed the room.", mode: .continueProse)
        )
        try expectFalse(result.prefill.contains("crossed"))
    }

    s.test("prose that is one unfinished fragment is left in context, not prefilled") {
        let result = PromptBuilder.build(
            makePrefillContext(prose: "Her hand slid lower and", mode: .continueProse)
        )
        try expectFalse(result.prefill.contains("Her hand slid lower"))
        try expectTrue(result.userBlock.contains("Her hand slid lower and"))
    }

    return s
}

private func makePrefillContext(prose: String, mode: GenerationMode) -> PromptContext {
    var project = Project(title: "T")
    let scene = Scene.empty(id: UUID(), title: "S")
    project.manuscript.orphanedSceneIds = [scene.id]
    var sceneCopy = scene
    sceneCopy.prose = prose
    return PromptContext(
        mode: mode,
        project: project,
        scenes: [scene.id: sceneCopy],
        currentSceneId: scene.id,
        cursorOffset: prose.utf16.count,
        selectionRange: nil,
        modelName: nil,
        contextBudgetTokens: 8192,
        replyBudgetTokens: 1024
    )
}

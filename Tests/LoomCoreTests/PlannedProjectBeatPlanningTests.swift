import Foundation
@testable import LoomCore

/// Planned Project mode — Phase 5.1: beat planning. An outline scene
/// carries only a one-paragraph `summary` + a `targetWordCount`. To
/// draft it with the per-beat writer loop, the summary is first
/// decomposed into an ordered list of beats, each with a slice of the
/// scene's word budget. The beat *count* and the word split are
/// deterministic (code); the beat *intents* come from one LLM pass.
func plannedProjectBeatPlanningTests() -> TestSuite {
    let s = TestSuite("PlannedProjectBeatPlanning")

    // MARK: - beatCount

    s.test("beatCount scales ~one beat per 300 words, clamped to 2…8") {
        try expectEqual(SceneBeatPlanning.beatCount(forTargetWords: 1_500), 5)
        try expectEqual(SceneBeatPlanning.beatCount(forTargetWords: 300), 2)
        try expectEqual(SceneBeatPlanning.beatCount(forTargetWords: 100), 2)
        try expectEqual(SceneBeatPlanning.beatCount(forTargetWords: 9_000), 8)
    }

    // MARK: - buildBeatPlanPrompt

    s.test("buildBeatPlanPrompt names the summary and the requested count") {
        let prompt = SceneBeatPlanning.buildBeatPlanPrompt(
            sceneSummary: "Mara breaks into the vault and is caught.",
            beatCount: 4
        )
        try expectTrue(prompt.contains("Mara breaks into the vault and is caught."))
        try expectTrue(prompt.contains("4"))
    }

    // MARK: - parseBeatPlan

    s.test("parseBeatPlan reads intent lines and splits the word budget evenly") {
        let raw = """
        Mara studies the vault door.
        She picks the lock under pressure.
        The alarm trips and guards close in.
        """
        let beats = SceneBeatPlanning.parseBeatPlan(raw, beatCount: 3, targetWords: 900)
        try expectEqual(beats.count, 3)
        try expectEqual(beats.map(\.index), [0, 1, 2])
        try expectEqual(beats[0].intent, "Mara studies the vault door.")
        try expectEqual(beats.map(\.targetWords).reduce(0, +), 900)
        try expectTrue(beats.allSatisfy { $0.targetWords == 300 })
    }

    s.test("parseBeatPlan distributes a word-budget remainder to the early beats") {
        let raw = "Beat one.\nBeat two.\nBeat three.\nBeat four."
        let beats = SceneBeatPlanning.parseBeatPlan(raw, beatCount: 4, targetWords: 1_000)
        try expectEqual(beats.map(\.targetWords).reduce(0, +), 1_000)
        // 1000 / 4 = 250 each — no remainder here.
        try expectTrue(beats.allSatisfy { $0.targetWords == 250 })

        let odd = SceneBeatPlanning.parseBeatPlan(raw, beatCount: 4, targetWords: 1_002)
        try expectEqual(odd.map(\.targetWords).reduce(0, +), 1_002)
        // remainder 2 → first two beats get the extra word.
        try expectEqual(odd.map(\.targetWords), [251, 251, 250, 250])
    }

    s.test("parseBeatPlan is tolerant of bullets, numbering, and preamble") {
        let raw = """
        Here is the beat plan:
        1. Mara studies the vault door.
        - She picks the lock.
        * The alarm trips.
        """
        let beats = SceneBeatPlanning.parseBeatPlan(raw, beatCount: 3, targetWords: 600)
        try expectEqual(beats.count, 3)
        try expectEqual(beats[0].intent, "Mara studies the vault door.")
        try expectEqual(beats[1].intent, "She picks the lock.")
        try expectEqual(beats[2].intent, "The alarm trips.")
    }

    s.test("parseBeatPlan truncates an over-long model response to the planned count") {
        let raw = "One.\nTwo.\nThree.\nFour.\nFive."
        let beats = SceneBeatPlanning.parseBeatPlan(raw, beatCount: 3, targetWords: 600)
        try expectEqual(beats.count, 3)
    }

    s.test("parseBeatPlan pads a short model response with placeholder beats") {
        let beats = SceneBeatPlanning.parseBeatPlan("Only one beat.", beatCount: 3, targetWords: 600)
        try expectEqual(beats.count, 3)
        try expectEqual(beats[0].intent, "Only one beat.")
        try expectFalse(beats[2].intent.isEmpty, "padded beats still carry a non-empty intent")
        try expectEqual(beats.map(\.targetWords).reduce(0, +), 600)
    }

    return s
}

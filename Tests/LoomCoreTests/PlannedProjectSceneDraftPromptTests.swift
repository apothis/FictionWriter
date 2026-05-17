import Foundation
@testable import LoomCore

/// Planned Project mode — Phase 5.2: the per-beat draft prompt. Each
/// beat of an outline scene is drafted in one writer call; this
/// builder assembles that call's prompt from the scene summary, the
/// planned beat list, the prose written so far, and the project's
/// assigned styles.
func plannedProjectSceneDraftPromptTests() -> TestSuite {
    let s = TestSuite("PlannedProjectSceneDraftPrompt")

    let beats = [
        SceneBeatPlanning.PlannedBeat(index: 0, intent: "Mara studies the vault door.", targetWords: 300),
        SceneBeatPlanning.PlannedBeat(index: 1, intent: "She picks the lock.", targetWords: 300),
        SceneBeatPlanning.PlannedBeat(index: 2, intent: "The alarm trips.", targetWords: 300),
    ]
    let styles = [
        Style(name: "Noir", type: .genre, descriptor: "Rain-slicked cynicism.",
              constraints: ["Keep the narration cynical."]),
        Style(name: "Terse", type: .register, descriptor: "Short sentences.",
              constraints: ["No throat-clearing."]),
    ]

    s.test("the prompt carries the scene summary, the current beat, and its word target") {
        let prompt = SceneDraftPrompt.buildBeatPrompt(
            sceneSummary: "Mara robs the vault and is caught.",
            beats: beats,
            currentBeatIndex: 1,
            priorProse: "Mara stood before the door.",
            styles: []
        )
        try expectTrue(prompt.contains("Mara robs the vault and is caught."))
        try expectTrue(prompt.contains("She picks the lock."))
        try expectTrue(prompt.contains("300"))
    }

    s.test("prior prose is included as already-written context") {
        let prompt = SceneDraftPrompt.buildBeatPrompt(
            sceneSummary: "A scene.",
            beats: beats,
            currentBeatIndex: 1,
            priorProse: "Mara stood before the door, listening.",
            styles: []
        )
        try expectTrue(prompt.contains("Mara stood before the door, listening."))
    }

    s.test("the opening beat is framed as having no prior prose") {
        let prompt = SceneDraftPrompt.buildBeatPrompt(
            sceneSummary: "A scene.",
            beats: beats,
            currentBeatIndex: 0,
            priorProse: "",
            styles: []
        )
        try expectTrue(prompt.lowercased().contains("opening"))
    }

    s.test("the final beat is framed to resolve the scene") {
        let prompt = SceneDraftPrompt.buildBeatPrompt(
            sceneSummary: "A scene.",
            beats: beats,
            currentBeatIndex: 2,
            priorProse: "…",
            styles: []
        )
        try expectTrue(prompt.lowercased().contains("final beat"))
    }

    s.test("assigned styles render into the prompt, genre before register") {
        let prompt = SceneDraftPrompt.buildBeatPrompt(
            sceneSummary: "A scene.",
            beats: beats,
            currentBeatIndex: 0,
            priorProse: "",
            styles: styles
        )
        try expectTrue(prompt.contains("Rain-slicked cynicism."))
        try expectTrue(prompt.contains("No throat-clearing."))
        let genreAt = try expectNotNil(prompt.range(of: "Noir"))
        let registerAt = try expectNotNil(prompt.range(of: "Terse"))
        try expectTrue(genreAt.lowerBound < registerAt.lowerBound)
    }

    s.test("a long prior prose is trimmed to a short tail — early prose is dropped") {
        let early = "ZEBRAMARKER the vault was very old."
        let filler = Array(repeating: "filler", count: 90).joined(separator: " ")
        let late = "QUOKKAMARKER she set her hand to the cold lock."
        let prior = early + " " + filler + " " + late
        let prompt = SceneDraftPrompt.buildBeatPrompt(
            sceneSummary: "A scene.",
            beats: beats,
            currentBeatIndex: 1,
            priorProse: prior,
            styles: []
        )
        try expectFalse(prompt.contains("ZEBRAMARKER"),
                        "the head of a long prior prose must not reach the prompt")
        try expectTrue(prompt.contains("QUOKKAMARKER"),
                       "the tail of the prior prose carries voice continuity")
    }

    s.test("a trimmed prior prose tail is marked as a fragment") {
        let prior = Array(repeating: "word", count: 200).joined(separator: " ")
        let prompt = SceneDraftPrompt.buildBeatPrompt(
            sceneSummary: "A scene.",
            beats: beats,
            currentBeatIndex: 1,
            priorProse: prior,
            styles: []
        )
        try expectTrue(prompt.contains("…"))
    }

    s.test("a short prior prose passes through whole, untrimmed") {
        let prior = "Mara stood before the door, listening for the guard."
        let prompt = SceneDraftPrompt.buildBeatPrompt(
            sceneSummary: "A scene.",
            beats: beats,
            currentBeatIndex: 1,
            priorProse: prior,
            styles: []
        )
        try expectTrue(prompt.contains(prior))
        try expectFalse(prompt.contains("…"))
    }

    s.test("the instruction no longer tells the writer to continue directly from the prior prose") {
        let prompt = SceneDraftPrompt.buildBeatPrompt(
            sceneSummary: "A scene.",
            beats: beats,
            currentBeatIndex: 1,
            priorProse: "Mara stood before the door.",
            styles: []
        )
        try expectFalse(prompt.contains("Continue directly from the prose so far"),
                        "that phrasing invites the writer to restate the prior beat's last line")
    }

    s.test("an out-of-range beat index yields an empty prompt") {
        try expectEqual(
            SceneDraftPrompt.buildBeatPrompt(
                sceneSummary: "A scene.", beats: beats,
                currentBeatIndex: 9, priorProse: "", styles: []
            ),
            ""
        )
    }

    return s
}

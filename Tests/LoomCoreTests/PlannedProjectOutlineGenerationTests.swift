import Foundation
@testable import LoomCore

/// Planned Project mode — Phase 2, Stage 1: turning a premise + sketch
/// into the framework's filled beat slots. LOOM_PLANNED_PROJECT.md §4.
func plannedProjectOutlineGenerationTests() -> TestSuite {
    let s = TestSuite("PlannedProjectOutlineGeneration")
    let framework = SaveTheCatFramework()

    s.test("beat prompt includes the premise, the sketch, and every beat name") {
        let prompt = OutlineGeneration.buildBeatGenerationPrompt(
            premise: "A courier smuggles a memory across a divided city.",
            characterSketch: "Vesna, a courier who never reads what she carries.",
            framework: framework
        )
        try expectTrue(prompt.contains("A courier smuggles a memory"))
        try expectTrue(prompt.contains("Vesna"))
        for beat in framework.beatSlots {
            try expectTrue(prompt.contains(beat.name), "prompt missing beat \(beat.name)")
        }
    }

    s.test("parser decodes a clean one-line-per-beat response in framework order") {
        let raw = framework.beatSlots
            .map { "\($0.name): something happens" }
            .joined(separator: "\n")
        let beats = OutlineGeneration.parseGeneratedBeats(raw, framework: framework)
        try expectEqual(beats.count, 15)
        try expectEqual(beats.map(\.beatName), framework.beatSlots.map(\.name))
        try expectEqual(beats[0].summary, "something happens")
    }

    s.test("parser tolerates leading bullets, numbering, and bold markup") {
        let raw = """
        1. Opening Image: Vesna runs the rooftops at dawn.
        - **Theme Stated**: A stranger says some cargo is worth reading.
        """
        let beats = OutlineGeneration.parseGeneratedBeats(raw, framework: framework)
        try expectEqual(beats.count, 2)
        try expectEqual(beats[0].beatName, "Opening Image")
        try expectEqual(beats[0].summary, "Vesna runs the rooftops at dawn.")
        try expectEqual(beats[1].beatName, "Theme Stated")
    }

    s.test("parser matches beat names case-insensitively, keeping the canonical name") {
        let beats = OutlineGeneration.parseGeneratedBeats(
            "opening image: lower-case beat label", framework: framework
        )
        try expectEqual(beats.count, 1)
        try expectEqual(beats[0].beatName, "Opening Image")
    }

    s.test("parser keeps a summary that itself contains a colon") {
        let beats = OutlineGeneration.parseGeneratedBeats(
            "Catalyst: a message arrives: read me.", framework: framework
        )
        try expectEqual(beats.count, 1)
        try expectEqual(beats[0].summary, "a message arrives: read me.")
    }

    s.test("parser ignores lines that name no known beat") {
        let raw = """
        Here is your outline:
        Opening Image: the real beat.
        Random Thought: not a beat at all.
        """
        let beats = OutlineGeneration.parseGeneratedBeats(raw, framework: framework)
        try expectEqual(beats.count, 1)
        try expectEqual(beats[0].beatName, "Opening Image")
    }

    s.test("parser returns only the beats present, in framework order") {
        let raw = """
        Midpoint: the false victory.
        Catalyst: the inciting message.
        """
        let beats = OutlineGeneration.parseGeneratedBeats(raw, framework: framework)
        try expectEqual(beats.map(\.beatName), ["Catalyst", "Midpoint"])
    }

    // MARK: - Stage 2: chapter map

    func allBeats() -> [OutlineGeneration.GeneratedBeat] {
        framework.beatSlots.map {
            OutlineGeneration.GeneratedBeat(beatName: $0.name, summary: "x")
        }
    }

    s.test("a flat scenario produces a single chapter plan with every beat") {
        let sizing = OutlineSizing.plan(for: .shortStory)  // flat
        let plans = OutlineGeneration.planChapters(beats: allBeats(), sizing: sizing)
        try expectEqual(plans.count, 1)
        try expectEqual(plans[0].beats.count, 15)
        try expectEqual(plans[0].sceneCount, sizing.sceneCount)
    }

    s.test("a chaptered scenario produces one plan per chapter") {
        let sizing = OutlineSizing.plan(for: .novella)
        let plans = OutlineGeneration.planChapters(beats: allBeats(), sizing: sizing)
        try expectEqual(plans.count, sizing.chapterCount)
    }

    s.test("every beat is assigned to exactly one chapter, in order") {
        let sizing = OutlineSizing.plan(for: .novel)
        let plans = OutlineGeneration.planChapters(beats: allBeats(), sizing: sizing)
        try expectEqual(plans.flatMap { $0.beats }, allBeats())
    }

    s.test("scene counts across chapters sum to the sizing total") {
        let sizing = OutlineSizing.plan(for: .novel)
        let plans = OutlineGeneration.planChapters(beats: allBeats(), sizing: sizing)
        try expectEqual(plans.map(\.sceneCount).reduce(0, +), sizing.sceneCount)
    }

    s.test("beats and scenes are distributed near-evenly across chapters") {
        let sizing = OutlineSizing.plan(for: .novella)
        let plans = OutlineGeneration.planChapters(beats: allBeats(), sizing: sizing)
        let beatCounts = plans.map { $0.beats.count }
        let sceneCounts = plans.map(\.sceneCount)
        try expectTrue(beatCounts.max()! - beatCounts.min()! <= 1)
        try expectTrue(sceneCounts.max()! - sceneCounts.min()! <= 1)
    }

    return s
}

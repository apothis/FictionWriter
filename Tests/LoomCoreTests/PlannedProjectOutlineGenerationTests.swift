import Foundation
@testable import LoomCore

/// Planned Project mode — Phase 2, Stage 1: turning a premise + sketch
/// into the framework's filled beat slots. LOOM_PLANNED_PROJECT.md §4.
func plannedProjectOutlineGenerationTests() -> TestSuite {
    let s = TestSuite("PlannedProjectOutlineGeneration")
    let framework = SaveTheCatFramework()

    /// Deferred-stub provider (per feedback_tdd_async_callbacks): the
    /// stub queues completions; the test flushes them in waves so the
    /// Stage 1 → Stage 3 hand-off happens as it would over real HTTP.
    final class OutlineStubProvider: OllamaCallProvider {
        var queued: [(Result<String, OllamaError>) -> Void] = []
        var canned: [Result<String, OllamaError>] = []
        var callCount = 0
        func call(
            prompt: String, schema: [String: Any], options: OllamaChatOptions,
            completion: @escaping (Result<String, OllamaError>) -> Void
        ) {
            callCount += 1
            queued.append(completion)
        }
        func flushAll() {
            while !queued.isEmpty, !canned.isEmpty {
                queued.removeFirst()(canned.removeFirst())
            }
        }
    }

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

    // MARK: - Stage 3: scene generation

    func chapterPlan(scenes: Int) -> OutlineGeneration.ChapterPlan {
        OutlineGeneration.ChapterPlan(
            beats: [OutlineGeneration.GeneratedBeat(
                beatName: "Catalyst", summary: "a message arrives"
            )],
            sceneCount: scenes
        )
    }

    s.test("scene prompt names the premise, the chapter's beats, and the scene count") {
        let prompt = OutlineGeneration.buildSceneGenerationPrompt(
            chapter: chapterPlan(scenes: 3),
            premise: "A courier smuggles a memory.",
            characterSketch: "Vesna, a courier."
        )
        try expectTrue(prompt.contains("A courier smuggles a memory"))
        try expectTrue(prompt.contains("a message arrives"))
        try expectTrue(prompt.contains("3"))
    }

    s.test("scene prompt insists on full beat coverage through to the last beat") {
        // When a chapter has more beats than scenes the model tends to
        // front-load and drop the ending — the prompt must require the
        // final scene to land the chapter's last beat.
        let prompt = OutlineGeneration.buildSceneGenerationPrompt(
            chapter: chapterPlan(scenes: 3),
            premise: "x", characterSketch: "y"
        )
        try expectTrue(prompt.contains("the final scene must reach the chapter's last beat"))
    }

    s.test("scene parser decodes clean title | summary lines") {
        let raw = """
        The Rooftop Run | Vesna sprints a delivery and is ambushed.
        The Stranger | A stranger says the cargo is worth reading.
        """
        let scenes = OutlineGeneration.parseGeneratedScenes(raw)
        try expectEqual(scenes.count, 2)
        try expectEqual(scenes[0].title, "The Rooftop Run")
        try expectEqual(scenes[0].summary, "Vesna sprints a delivery and is ambushed.")
    }

    s.test("scene parser tolerates numbering and bold markup on the title") {
        let scenes = OutlineGeneration.parseGeneratedScenes(
            "1. **The Rooftop Run** | Vesna runs the rooftops."
        )
        try expectEqual(scenes.count, 1)
        try expectEqual(scenes[0].title, "The Rooftop Run")
    }

    s.test("scene parser skips a line with no separator or an empty field") {
        let raw = """
        A line with no bar at all.
        The Real Scene | something happens.
        | missing title
        Missing Summary |
        """
        let scenes = OutlineGeneration.parseGeneratedScenes(raw)
        try expectEqual(scenes.count, 1)
        try expectEqual(scenes[0].title, "The Real Scene")
    }

    // MARK: - Stage 4: assembly + orchestrator

    s.test("reconcileScenes pads short, truncates long, keeps exact") {
        let two = [
            OutlineGeneration.SceneOutline(title: "A", summary: "a"),
            OutlineGeneration.SceneOutline(title: "B", summary: "b"),
        ]
        try expectEqual(OutlineGeneration.reconcileScenes(two, target: 2).count, 2)
        try expectEqual(OutlineGeneration.reconcileScenes(two, target: 4).count, 4)
        try expectEqual(OutlineGeneration.reconcileScenes(two, target: 1).count, 1)
    }

    s.test("a flat outline puts every scene in orphanedSceneIds, status todo") {
        let sizing = OutlineSizing.plan(for: .shortStory)
        let plan = OutlineGeneration.ChapterPlan(
            beats: allBeats(), sceneCount: sizing.sceneCount
        )
        let scenes = (0..<sizing.sceneCount).map {
            OutlineGeneration.SceneOutline(title: "S\($0)", summary: "x")
        }
        let outline = OutlineGeneration.assembleOutline(
            plans: [plan], scenesPerChapter: [scenes], sizing: sizing
        )
        try expectEqual(outline.manuscript.parts.count, 0)
        try expectEqual(outline.manuscript.orphanedSceneIds.count, sizing.sceneCount)
        try expectEqual(outline.scenes.count, sizing.sceneCount)
        try expectTrue(outline.scenes.allSatisfy { $0.status == .todo })
    }

    s.test("a chaptered outline builds one Part of chapters with the right scene total") {
        let sizing = OutlineSizing.plan(for: .novella)
        let plans = OutlineGeneration.planChapters(beats: allBeats(), sizing: sizing)
        let scenesPerChapter = plans.map { plan in
            (0..<plan.sceneCount).map {
                OutlineGeneration.SceneOutline(title: "S\($0)", summary: "x")
            }
        }
        let outline = OutlineGeneration.assembleOutline(
            plans: plans, scenesPerChapter: scenesPerChapter, sizing: sizing
        )
        try expectEqual(outline.manuscript.parts.count, 1)
        try expectEqual(outline.manuscript.parts[0].chapters.count, sizing.chapterCount)
        try expectEqual(outline.scenes.count, sizing.sceneCount)
    }

    func beatResponse() -> String {
        framework.beatSlots.map { "\($0.name): \($0.name) happens" }
            .joined(separator: "\n")
    }

    s.test("OutlineGenerator runs Stage 1 then per-chapter Stage 3 to an outline") {
        let stub = OutlineStubProvider()
        let gen = OutlineGenerator(provider: stub)
        var captured: Result<OutlineGeneration.GeneratedOutline, Error>?
        gen.generate(
            premise: "A courier smuggles a memory.",
            characterSketch: "Vesna, a courier.",
            lengthScenario: .shortStory,
            framework: framework
        ) { captured = $0 }

        try expectEqual(stub.queued.count, 1)  // Stage 1 only, so far
        stub.canned = [
            .success(beatResponse()),
            .success("A | a\nB | b\nC | c"),
        ]
        stub.flushAll()

        let result = try expectNotNil(captured)
        guard case .success(let outline) = result else {
            throw TestFailure(message: "expected success", file: #file, line: #line)
        }
        try expectEqual(outline.scenes.count, 3)
        try expectEqual(stub.callCount, 2)
    }

    s.test("OutlineGenerator surfaces a Stage 1 failure") {
        let stub = OutlineStubProvider()
        let gen = OutlineGenerator(provider: stub)
        var captured: Result<OutlineGeneration.GeneratedOutline, Error>?
        gen.generate(
            premise: "x", characterSketch: "y",
            lengthScenario: .shortStory, framework: framework
        ) { captured = $0 }
        stub.canned = [.failure(OllamaError.unexpectedShape)]
        stub.flushAll()
        let result = try expectNotNil(captured)
        if case .success = result {
            throw TestFailure(message: "expected failure", file: #file, line: #line)
        }
    }

    s.test("OutlineGenerator fans out one Stage 3 call per chapter") {
        let stub = OutlineStubProvider()
        let gen = OutlineGenerator(provider: stub)
        gen.generate(
            premise: "x", characterSketch: "y",
            lengthScenario: .novella, framework: framework
        ) { _ in }
        try expectEqual(stub.queued.count, 1)
        stub.canned = [.success(beatResponse())]
            + Array(repeating: .success("S | s"), count: 5)
        stub.flushAll()
        try expectEqual(stub.callCount, 6)  // 1 beat + 5 chapter calls
    }

    return s
}

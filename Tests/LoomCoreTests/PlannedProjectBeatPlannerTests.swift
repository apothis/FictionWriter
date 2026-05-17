import Foundation
@testable import LoomCore

/// Planned Project mode — Phase 5.1: the async beat-planning pass.
/// `SceneBeatPlanner` runs one LLM call over a scene's summary and
/// turns the response into the deterministic-budget beat list the
/// per-beat draft loop consumes.
func plannedProjectBeatPlannerTests() -> TestSuite {
    let s = TestSuite("PlannedProjectBeatPlanner")

    /// Deferred-stub provider (per feedback_tdd_async_callbacks): the
    /// completion is stored and flushed by the test, never invoked
    /// synchronously inside `call`.
    final class StubProvider: OllamaCallProvider {
        var pending: ((Result<String, OllamaError>) -> Void)?
        var lastPrompt = ""
        func call(
            prompt: String, schema: [String: Any], options: OllamaChatOptions,
            completion: @escaping (Result<String, OllamaError>) -> Void
        ) {
            lastPrompt = prompt
            pending = completion
        }
        func flush(_ result: Result<String, OllamaError>) {
            let p = pending
            pending = nil
            p?(result)
        }
    }

    s.test("planBeats prompts with the summary and yields the parsed beats") {
        let stub = StubProvider()
        let planner = SceneBeatPlanner(provider: stub)
        var got: [SceneBeatPlanning.PlannedBeat]?
        planner.planBeats(
            sceneSummary: "Mara breaks into the vault and is caught.",
            targetWordCount: 900
        ) { result in
            if case .success(let beats) = result { got = beats }
        }
        try expectTrue(stub.lastPrompt.contains("Mara breaks into the vault"))
        try expectNil(got)

        stub.flush(.success("She studies the door.\nShe picks the lock.\nThe alarm trips."))
        let beats = try expectNotNil(got)
        try expectEqual(beats.count, 3)
        try expectEqual(beats[0].intent, "She studies the door.")
        try expectEqual(beats.map(\.targetWords).reduce(0, +), 900)
    }

    s.test("planBeats propagates a provider failure") {
        let stub = StubProvider()
        let planner = SceneBeatPlanner(provider: stub)
        var failed = false
        planner.planBeats(sceneSummary: "A scene.", targetWordCount: 600) { result in
            if case .failure = result { failed = true }
        }
        stub.flush(.failure(.transport("server unreachable")))
        try expectTrue(failed)
    }

    s.test("planBeats completes even after the planner's scope has closed") {
        let stub = StubProvider()
        var got: [SceneBeatPlanning.PlannedBeat]?
        do {
            let planner = SceneBeatPlanner(provider: stub)
            planner.planBeats(sceneSummary: "A scene.", targetWordCount: 600) { result in
                if case .success(let beats) = result { got = beats }
            }
        }
        stub.flush(.success("One.\nTwo."))
        try expectNotNil(got)
    }

    return s
}

import Foundation
@testable import LoomCore

/// Planned Project mode — Phase 5.2: `OutlineDraftCoordinator`. Drafts
/// an outline scene end-to-end: one beat-planning LLM pass over the
/// scene's summary, then one writer call per planned beat, the prose
/// accumulated and written back to the scene with the status advanced
/// `todo → draft`.
func plannedProjectOutlineDraftCoordinatorTests() -> TestSuite {
    let s = TestSuite("PlannedProjectOutlineDraftCoordinator")

    /// Deferred-stub provider (per feedback_tdd_async_callbacks): the
    /// stub queues completions and the test flushes them in waves, so
    /// the plan → beat → beat hand-off happens as it would over HTTP.
    final class StubProvider: OllamaCallProvider {
        var queued: [(Result<String, OllamaError>) -> Void] = []
        var canned: [Result<String, OllamaError>] = []
        var prompts: [String] = []
        func call(
            prompt: String, schema: [String: Any], options: OllamaChatOptions,
            completion: @escaping (Result<String, OllamaError>) -> Void
        ) {
            prompts.append(prompt)
            queued.append(completion)
        }
        func flushAll() {
            while !queued.isEmpty, !canned.isEmpty {
                queued.removeFirst()(canned.removeFirst())
            }
        }
    }

    func sceneSession() -> (ProjectSession, UUID) {
        let session = ProjectSession(project: Project(title: "T"), url: nil)
        let scene = session.addScene()
        session.setSceneSummary(id: scene.id, to: "Mara robs the vault and is caught.")
        session.setSceneTargetWordCount(id: scene.id, to: 600)  // beatCount(600) == 2
        session.setSceneStatus(id: scene.id, to: .todo)
        return (session, scene.id)
    }

    s.test("drafts a scene: plan pass then per-beat calls, prose written, status → draft") {
        let (session, sceneId) = sceneSession()
        let provider = StubProvider()
        let coord = OutlineDraftCoordinator(session: session, provider: provider)

        var finishedSceneId: UUID?
        let obs = NotificationCenter.default.addObserver(
            forName: OutlineDraftCoordinator.didFinishNotification,
            object: coord, queue: nil
        ) { note in finishedSceneId = note.userInfo?["sceneId"] as? UUID }
        defer { NotificationCenter.default.removeObserver(obs) }

        coord.start(sceneId: sceneId)
        // Wave 1 — the beat-planning pass resolves.
        provider.canned = [.success("Mara studies the door.\nThe alarm trips.")]
        provider.flushAll()
        // Wave 2 — the two per-beat writer calls resolve.
        provider.canned = [
            .success("Mara studied the vault door, every nerve alight."),
            .success("The alarm shrieked. Boots in the corridor."),
        ]
        provider.flushAll()

        try expectEqual(finishedSceneId, sceneId)
        let scene = try expectNotNil(session.scenes[sceneId])
        try expectEqual(scene.status, .draft)
        try expectTrue(scene.prose.contains("every nerve alight"))
        try expectTrue(scene.prose.contains("Boots in the corridor."))
        try expectFalse(coord.isGenerating)
    }

    s.test("the per-beat prompts carry the planned beat intents") {
        let (session, sceneId) = sceneSession()
        let provider = StubProvider()
        let coord = OutlineDraftCoordinator(session: session, provider: provider)
        coord.start(sceneId: sceneId)
        provider.canned = [.success("Mara studies the door.\nThe alarm trips.")]
        provider.flushAll()
        provider.canned = [.success("prose one"), .success("prose two")]
        provider.flushAll()
        // prompts[0] is the plan pass; prompts[1..] are the beat calls.
        try expectTrue(provider.prompts.count >= 3)
        try expectTrue(provider.prompts[1].contains("Mara studies the door."))
        try expectTrue(provider.prompts[2].contains("The alarm trips."))
    }

    s.test("a planning-pass failure leaves the scene untouched") {
        let (session, sceneId) = sceneSession()
        let provider = StubProvider()
        let coord = OutlineDraftCoordinator(session: session, provider: provider)

        var finished = false
        let obs = NotificationCenter.default.addObserver(
            forName: OutlineDraftCoordinator.didFinishNotification,
            object: coord, queue: nil
        ) { _ in finished = true }
        defer { NotificationCenter.default.removeObserver(obs) }

        coord.start(sceneId: sceneId)
        provider.canned = [.failure(.transport("server unreachable"))]
        provider.flushAll()

        try expectTrue(finished)
        let scene = try expectNotNil(session.scenes[sceneId])
        try expectEqual(scene.status, .todo)
        try expectTrue(scene.prose.isEmpty)
        try expectFalse(coord.isGenerating)
    }

    return s
}

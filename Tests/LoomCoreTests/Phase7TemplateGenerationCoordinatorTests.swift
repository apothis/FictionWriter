import Foundation
@testable import LoomCore

/// Phase 7.b.4 — `TemplateGenerationCoordinator` per-beat loop.
///
/// Stateful coordinator: kicks off M sequential writer calls
/// (one per beat in the skeleton), accumulates the generated prose,
/// emits each beat as a single `didEmitToken` event (so the editor's
/// existing token-inserter can consume the stream verbatim without
/// new wiring), supports cancellation mid-scene, and retries empty
/// outputs once with a sampler tweak (punchlist item 3).
///
/// Tests use deferred-completion stubs per
/// [`feedback_tdd_async_callbacks`](memory/feedback_tdd_async_callbacks.md).
func phase7TemplateGenerationCoordinatorTests() -> TestSuite {
    let s = TestSuite("Phase7TemplateGenerationCoordinator")

    func makeTempProject() -> URL {
        // Do NOT pre-create — ProjectStorage.createNewProject creates
        // the directory itself and throws `directoryAlreadyExists`
        // if it's already there.
        FileManager.default.temporaryDirectory
            .appendingPathComponent("loom-tg-test-\(UUID().uuidString)")
    }

    /// Build a project on disk with one template scene + its
    /// skeleton sidecar. Returns (projectURL, templateId).
    func bootstrap(beatCount: Int = 3) throws -> (URL, UUID) {
        let projectURL = makeTempProject()
        let storage = ProjectStorage()
        let project = try storage.createNewProject(at: projectURL, title: "T", author: nil)
        try storage.saveProject(project, at: projectURL)
        let template = TemplateScene(
            id: UUID(), name: "Test template",
            body: "Source prose. " + String(repeating: "Sentence. ", count: 30)
        )
        try TemplateSceneStorage.saveTemplate(template, in: projectURL)
        var beats: [SceneBeat] = []
        for i in 0..<beatCount {
            beats.append(SceneBeat(
                index: i, summary: "{PROTAGONIST} does beat \(i).",
                modality: .action, function: i == 0 ? .setup : (i == beatCount - 1 ? .exit : .escalation),
                targetWords: 50, wordRangeStart: i * 50, wordRangeEnd: (i + 1) * 50,
                beatTensionChange: 1
            ))
        }
        let skeleton = ExtractedSceneSkeleton(
            beats: beats, sourceCharacters: ["Mara"],
            sourceSettingMarkers: ["room"]
        )
        try TemplateSceneStorage.saveSkeleton(skeleton, for: template.id, in: projectURL)
        return (projectURL, template.id)
    }

    /// Stub KoboldGenerating with snapshot-then-clear-then-fire
    /// deferral. `responses` is consumed in order; the stub records
    /// each generate(...) call's prompt for assertion.
    final class StubWriter: KoboldGenerating {
        var capturedPrompts: [String] = []
        var capturedSamplers: [SamplerParams] = []
        var responses: [Result<String, Error>]
        private var pending: [(Result<String, Error>, (Result<String, Error>) -> Void)] = []
        private(set) var cancelCalled = false

        init(responses: [Result<String, Error>]) { self.responses = responses }

        func generate(
            prompt: String,
            stopSequences: [String],
            params: SamplerParams,
            maxContextLength: Int,
            completion: @escaping (Result<String, Error>) -> Void
        ) {
            capturedPrompts.append(prompt)
            capturedSamplers.append(params)
            let r = responses.isEmpty
                ? .failure(NSError(domain: "stub", code: -1))
                : responses.removeFirst()
            pending.append((r, completion))
        }

        func flush() {
            let snapshot = pending
            pending.removeAll()
            for (r, c) in snapshot { c(r) }
        }
    }

    // MARK: - Happy path

    s.test("Coordinator runs M beats sequentially, accumulating prose") {
        let (projectURL, templateId) = try bootstrap(beatCount: 3)
        defer { try? FileManager.default.removeItem(at: projectURL) }

        let session = ProjectSession(project: Project(title: "T"), url: projectURL)
        _ = session.addScene()
        let stub = StubWriter(responses: [
            .success("Beat zero prose."),
            .success("Beat one prose."),
            .success("Beat two prose."),
        ])
        let coord = TemplateGenerationCoordinator(
            session: session,
            writerResolver: { _ in stub }
        )

        var emittedTokens: [String] = []
        let tokenObs = NotificationCenter.default.addObserver(
            forName: TemplateGenerationCoordinator.didEmitTokenNotification,
            object: coord, queue: nil
        ) { note in
            if let t = note.userInfo?["token"] as? String { emittedTokens.append(t) }
        }
        defer { NotificationCenter.default.removeObserver(tokenObs) }
        var finished = false
        let finishObs = NotificationCenter.default.addObserver(
            forName: TemplateGenerationCoordinator.didFinishNotification,
            object: coord, queue: nil
        ) { _ in finished = true }
        defer { NotificationCenter.default.removeObserver(finishObs) }

        coord.start(templateId: templateId, castMapping: "Maya is protagonist", cursorOffset: 0)
        // The coordinator kicks off the first beat synchronously
        // (or near-synchronously); flush drains it + advances loop.
        for _ in 0..<3 { stub.flush() }

        // Streaming: token count is N×beats + (N-1) inter-beat
        // separators rather than 1-per-beat. Assert on the joined
        // sequence — that's the actual behavioural contract.
        let joined = emittedTokens.joined()
        try expectTrue(joined.contains("Beat zero prose"))
        try expectTrue(joined.contains("Beat one prose"))
        try expectTrue(joined.contains("Beat two prose"))
        // And the inter-beat separator landed between adjacent beats.
        try expectTrue(joined.contains("prose.\n\nBeat one"))
        try expectTrue(joined.contains("prose.\n\nBeat two"))
        try expectTrue(finished)
        try expectEqual(coord.isGenerating, false)
        // Per-beat prompts include current beat index hints.
        try expectEqual(stub.capturedPrompts.count, 3)
        try expectTrue(stub.capturedPrompts[0].contains("Write beat 0"))
        try expectTrue(stub.capturedPrompts[1].contains("Write beat 1"))
        try expectTrue(stub.capturedPrompts[2].contains("Write beat 2"))
    }

    // MARK: - Cancellation

    s.test("Coordinator.cancel during a beat aborts further beats") {
        let (projectURL, templateId) = try bootstrap(beatCount: 5)
        defer { try? FileManager.default.removeItem(at: projectURL) }
        let session = ProjectSession(project: Project(title: "T"), url: projectURL)
        _ = session.addScene()
        let stub = StubWriter(responses: [
            .success("Beat zero."), .success("Beat one."),
            .success("Beat two."), .success("Beat three."), .success("Beat four."),
        ])
        let coord = TemplateGenerationCoordinator(
            session: session,
            writerResolver: { _ in stub }
        )

        coord.start(templateId: templateId, castMapping: "x", cursorOffset: 0)
        stub.flush()  // beat 0 completes
        stub.flush()  // beat 1 completes
        coord.cancel()
        stub.flush()  // beat 2 was in-flight; completes after cancel
        stub.flush()  // would-be beat 3 — should NOT fire
        try expectEqual(coord.isGenerating, false)
        // The writer should have been called at most 3 times: beats
        // 0, 1, 2 (in-flight when cancel landed). Beats 3 + 4 must
        // never start.
        try expectTrue(stub.capturedPrompts.count <= 3)
        try expectTrue(stub.responses.count >= 2)  // beat 3 + 4 untouched
    }

    // MARK: - Retry on empty output (punchlist item 3)

    s.test("Coordinator retries-on-empty once with sampler tweak") {
        let (projectURL, templateId) = try bootstrap(beatCount: 2)
        defer { try? FileManager.default.removeItem(at: projectURL) }
        let session = ProjectSession(project: Project(title: "T"), url: projectURL)
        _ = session.addScene()
        // Beat 0: empty (triggers retry), then valid. Beat 1: valid.
        let stub = StubWriter(responses: [
            .success(""),                       // beat 0 first attempt — empty
            .success("Beat zero retry prose."), // beat 0 retry — succeeds
            .success("Beat one prose."),        // beat 1 first attempt — succeeds
        ])
        let coord = TemplateGenerationCoordinator(
            session: session,
            writerResolver: { _ in stub }
        )

        var emittedTokens: [String] = []
        let tokenObs = NotificationCenter.default.addObserver(
            forName: TemplateGenerationCoordinator.didEmitTokenNotification,
            object: coord, queue: nil
        ) { note in
            if let t = note.userInfo?["token"] as? String { emittedTokens.append(t) }
        }
        defer { NotificationCenter.default.removeObserver(tokenObs) }

        coord.start(templateId: templateId, castMapping: "x", cursorOffset: 0)
        for _ in 0..<4 { stub.flush() }

        // Writer called 3 times total: beat 0 empty + beat 0 retry + beat 1.
        try expectEqual(stub.capturedPrompts.count, 3)
        // Streaming: assert on the joined sequence — the retry should
        // not double-emit the inter-beat separator (would produce
        // "...retry prose.\n\n\n\nBeat one..." instead of one \n\n).
        let joined = emittedTokens.joined()
        try expectTrue(joined.contains("retry prose"))
        try expectTrue(joined.contains("Beat one prose"))
        try expectFalse(joined.contains("\n\n\n\n"), "inter-beat separator should not double on retry")
        try expectTrue(joined.contains("retry prose.\n\nBeat one"),
            "exactly one \\n\\n between beats; got: \(joined)")
    }

    s.test("Coordinator gives up after one empty retry and continues to next beat") {
        let (projectURL, templateId) = try bootstrap(beatCount: 2)
        defer { try? FileManager.default.removeItem(at: projectURL) }
        let session = ProjectSession(project: Project(title: "T"), url: projectURL)
        _ = session.addScene()
        // Beat 0: empty x2 (both attempts fail). Beat 1: valid.
        let stub = StubWriter(responses: [
            .success(""), .success(""),
            .success("Beat one survived."),
        ])
        let coord = TemplateGenerationCoordinator(
            session: session,
            writerResolver: { _ in stub }
        )

        var finished = false
        let finishObs = NotificationCenter.default.addObserver(
            forName: TemplateGenerationCoordinator.didFinishNotification,
            object: coord, queue: nil
        ) { _ in finished = true }
        defer { NotificationCenter.default.removeObserver(finishObs) }

        coord.start(templateId: templateId, castMapping: "x", cursorOffset: 0)
        for _ in 0..<5 { stub.flush() }
        // Writer called 3 times (beat 0 attempt + retry + beat 1).
        try expectEqual(stub.capturedPrompts.count, 3)
        try expectTrue(finished)
    }

    // MARK: - Stop sequences (punchlist item 2)

    s.test("Coordinator stop sequences do NOT include lone `[` prefix (post-§7.a.2)") {
        let (projectURL, templateId) = try bootstrap(beatCount: 1)
        defer { try? FileManager.default.removeItem(at: projectURL) }
        let session = ProjectSession(project: Project(title: "T"), url: projectURL)
        _ = session.addScene()
        let stub = StubWriter(responses: [.success("ok")])
        let coord = TemplateGenerationCoordinator(
            session: session,
            writerResolver: { _ in stub }
        )
        coord.start(templateId: templateId, castMapping: "x", cursorOffset: 0)
        stub.flush()
        // The actual stop sequences passed are recorded in a separate
        // property — assert they don't include a bare `[` (which
        // catches `[silence]` openings per §7.a.2 finding).
        try expectFalse(coord.lastStopSequences.contains("["))
        // Longer markers starting with `===` are fine to keep (won't
        // false-positive on prose that opens with a bracket).
        // Smoke-test finding: the writer hallucinates "[END BEAT N
        // PROSE]" markers at the end of the last beat. Stop on the
        // "[END" prefix so the artifact doesn't leak into the
        // editor; this is narrower than a bare "[" so legitimate
        // dialogue-tag-like prose ("[he leaned in]") still streams.
        try expectTrue(coord.lastStopSequences.contains("[END"),
            "expected [END as a stop marker; got: \(coord.lastStopSequences)")
        try expectTrue(coord.lastStopSequences.contains(where: { $0.hasPrefix("===") }))
    }

    // MARK: - Early-exit invariants

    s.test("Coordinator.start no-ops when template id is stale") {
        let projectURL = makeTempProject()
        defer { try? FileManager.default.removeItem(at: projectURL) }
        let session = ProjectSession(project: Project(title: "T"), url: projectURL)
        _ = session.addScene()
        let stub = StubWriter(responses: [])
        let coord = TemplateGenerationCoordinator(
            session: session,
            writerResolver: { _ in stub }
        )
        coord.start(templateId: UUID(), castMapping: "x", cursorOffset: 0)
        try expectEqual(coord.isGenerating, false)
        try expectEqual(stub.capturedPrompts.count, 0)
    }

    // Per-beat streaming: previously TemplateGenerationCoordinator
    // called the non-streaming `generate(...)` overload and emitted
    // each completed beat as one large `didEmitToken` event — the
    // user saw ~100-word chunks appear all at once. Switch to the
    // streaming `generate(..., onToken:, completion:)` overload and
    // forward every token chunk straight to `didEmitToken` so the
    // editor renders character-by-character like the normal
    // GenerationCoordinator path.
    final class StreamingStubWriter: KoboldGenerating {
        let streamedTokens: [String]
        let finalError: Error?
        private var pending: [() -> Void] = []

        init(streamedTokens: [String], finalError: Error? = nil) {
            self.streamedTokens = streamedTokens
            self.finalError = finalError
        }

        func generate(
            prompt: String, stopSequences: [String],
            params: SamplerParams, maxContextLength: Int,
            completion: @escaping (Result<String, Error>) -> Void
        ) {
            // Should not be called when streaming overload is used —
            // fallback path; deliver the whole concatenation in one shot.
            let full = streamedTokens.joined()
            pending.append { [self] in
                if let err = finalError { completion(.failure(err)) }
                else { completion(.success(full)) }
            }
        }

        func generate(
            prompt: String, stopSequences: [String],
            params: SamplerParams, maxContextLength: Int,
            onToken: @escaping (String) -> Void,
            completion: @escaping (Result<String, Error>) -> Void
        ) {
            pending.append { [self] in
                for tok in streamedTokens { onToken(tok) }
                if let err = finalError { completion(.failure(err)) }
                else { completion(.success(streamedTokens.joined())) }
            }
        }

        func flush() {
            let snapshot = pending
            pending.removeAll()
            for f in snapshot { f() }
        }
    }

    s.test("Coordinator forwards every streamed token as didEmitToken (not one chunk per beat)") {
        let (projectURL, templateId) = try bootstrap(beatCount: 1)
        defer { try? FileManager.default.removeItem(at: projectURL) }
        let session = ProjectSession(project: Project(title: "T"), url: projectURL)
        _ = session.addScene()
        let stub = StreamingStubWriter(
            streamedTokens: ["Hello", " ", "world", " ", "today."]
        )
        let coord = TemplateGenerationCoordinator(
            session: session,
            writerResolver: { _ in stub }
        )

        var emittedTokens: [String] = []
        let obs = NotificationCenter.default.addObserver(
            forName: TemplateGenerationCoordinator.didEmitTokenNotification,
            object: coord, queue: nil
        ) { note in
            if let t = note.userInfo?["token"] as? String { emittedTokens.append(t) }
        }
        defer { NotificationCenter.default.removeObserver(obs) }

        coord.start(templateId: templateId, castMapping: "x", cursorOffset: 0)
        for _ in 0..<3 { stub.flush() }

        // Five streamed tokens → five didEmitToken events. The old
        // behaviour would have produced one event with the joined
        // string ("Hello world today.").
        try expectEqual(emittedTokens, ["Hello", " ", "world", " ", "today."])
    }

    // Bug from Phase 7 smoke testing: TemplateGenerationCoordinator
    // resolved the writer profile from `session.project.settings.
    // serverProfileId` directly, with no fallback when the project
    // had no override (typical for newly-created projects). The
    // KoboldClientRegistry then returned its localhost sentinel and
    // beat 0 failed with `Could not connect to the server`. Mirror
    // GenerationCoordinator's `?? appDefault` chain so the project-
    // level override is optional rather than required.
    s.test("Coordinator falls back to app default when project has no serverProfileId") {
        let (projectURL, templateId) = try bootstrap(beatCount: 1)
        defer { try? FileManager.default.removeItem(at: projectURL) }
        let session = ProjectSession(project: Project(title: "T"), url: projectURL)
        _ = session.addScene()
        // session.project.settings.serverProfileId is nil by default.
        let appDefaultId = UUID()
        var capturedProfileId: UUID? = nil
        var capturedCount = 0
        let stub = StubWriter(responses: [.success("beat zero")])
        let coord = TemplateGenerationCoordinator(
            session: session,
            writerResolver: { id in
                capturedProfileId = id
                capturedCount += 1
                return stub
            },
            appDefaultProfileIdProvider: { appDefaultId }
        )
        coord.start(templateId: templateId, castMapping: "x", cursorOffset: 0)
        stub.flush()
        try expectEqual(capturedCount, 1)
        try expectEqual(capturedProfileId, appDefaultId)
    }

    s.test("Coordinator prefers project-level serverProfileId over app default") {
        let (projectURL, templateId) = try bootstrap(beatCount: 1)
        defer { try? FileManager.default.removeItem(at: projectURL) }
        var project = Project(title: "T")
        let projectId = UUID()
        project.settings.serverProfileId = projectId
        let session = ProjectSession(project: project, url: projectURL)
        _ = session.addScene()
        let appDefaultId = UUID()
        var capturedProfileId: UUID? = nil
        let stub = StubWriter(responses: [.success("beat zero")])
        let coord = TemplateGenerationCoordinator(
            session: session,
            writerResolver: { id in
                capturedProfileId = id
                return stub
            },
            appDefaultProfileIdProvider: { appDefaultId }
        )
        coord.start(templateId: templateId, castMapping: "x", cursorOffset: 0)
        stub.flush()
        try expectEqual(capturedProfileId, projectId)
    }

    s.test("Coordinator.start no-ops when project has no current scene") {
        let (projectURL, templateId) = try bootstrap(beatCount: 1)
        defer { try? FileManager.default.removeItem(at: projectURL) }
        let session = ProjectSession(project: Project(title: "T"), url: projectURL)
        // Deliberately don't addScene — currentSceneId stays nil.
        let stub = StubWriter(responses: [.success("x")])
        let coord = TemplateGenerationCoordinator(
            session: session,
            writerResolver: { _ in stub }
        )
        coord.start(templateId: templateId, castMapping: "x", cursorOffset: 0)
        try expectEqual(coord.isGenerating, false)
        try expectEqual(stub.capturedPrompts.count, 0)
    }

    return s
}

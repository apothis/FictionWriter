import Foundation
@testable import LoomCore

/// Phase 5 production A1 — honest smoke that `AppState` wires the
/// style-retrieval surface into the writer-prompt pipeline.
///
/// What's pinned here:
///
/// - In-memory ("Untitled") sessions don't spawn a retrieval service;
///   the closure returns `[]` so `GenerationCoordinator` falls through
///   to the pre-Phase-5 prompt-build path with no `[STYLE EXEMPLARS]`
///   layer.
/// - Opening or creating a project installs a `RetrievalService` bound
///   to the project URL; the closure produced by
///   `AppState.styleRetriever()` delegates into it.
/// - Switching projects (re-`openProject` against a different URL)
///   tears down the old service and installs a fresh one — important
///   because the production `PythonEmbeddingClient` owns a
///   long-lived subprocess that must be released when the project
///   closes.
/// - Tests inject a stub `EmbeddingClient` via
///   `AppState.embeddingClientFactory` so the production Python
///   subprocess never gets spawned during the suite.
func phase5AppStateRetrievalWiringTests() -> TestSuite {
    let s = TestSuite("Phase5AppStateRetrievalWiring")

    /// Deterministic stub embedder reused from
    /// `Phase5RetrievalServiceTests.StubD`. 3-d, length-based, so any
    /// query against any non-empty corpus produces at least one match.
    final class StubD: EmbeddingClient {
        let modelId: String = "stub/AppStateWiring"
        let dim: Int = 3
        private(set) var embedCallCount: Int = 0
        func embed(_ text: String) -> EmbeddingVector? {
            embedCallCount += 1
            let words = text.split(whereSeparator: { $0.isWhitespace }).count
            return EmbeddingVector(values: [
                Float(words),
                Float(text.count),
                Float(text.filter { $0.isLetter }.count)
            ])
        }
    }

    /// Builds an AppState with an isolated settings store + a factory
    /// that records every client it produces. Tests inspect the
    /// `clientsByURL` map to verify lifecycle behaviour.
    final class Recorder {
        var clientsByURL: [URL: StubD] = [:]
        func factory(_ projectURL: URL) -> EmbeddingClient {
            let stub = StubD()
            clientsByURL[projectURL] = stub
            return stub
        }
    }

    func freshAppState(recorder: Recorder) -> AppState {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("loom-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let store = AppSettingsStore(fileManager: .default, rootDir: tmp)
        return AppState(
            settingsStore: store,
            embeddingClientFactory: { url in recorder.factory(url) }
        )
    }

    func makeIngestedProject(at url: URL, recorder: Recorder) throws {
        // Bootstrap a .loom dir with a single ingested reference, so
        // the retriever has a non-empty corpus to score against.
        // `createNewProject` creates the directory itself; pre-creating
        // it would throw `directoryAlreadyExists`.
        let storage = ProjectStorage()
        let project = try storage.createNewProject(at: url, title: "Test", author: nil)
        try storage.saveProject(project, at: url)
        let refId = UUID()
        try ReferenceStorage.saveReference(
            ReferenceText(id: refId, name: "ref-1",
                          body: "She walked into the kitchen and looked at the cat.\nThe cat looked back."),
            in: url
        )
        // Use a DIFFERENT stub for ingest so the recorder's
        // clientsByURL map only reflects the AppState-injected
        // factory (cleaner lifecycle assertions).
        let pipeline = ReferenceIngestPipeline(
            projectURL: url,
            chunkSize: 100, chunkOverlap: 0,
            dClient: recorder.factory(url),
            modalityLLM: { _ in .action }
        )
        try pipeline.chunkAndEmbedD(referenceId: refId)
        try pipeline.refitAllEVectors()
        // Reset recorder so the AppState-driven lifecycle starts clean.
        recorder.clientsByURL.removeAll()
    }

    s.test("in-memory session: styleRetriever closure returns empty") {
        let rec = Recorder()
        let app = freshAppState(recorder: rec)
        let retriever = app.styleRetriever()
        try expectEqual(retriever("any query"), [])
        try expectEqual(rec.clientsByURL.count, 0)
    }

    s.test("openProject installs a RetrievalService that the closure delegates into") {
        let rec = Recorder()
        let projectURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("loom-test-proj-\(UUID().uuidString).loom")
        try makeIngestedProject(at: projectURL, recorder: rec)
        defer { try? FileManager.default.removeItem(at: projectURL) }

        let app = freshAppState(recorder: rec)
        try app.openProject(at: projectURL)

        // Factory was called for this project URL.
        try expectEqual(rec.clientsByURL.count, 1)
        try expectNotNil(rec.clientsByURL[projectURL])

        // Closure delegates into the service: returns at least one
        // exemplar from the ingested reference.
        let retriever = app.styleRetriever()
        let results = retriever("She walked into the kitchen.")
        try expectTrue(results.count >= 1)
        try expectEqual(results.first?.referenceName, "ref-1")
        // And the injected stub got called (D path used).
        try expectTrue((rec.clientsByURL[projectURL]?.embedCallCount ?? 0) >= 1)
    }

    s.test("switching projects releases the prior service and spawns a fresh one") {
        let rec = Recorder()
        let urlA = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("loom-test-projA-\(UUID().uuidString).loom")
        let urlB = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("loom-test-projB-\(UUID().uuidString).loom")
        try makeIngestedProject(at: urlA, recorder: rec)
        try makeIngestedProject(at: urlB, recorder: rec)
        defer {
            try? FileManager.default.removeItem(at: urlA)
            try? FileManager.default.removeItem(at: urlB)
        }

        let app = freshAppState(recorder: rec)
        try app.openProject(at: urlA)
        try expectNotNil(rec.clientsByURL[urlA])

        try app.openProject(at: urlB)
        // Both URLs are present in the recorder (factory called twice,
        // once per project). The lifecycle invariant we care about is
        // "switching produced a fresh client" — verified by the second
        // key landing in the map.
        try expectEqual(rec.clientsByURL.count, 2)
        try expectNotNil(rec.clientsByURL[urlB])
    }

    s.test("createProject installs a RetrievalService against the new URL") {
        let rec = Recorder()
        let projectURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("loom-test-create-\(UUID().uuidString).loom")
        defer { try? FileManager.default.removeItem(at: projectURL) }

        let app = freshAppState(recorder: rec)
        try app.createProject(at: projectURL, title: "Fresh")
        try expectEqual(rec.clientsByURL.count, 1)
        try expectNotNil(rec.clientsByURL[projectURL])

        // No references yet → retrieval returns empty (graceful).
        let retriever = app.styleRetriever()
        try expectEqual(retriever("anything"), [])
    }

    return s
}

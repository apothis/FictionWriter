import Foundation
@testable import LoomCore

// Phase 8.b.4 — `TemplateGenerationCoordinator` accepts a
// `styleRetriever` closure. The coordinator calls it once per beat
// with a query produced by `BeatRetrievalQuery.build`, and forwards
// the returned exemplars to `BeatGeneration.buildBeatPrompt` so the
// `[STYLE EXEMPLARS]` block lands in each writer call.

private final class CapturingWriter: KoboldGenerating {
    var capturedPrompts: [String] = []
    var responses: [Result<String, Error>]
    private var pending: [(Result<String, Error>, (Result<String, Error>) -> Void)] = []

    init(_ responses: [Result<String, Error>]) { self.responses = responses }

    func generate(
        prompt: String,
        stopSequences: [String],
        params: SamplerParams,
        maxContextLength: Int,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        capturedPrompts.append(prompt)
        let r = responses.isEmpty
            ? .failure(NSError(domain: "stub", code: -1))
            : responses.removeFirst()
        pending.append((r, completion))
    }
    func flush() {
        let snapshot = pending; pending.removeAll()
        for (r, c) in snapshot { c(r) }
    }
}

private func bootstrap(beatCount: Int = 2) throws -> (URL, UUID) {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("loom-tg8-\(UUID().uuidString)")
    let storage = ProjectStorage()
    let project = try storage.createNewProject(at: url, title: "T", author: nil)
    try storage.saveProject(project, at: url)
    let template = TemplateScene(
        id: UUID(), name: "T",
        body: "Source. " + String(repeating: "Sentence. ", count: 30)
    )
    try TemplateSceneStorage.saveTemplate(template, in: url)
    var beats: [SceneBeat] = []
    for i in 0..<beatCount {
        beats.append(SceneBeat(
            index: i, summary: "{PROTAGONIST} does beat \(i).",
            modality: .action, function: i == 0 ? .setup : .exit,
            targetWords: 50, wordRangeStart: i * 50, wordRangeEnd: (i + 1) * 50,
            beatTensionChange: 0
        ))
    }
    let skel = ExtractedSceneSkeleton(
        beats: beats, sourceCharacters: ["Mara"], sourceSettingMarkers: []
    )
    try TemplateSceneStorage.saveSkeleton(skel, for: template.id, in: url)
    return (url, template.id)
}

private func makeExemplar(_ text: String, name: String) -> StyleExemplar {
    StyleExemplar(
        referenceId: UUID(), referenceName: name, chunkIndex: 0,
        text: text, modality: .action, rrfScore: 1.0
    )
}

func phase8TemplateGenStyleRetrievalTests() -> TestSuite {
    let s = TestSuite("Phase8TemplateGenStyleRetrieval")

    s.test("default styleRetriever=nil preserves Phase 7 behaviour (no [STYLE EXEMPLARS] block)") {
        let (projectURL, templateId) = try bootstrap(beatCount: 2)
        defer { try? FileManager.default.removeItem(at: projectURL) }
        let session = ProjectSession(project: Project(title: "T"), url: projectURL)
        _ = session.addScene()
        let writer = CapturingWriter([.success("beat0."), .success("beat1.")])
        let coord = TemplateGenerationCoordinator(
            session: session, writerResolver: { _ in writer }
        )
        coord.start(templateId: templateId, castMapping: "Maya", cursorOffset: 0)
        writer.flush(); writer.flush()
        try expectEqual(writer.capturedPrompts.count, 2)
        for prompt in writer.capturedPrompts {
            try expectFalse(prompt.contains("[STYLE EXEMPLARS]"))
        }
    }

    s.test("styleRetriever set: called per beat; results land in each prompt") {
        let (projectURL, templateId) = try bootstrap(beatCount: 2)
        defer { try? FileManager.default.removeItem(at: projectURL) }
        let session = ProjectSession(project: Project(title: "T"), url: projectURL)
        _ = session.addScene()
        let writer = CapturingWriter([.success("beat0."), .success("beat1.")])

        var capturedQueries: [String] = []
        let coord = TemplateGenerationCoordinator(
            session: session,
            writerResolver: { _ in writer },
            styleRetriever: { query in
                capturedQueries.append(query)
                // Return a beat-index-specific exemplar so the test
                // can verify per-beat invocation, not just per-scene.
                let n = capturedQueries.count
                return [makeExemplar("Retrieved chunk #\(n).", name: "ref\(n)")]
            }
        )
        coord.start(templateId: templateId, castMapping: "Maya", cursorOffset: 0)
        writer.flush(); writer.flush()

        // Two beats → two retriever calls (per-beat, per D5 lock).
        try expectEqual(capturedQueries.count, 2)
        // Each query includes the beat summary + cast.
        try expectTrue(capturedQueries[0].contains("does beat 0"))
        try expectTrue(capturedQueries[0].contains("Maya"))
        try expectTrue(capturedQueries[1].contains("does beat 1"))

        // Each prompt includes the [STYLE EXEMPLARS] block with the
        // beat-specific retrieved chunk.
        try expectEqual(writer.capturedPrompts.count, 2)
        try expectTrue(writer.capturedPrompts[0].contains("[STYLE EXEMPLARS]"))
        try expectTrue(writer.capturedPrompts[0].contains("Retrieved chunk #1."))
        try expectTrue(writer.capturedPrompts[1].contains("Retrieved chunk #2."))
        // Beat 1's prompt should NOT carry beat 0's exemplar (per-beat,
        // not per-scene).
        try expectFalse(writer.capturedPrompts[1].contains("Retrieved chunk #1."))
    }

    s.test("styleRetriever returning empty array: [STYLE EXEMPLARS] block is omitted") {
        let (projectURL, templateId) = try bootstrap(beatCount: 1)
        defer { try? FileManager.default.removeItem(at: projectURL) }
        let session = ProjectSession(project: Project(title: "T"), url: projectURL)
        _ = session.addScene()
        let writer = CapturingWriter([.success("beat0.")])
        let coord = TemplateGenerationCoordinator(
            session: session, writerResolver: { _ in writer },
            styleRetriever: { _ in [] }
        )
        coord.start(templateId: templateId, castMapping: "Maya", cursorOffset: 0)
        writer.flush()
        try expectEqual(writer.capturedPrompts.count, 1)
        try expectFalse(writer.capturedPrompts[0].contains("[STYLE EXEMPLARS]"))
    }

    return s
}

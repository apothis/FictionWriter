import Foundation
@testable import LoomCore

/// Phase 7.b followup — generation-log entry for template gens.
///
/// `GenerationCoordinator` writes a `GenerationLogEntry` to
/// `<project>/generation-log/<ts>.json` on finish (the History tab
/// reads from there for the "what was sent / what came back"
/// disclosure). `TemplateGenerationCoordinator` previously did NOT —
/// observability gap closed here.
///
/// Mode stays as `.continueProse` (least-wrong existing case for
/// "wrote prose into the scene") rather than churning every
/// `switch mode` site to add a new enum case. A new optional
/// `templateGenerationInfo: TemplateGenerationInfo?` field on
/// `GenerationLogEntry` carries the template-specific metadata
/// (template id + name, cast mapping, beat count + modality
/// sequence, voice descriptor) so the History tab can later be
/// extended to render template gens distinctively.
func phase7TemplateGenLogTests() -> TestSuite {
    let s = TestSuite("Phase7TemplateGenLog")

    func makeTempProject() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("loom-tg-log-test-\(UUID().uuidString)")
    }

    func bootstrap(beatCount: Int = 2) throws -> (URL, UUID, ProjectSession) {
        let projectURL = makeTempProject()
        let storage = ProjectStorage()
        let project = try storage.createNewProject(at: projectURL, title: "T", author: nil)
        try storage.saveProject(project, at: projectURL)
        let session = ProjectSession(project: project, url: projectURL)
        _ = session.addScene()
        let template = TemplateScene(
            id: UUID(), name: "Doorway test",
            body: "Source prose. " + String(repeating: "Sentence. ", count: 20)
        )
        try TemplateSceneStorage.saveTemplate(template, in: projectURL)
        var beats: [SceneBeat] = []
        for i in 0..<beatCount {
            beats.append(SceneBeat(
                index: i, summary: "{PROTAGONIST} does beat \(i).",
                modality: i % 2 == 0 ? .action : .dialogue,
                function: i == 0 ? .setup : (i == beatCount - 1 ? .exit : .escalation),
                targetWords: 50, wordRangeStart: i * 50, wordRangeEnd: (i + 1) * 50,
                beatTensionChange: 1
            ))
        }
        let voice = VoiceDescriptor(
            sentenceCadence: .shortClipped,
            dialogueDensity: .balanced,
            rhetoricalFlourish: .minimal,
            register: "noir minimalism",
            distinctiveTechniques: ["bare attribution tags"]
        )
        let skeleton = ExtractedSceneSkeleton(
            beats: beats, sourceCharacters: ["Mara"],
            sourceSettingMarkers: ["doorway"],
            voiceDescriptor: voice
        )
        try TemplateSceneStorage.saveSkeleton(skeleton, for: template.id, in: projectURL)
        return (projectURL, template.id, session)
    }

    /// Same deferred-completion stub used elsewhere in this suite.
    final class StubWriter: KoboldGenerating {
        var responses: [Result<String, Error>]
        private var pending: [(Result<String, Error>, (Result<String, Error>) -> Void)] = []
        init(responses: [Result<String, Error>]) { self.responses = responses }
        func generate(
            prompt: String, stopSequences: [String], params: SamplerParams,
            maxContextLength: Int,
            completion: @escaping (Result<String, Error>) -> Void
        ) {
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

    // MARK: - TemplateGenerationInfo + log-entry field

    s.test("GenerationLogEntry round-trips with optional templateGenerationInfo") {
        let info = TemplateGenerationInfo(
            templateId: UUID(),
            templateName: "Hemingway test",
            castMapping: "Maya is the protagonist",
            beatCount: 3,
            beatModalitySequence: ["action", "dialogue", "action"],
            voiceDescriptor: nil
        )
        let entry = GenerationLogEntry(
            sceneId: UUID(),
            mode: .continueProse,
            promptAssembly: PromptAssembly(
                contextChiclets: [], fullPrompt: "x", promptTokens: 0,
                aboveCacheTokens: 0, belowCacheTokens: 0, evictedLayers: [],
                template: .raw
            ),
            response: GenerationResponse(rawText: "y", completionTokens: 1, elapsedMs: 10),
            templateGenerationInfo: info
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(GenerationLogEntry.self, from: data)
        try expectEqual(decoded.templateGenerationInfo?.templateId, info.templateId)
        try expectEqual(decoded.templateGenerationInfo?.beatCount, 3)
    }

    s.test("GenerationLogEntry decodes legacy entries without templateGenerationInfo") {
        // Phase 1+ entries on disk pre-Phase-7 must still load.
        let legacy = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "sceneId": "22222222-2222-2222-2222-222222222222",
          "timestamp": "2026-01-01T00:00:00.000Z",
          "mode": "continueProse",
          "promptAssembly": {
            "contextChiclets": [],
            "fullPrompt": "old prompt",
            "promptTokens": 0,
            "aboveCacheTokens": 0,
            "belowCacheTokens": 0,
            "evictedLayers": [],
            "template": "raw"
          },
          "response": {
            "rawText": "old response",
            "completionTokens": 1,
            "refusalDetected": false,
            "elapsedMs": 10
          }
        }
        """
        let entry = try JSONDecoder.loom.decode(
            GenerationLogEntry.self, from: legacy.data(using: .utf8)!
        )
        try expectTrue(entry.templateGenerationInfo == nil)
        try expectEqual(entry.response.rawText, "old response")
    }

    // MARK: - TemplateGenerationCoordinator writes log on successful finish

    s.test("TemplateGenerationCoordinator writes a GenerationLogEntry on finish") {
        let (projectURL, templateId, session) = try bootstrap(beatCount: 2)
        defer { try? FileManager.default.removeItem(at: projectURL) }

        let stub = StubWriter(responses: [.success("Beat zero prose."), .success("Beat one prose.")])
        let coord = TemplateGenerationCoordinator(
            session: session,
            writerResolver: { _ in stub }
        )

        var loggedEntry: GenerationLogEntry?
        let logObs = NotificationCenter.default.addObserver(
            forName: TemplateGenerationCoordinator.didWriteLogEntryNotification,
            object: coord, queue: nil
        ) { note in
            loggedEntry = note.userInfo?["entry"] as? GenerationLogEntry
        }
        defer { NotificationCenter.default.removeObserver(logObs) }

        coord.start(templateId: templateId, castMapping: "Maya is protagonist", cursorOffset: 0)
        for _ in 0..<3 { stub.flush() }

        try expectNotNil(loggedEntry)
        try expectEqual(loggedEntry?.mode, .continueProse)
        // Template metadata captured.
        try expectNotNil(loggedEntry?.templateGenerationInfo)
        try expectEqual(loggedEntry?.templateGenerationInfo?.templateId, templateId)
        try expectEqual(loggedEntry?.templateGenerationInfo?.beatCount, 2)
        try expectEqual(loggedEntry?.templateGenerationInfo?.castMapping, "Maya is protagonist")
        // Voice descriptor preserved.
        try expectEqual(
            loggedEntry?.templateGenerationInfo?.voiceDescriptor?.register,
            "noir minimalism"
        )
        // Response text is the accumulated insertedText.
        try expectTrue(loggedEntry?.response.rawText.contains("Beat zero prose") == true)
        try expectTrue(loggedEntry?.response.rawText.contains("Beat one prose") == true)
    }

    s.test("TemplateGenerationCoordinator does NOT log on cancel before any beat completes") {
        let (projectURL, templateId, session) = try bootstrap(beatCount: 3)
        defer { try? FileManager.default.removeItem(at: projectURL) }
        let stub = StubWriter(responses: [.success("ok"), .success("ok"), .success("ok")])
        let coord = TemplateGenerationCoordinator(
            session: session, writerResolver: { _ in stub }
        )

        var loggedEntry: GenerationLogEntry?
        let logObs = NotificationCenter.default.addObserver(
            forName: TemplateGenerationCoordinator.didWriteLogEntryNotification,
            object: coord, queue: nil
        ) { note in
            loggedEntry = note.userInfo?["entry"] as? GenerationLogEntry
        }
        defer { NotificationCenter.default.removeObserver(logObs) }

        coord.start(templateId: templateId, castMapping: "x", cursorOffset: 0)
        coord.cancel()
        for _ in 0..<3 { stub.flush() }

        // Cancelled before any prose accumulated → no log written.
        // (If at least one beat completed before cancel, a partial log
        // IS expected — but in this test cancel lands before the first
        // beat's completion is flushed.)
        try expectTrue(loggedEntry == nil)
    }

    return s
}

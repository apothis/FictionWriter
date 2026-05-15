import Foundation
@testable import LoomCore

// Phase 8.b.x — `TemplateGenerationCoordinator` runs each completed
// beat's output through `BeatOutputSanitizer.strip` before it
// becomes the `priorBeatsProse` for subsequent beats. This is the
// cascade-breaking guarantee: even if one beat hallucinates a
// `[VALIDATE BEAT]` block, beats N+1 onward see the SANITIZED prior
// prose and don't learn the pattern. The coordinator also posts a
// notification describing the deletion so the editor can drop the
// hallucinated rubbish from the visible text view.

private final class LeakWriter: KoboldGenerating {
    var capturedPrompts: [String] = []
    var streamingOutputs: [String]
    private var pending: [(String, (String) -> Void, (Result<String, Error>) -> Void)] = []

    init(_ outputs: [String]) { self.streamingOutputs = outputs }

    func generate(
        prompt: String,
        stopSequences: [String],
        params: SamplerParams,
        maxContextLength: Int,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        capturedPrompts.append(prompt)
        let out = streamingOutputs.isEmpty ? "" : streamingOutputs.removeFirst()
        pending.append((out, { _ in }, completion))
    }
    func generate(
        prompt: String,
        stopSequences: [String],
        params: SamplerParams,
        maxContextLength: Int,
        onToken: @escaping (String) -> Void,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        capturedPrompts.append(prompt)
        let out = streamingOutputs.isEmpty ? "" : streamingOutputs.removeFirst()
        pending.append((out, onToken, completion))
    }
    func flush() {
        let snap = pending; pending.removeAll()
        for (out, onToken, completion) in snap {
            // Stream the whole output as one chunk (simulates a fast
            // model; the coordinator's per-token logic doesn't care
            // about chunk granularity).
            onToken(out)
            completion(.success(out))
        }
    }
}

private func bootstrap(beatCount: Int) throws -> (URL, UUID) {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("loom-tg-sanitize-\(UUID().uuidString)")
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
            index: i, summary: "{PROTAGONIST} beat \(i).",
            modality: .action, function: i == 0 ? .setup : .exit,
            targetWords: 50, wordRangeStart: i * 50, wordRangeEnd: (i + 1) * 50,
            beatTensionChange: 0
        ))
    }
    let skel = ExtractedSceneSkeleton(
        beats: beats, sourceCharacters: [], sourceSettingMarkers: []
    )
    try TemplateSceneStorage.saveSkeleton(skel, for: template.id, in: url)
    return (url, template.id)
}

/// Slice out the `[BEATS BEFORE THIS — already generated, do not
/// regenerate]\n...` section's body from a per-beat prompt, ending
/// at the next blank-line block boundary. Returns nil if the marker
/// isn't found.
private func extractPriorBeatsSection(_ prompt: String) -> String? {
    let markerLine = "[BEATS BEFORE THIS"
    guard let markerRange = prompt.range(of: markerLine) else { return nil }
    // Skip to the end of the marker line.
    guard let lineEnd = prompt.range(of: "\n", range: markerRange.upperBound..<prompt.endIndex) else {
        return nil
    }
    // Section runs until the next "\n\n" boundary (blank-line separator).
    let bodyStart = lineEnd.upperBound
    if let nextBoundary = prompt.range(of: "\n\n", range: bodyStart..<prompt.endIndex) {
        return String(prompt[bodyStart..<nextBoundary.lowerBound])
    }
    return String(prompt[bodyStart...])
}

func phase8TemplateGenSanitizeTests() -> TestSuite {
    let s = TestSuite("Phase8TemplateGenSanitize")

    s.test("insertedText is sanitized after each beat — subsequent beats see clean prior prose") {
        let (projectURL, templateId) = try bootstrap(beatCount: 3)
        defer { try? FileManager.default.removeItem(at: projectURL) }
        let session = ProjectSession(project: Project(title: "T"), url: projectURL)
        _ = session.addScene()
        let writer = LeakWriter([
            // Beat 0 hallucinates a [VALIDATE BEAT] meta-block at the tail.
            """
            Clean beat zero prose.



            [VALIDATE BEAT]
            Length check: 30 words.
            """,
            // Beat 1: clean prose. After beat 0 is sanitized, beat 1's
            // priorBeatsProse should NOT contain the meta-block.
            "Clean beat one prose.",
            "Clean beat two prose.",
        ])
        let coord = TemplateGenerationCoordinator(
            session: session, writerResolver: { _ in writer }
        )
        coord.start(templateId: templateId, castMapping: "x", cursorOffset: 0)
        writer.flush()  // beat 0
        writer.flush()  // beat 1
        writer.flush()  // beat 2

        // Beat 1's captured prompt: priorBeatsProse should contain
        // beat 0's clean prose but NOT the meta-block. Extract just
        // the [BEATS BEFORE THIS — already generated] section, since
        // the SYSTEM framing now legitimately mentions `[VALIDATE
        // BEAT]` etc. as forbidden patterns.
        try expectTrue(writer.capturedPrompts.count >= 2)
        let beat1Prompt = writer.capturedPrompts[1]
        guard let priorSection = extractPriorBeatsSection(beat1Prompt) else {
            throw TestFailure(
                message: "could not find [BEATS BEFORE THIS] section in beat 1 prompt",
                file: #file, line: #line
            )
        }
        try expectTrue(priorSection.contains("Clean beat zero prose"))
        try expectFalse(priorSection.contains("[VALIDATE BEAT]"),
                       "cascade broken: subsequent beats must not see hallucinated meta-blocks in prior-prose; got:\n\(priorSection)")
        try expectFalse(priorSection.contains("Length check:"))
    }

    s.test("excess blank lines in beat output collapse before subsequent beats see them") {
        let (projectURL, templateId) = try bootstrap(beatCount: 2)
        defer { try? FileManager.default.removeItem(at: projectURL) }
        let session = ProjectSession(project: Project(title: "T"), url: projectURL)
        _ = session.addScene()
        let writer = LeakWriter([
            "Beat zero ends.\n\n\n\n\n\n",  // six trailing newlines
            "Beat one.",
        ])
        let coord = TemplateGenerationCoordinator(
            session: session, writerResolver: { _ in writer }
        )
        coord.start(templateId: templateId, castMapping: "x", cursorOffset: 0)
        writer.flush()
        // After sanitization beat 0 should be trimmed to "Beat zero
        // ends." then the intentional inter-beat "\n\n" separator
        // is appended → insertedText = "Beat zero ends.\n\n". No
        // triple-newline run survives the sanitizer's (c) collapse +
        // (d) trim, even though the writer emitted six trailing
        // newlines.
        try expectFalse(coord.insertedText.contains("\n\n\n"),
                       "expected no triple-newline run in insertedText after sanitization; got: '\(coord.insertedText)'")
        // Sanitizer trimmed all of the writer's trailing whitespace
        // and the coordinator added exactly one "\n\n" separator.
        try expectEqual(coord.insertedText, "Beat zero ends.\n\n")
    }

    s.test("posts didSanitizeBeatNotification with the deletion delta") {
        let (projectURL, templateId) = try bootstrap(beatCount: 1)
        defer { try? FileManager.default.removeItem(at: projectURL) }
        let session = ProjectSession(project: Project(title: "T"), url: projectURL)
        _ = session.addScene()
        let writer = LeakWriter([
            "Good prose.\n\n[VALIDATE BEAT]\nLength check: 5 words.",
        ])
        let coord = TemplateGenerationCoordinator(
            session: session, writerResolver: { _ in writer }
        )
        var observed: [(beatIndex: Int, deleteCount: Int)] = []
        let obs = NotificationCenter.default.addObserver(
            forName: TemplateGenerationCoordinator.didSanitizeBeatNotification,
            object: coord, queue: nil
        ) { note in
            if let beat = note.userInfo?["beatIndex"] as? Int,
               let count = note.userInfo?["deleteCount"] as? Int {
                observed.append((beat, count))
            }
        }
        defer { NotificationCenter.default.removeObserver(obs) }

        coord.start(templateId: templateId, castMapping: "x", cursorOffset: 0)
        writer.flush()

        try expectEqual(observed.count, 1)
        try expectEqual(observed[0].beatIndex, 0)
        try expectGreaterThan(observed[0].deleteCount, 0)
    }

    s.test("clean output emits no didSanitizeBeatNotification") {
        let (projectURL, templateId) = try bootstrap(beatCount: 1)
        defer { try? FileManager.default.removeItem(at: projectURL) }
        let session = ProjectSession(project: Project(title: "T"), url: projectURL)
        _ = session.addScene()
        let writer = LeakWriter(["Just clean prose, no rubbish."])
        let coord = TemplateGenerationCoordinator(
            session: session, writerResolver: { _ in writer }
        )
        var observedCount = 0
        let obs = NotificationCenter.default.addObserver(
            forName: TemplateGenerationCoordinator.didSanitizeBeatNotification,
            object: coord, queue: nil
        ) { _ in observedCount += 1 }
        defer { NotificationCenter.default.removeObserver(obs) }

        coord.start(templateId: templateId, castMapping: "x", cursorOffset: 0)
        writer.flush()

        try expectEqual(observedCount, 0)
    }

    return s
}

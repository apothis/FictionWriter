import Foundation
@testable import LoomCore

/// Continuity Audit (L10) — Phase B, the engine orchestrator. Wires
/// extract → ground → retrieve → adjudicate → knowledge-check →
/// assemble → store, end to end. Stub-smoke tested: deferred-completion
/// stubs (per the async-callback TDD memory) drained by a `drive`
/// helper that pumps the recursive stepping to completion.
func continuityAuditEngineTests() -> TestSuite {
    let s = TestSuite("ContinuityAuditEngine")

    struct StubError: Error {}

    final class StubExtractor: ContinuityClaimExtracting {
        var claimsByScene: [String: [ContinuityAudit.Claim]] = [:]
        var failScenes: Set<String> = []
        private var pending: [(String, (Result<[ContinuityAudit.Claim], Error>) -> Void)] = []
        var hasPending: Bool { !pending.isEmpty }
        func extract(
            scenePose: String, sceneId: String,
            completion: @escaping (Result<[ContinuityAudit.Claim], Error>) -> Void
        ) { pending.append((sceneId, completion)) }
        func drain() {
            let p = pending; pending = []
            for (sid, c) in p {
                if failScenes.contains(sid) { c(.failure(StubError())) }
                else { c(.success(claimsByScene[sid] ?? [])) }
            }
        }
    }

    final class StubAdjProvider: OllamaCallProvider {
        var responder: (String) -> Result<String, OllamaError> = { _ in .success("") }
        private var pending: [(String, (Result<String, OllamaError>) -> Void)] = []
        var hasPending: Bool { !pending.isEmpty }
        func call(
            prompt: String, schema: [String: Any], options: OllamaChatOptions,
            completion: @escaping (Result<String, OllamaError>) -> Void
        ) { pending.append((prompt, completion)) }
        func drain() {
            let p = pending; pending = []
            for (pr, c) in p { c(responder(pr)) }
        }
    }

    func drive(_ ext: StubExtractor, _ adj: StubAdjProvider) {
        while ext.hasPending || adj.hasPending { ext.drain(); adj.drain() }
    }

    // A synchronous embedder — `vectorFor` maps each text to a vector;
    // texts mapped to the same vector are cosine-identical.
    final class StubEmbedder: KoboldEmbedding {
        var vectorFor: (String) -> [Float] = { _ in [Float](repeating: 1, count: 8) }
        func embed(texts: [String], completion: @escaping (Result<[[Float]], Error>) -> Void) {
            completion(.success(texts.map(vectorFor)))
        }
    }
    func onehot(_ i: Int) -> [Float] {
        var v = [Float](repeating: 0, count: 8); v[i] = 1; return v
    }

    func tempProject() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("loom-cae-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func attr(_ subject: String, _ value: String, scene: String) -> ContinuityAudit.Claim {
        ContinuityAudit.Claim(
            type: .attribute, subject: subject, attributeKey: "eye colour", value: value,
            sourceSceneId: scene, source: .narration, evidenceQuote: "q")
    }

    let contradictionJSON = #"{"verdict":"contradiction","confidence":0.9,"explanation":"conflict"}"#
    let consistentJSON = #"{"verdict":"consistent","confidence":0.9,"explanation":"fine"}"#

    let scenes = [
        ContinuityAuditEngine.SceneInput(id: "s1", prose: "Scene one."),
        ContinuityAuditEngine.SceneInput(id: "s2", prose: "Scene two."),
    ]

    s.test("an adjudicated attribute conflict becomes a stored finding") {
        let ext = StubExtractor()
        ext.claimsByScene = [
            "s1": [attr("Mara", "green eyes", scene: "s1")],
            "s2": [attr("Mara", "brown eyes", scene: "s2")],
        ]
        let adj = StubAdjProvider()
        adj.responder = { _ in .success(contradictionJSON) }
        let engine = ContinuityAuditEngine(extractor: ext, adjudicationProvider: adj, entities: [])
        let project = tempProject()
        var result: Result<[ContinuityFinding], Error>?
        engine.audit(scenes: scenes, projectURL: project) { result = $0 }
        drive(ext, adj)
        let findings = try expectNotNil(try result?.get())
        try expectEqual(findings.count, 1)
        try expectEqual(findings[0].kind, .attributeDrift)
        try expectEqual(ContinuityAuditStore.load(in: project)?.findings.count, 1)
    }

    s.test("a consistent verdict yields no finding") {
        let ext = StubExtractor()
        ext.claimsByScene = [
            "s1": [attr("Mara", "green eyes", scene: "s1")],
            "s2": [attr("Mara", "green-ish eyes", scene: "s2")],
        ]
        let adj = StubAdjProvider()
        adj.responder = { _ in .success(consistentJSON) }
        let engine = ContinuityAuditEngine(extractor: ext, adjudicationProvider: adj, entities: [])
        var result: Result<[ContinuityFinding], Error>?
        engine.audit(scenes: scenes, projectURL: tempProject()) { result = $0 }
        drive(ext, adj)
        try expectEqual(try result?.get().count, 0)
    }

    func knowledgeClaims() -> [String: [ContinuityAudit.Claim]] {
        [
            "s1": [ContinuityAudit.Claim(
                type: .knowledgeState, subject: "Mara", attributeKey: "", value: "Mara knows SECRET",
                sourceSceneId: "s1", source: .dialogue, evidenceQuote: "q")],
            "s2": [ContinuityAudit.Claim(
                type: .event, subject: "x", attributeKey: "", value: "SECRET is revealed",
                sourceSceneId: "s2", source: .narration, evidenceQuote: "q")],
        ]
    }
    let secretSimilarity: (String, String) -> Double = { a, b in
        a.contains("SECRET") && b.contains("SECRET") ? 1.0 : 0.0
    }

    s.test("a knowledge candidate the adjudicator confirms becomes a finding") {
        let ext = StubExtractor()
        ext.claimsByScene = knowledgeClaims()
        let adj = StubAdjProvider()
        adj.responder = { _ in .success(contradictionJSON) }
        let engine = ContinuityAuditEngine(
            extractor: ext, adjudicationProvider: adj, entities: [], similarity: secretSimilarity)
        var result: Result<[ContinuityFinding], Error>?
        engine.audit(scenes: scenes, projectURL: tempProject()) { result = $0 }
        drive(ext, adj)
        let findings = try expectNotNil(try result?.get())
        try expectEqual(findings.count, 1)
        try expectEqual(findings[0].kind, .knowledgeViolation)
    }

    s.test("a knowledge candidate the adjudicator rejects produces no finding") {
        let ext = StubExtractor()
        ext.claimsByScene = knowledgeClaims()
        let adj = StubAdjProvider()
        adj.responder = { _ in .success(consistentJSON) }   // the FP-rejection path
        let engine = ContinuityAuditEngine(
            extractor: ext, adjudicationProvider: adj, entities: [], similarity: secretSimilarity)
        var result: Result<[ContinuityFinding], Error>?
        engine.audit(scenes: scenes, projectURL: tempProject()) { result = $0 }
        drive(ext, adj)
        try expectEqual(try result?.get().count, 0)
    }

    s.test("a scene whose extraction fails is skipped — the audit still completes") {
        let ext = StubExtractor()
        ext.failScenes = ["s2"]
        ext.claimsByScene = [
            "s1": [attr("Mara", "green eyes", scene: "s1")],
            "s3": [attr("Mara", "brown eyes", scene: "s3")],
        ]
        let adj = StubAdjProvider()
        adj.responder = { _ in .success(contradictionJSON) }
        let threeScenes = scenes + [ContinuityAuditEngine.SceneInput(id: "s3", prose: "Scene three.")]
        let engine = ContinuityAuditEngine(extractor: ext, adjudicationProvider: adj, entities: [])
        var result: Result<[ContinuityFinding], Error>?
        engine.audit(scenes: threeScenes, projectURL: tempProject()) { result = $0 }
        drive(ext, adj)
        try expectEqual(try result?.get().count, 1)
    }

    s.test("a pair whose adjudication fails is skipped — the audit still completes") {
        let ext = StubExtractor()
        ext.claimsByScene = [
            "s1": [attr("Mara", "green eyes", scene: "s1")],
            "s2": [attr("Mara", "brown eyes", scene: "s2")],
        ]
        let adj = StubAdjProvider()
        adj.responder = { _ in .failure(.transport("boom")) }
        let engine = ContinuityAuditEngine(extractor: ext, adjudicationProvider: adj, entities: [])
        var result: Result<[ContinuityFinding], Error>?
        engine.audit(scenes: scenes, projectURL: tempProject()) { result = $0 }
        drive(ext, adj)
        try expectEqual(try result?.get().count, 0)
    }

    s.test("with an embedder, a duplicate claim is deduped before retrieval") {
        let ext = StubExtractor()
        ext.claimsByScene = [
            "s1": [attr("Mara", "green eyes A", scene: "s1"),
                   attr("Mara", "green eyes B", scene: "s1")],
            "s2": [attr("Mara", "brown eyes", scene: "s2")],
        ]
        let adj = StubAdjProvider()
        adj.responder = { _ in .success(contradictionJSON) }
        let embedder = StubEmbedder()
        embedder.vectorFor = { $0.contains("green") ? onehot(0) : onehot(1) }
        let engine = ContinuityAuditEngine(
            extractor: ext, adjudicationProvider: adj, entities: [], embedder: embedder)
        var result: Result<[ContinuityFinding], Error>?
        engine.audit(scenes: scenes, projectURL: tempProject()) { result = $0 }
        drive(ext, adj)
        // The two paraphrase green claims collapse to one → one
        // candidate pair → one finding (without dedup it would be two).
        try expectEqual(try result?.get().count, 1)
    }

    s.test("with an embedder, the knowledge check uses an embedding-backed similarity") {
        let ext = StubExtractor()
        ext.claimsByScene = [
            "s1": [ContinuityAudit.Claim(
                type: .knowledgeState, subject: "Mara", attributeKey: "",
                value: "Mara knows the SECRET", sourceSceneId: "s1",
                source: .dialogue, evidenceQuote: "q")],
            "s2": [ContinuityAudit.Claim(
                type: .event, subject: "x", attributeKey: "",
                value: "the SECRET is revealed", sourceSceneId: "s2",
                source: .narration, evidenceQuote: "q")],
        ]
        let adj = StubAdjProvider()
        adj.responder = { _ in .success(contradictionJSON) }
        let embedder = StubEmbedder()
        // Both propositions share "SECRET" → same vector → cosine 1.
        embedder.vectorFor = { $0.contains("SECRET") ? onehot(2) : onehot(3) }
        let engine = ContinuityAuditEngine(
            extractor: ext, adjudicationProvider: adj, entities: [], embedder: embedder)
        var result: Result<[ContinuityFinding], Error>?
        engine.audit(scenes: scenes, projectURL: tempProject()) { result = $0 }
        drive(ext, adj)
        let findings = try expectNotNil(try result?.get())
        try expectEqual(findings.count, 1)
        try expectEqual(findings[0].kind, .knowledgeViolation)
    }

    return s
}

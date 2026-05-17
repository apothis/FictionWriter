import Foundation
@testable import LoomCore

/// Continuity Audit (L10) — Phase B, the `ContinuityAuditStore` sidecar.
/// Persists findings to `<project>/continuity-audit/audit.json`, mirrors
/// `ProposedEntitiesStore`. A re-audit replaces findings but carries
/// forward the writer's triage decisions so dismissed errors stay
/// dismissed.
func continuityAuditStoreTests() -> TestSuite {
    let s = TestSuite("ContinuityAuditStore")

    func tempProject() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("loom-cas-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func finding(
        _ kind: ContinuityFinding.Kind = .attributeDrift,
        aValue: String = "green", aScene: String = "s1",
        bValue: String = "brown", bScene: String = "s3",
        status: ContinuityFinding.Status = .open
    ) -> ContinuityFinding {
        func claim(_ v: String, _ sc: String) -> ContinuityAudit.Claim {
            ContinuityAudit.Claim(
                type: .attribute, subject: "Mara", attributeKey: "eye colour", value: v,
                sourceSceneId: sc, source: .narration, evidenceQuote: "q")
        }
        return ContinuityFinding(
            kind: kind, severity: .high, claimA: claim(aValue, aScene), claimB: claim(bValue, bScene),
            explanation: "x", confidence: 0.9, status: status)
    }

    s.test("payload round-trips through Codable") {
        let payload = ContinuityAuditPayload(
            schemaVersion: 1, findings: [finding()], updatedAt: Date(timeIntervalSince1970: 100))
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(ContinuityAuditPayload.self, from: data)
        try expectEqual(decoded, payload)
    }

    s.test("forward-load — a minimal older JSON decodes with defaults") {
        let json = #"{"findings":[]}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ContinuityAuditPayload.self, from: json)
        try expectEqual(decoded.findings.count, 0)
        try expectEqual(decoded.schemaVersion, 1)
    }

    s.test("save then load round-trips through disk") {
        let project = tempProject()
        let payload = ContinuityAuditPayload(schemaVersion: 1, findings: [finding()], updatedAt: Date())
        try ContinuityAuditStore.save(payload, in: project)
        let loaded = try expectNotNil(ContinuityAuditStore.load(in: project))
        try expectEqual(loaded.findings.count, 1)
    }

    s.test("load on a missing sidecar returns nil") {
        try expectNil(ContinuityAuditStore.load(in: tempProject()))
    }

    s.test("replaceFindings overwrites the finding set") {
        let project = tempProject()
        try ContinuityAuditStore.save(
            ContinuityAuditPayload(schemaVersion: 1, findings: [finding(), finding()], updatedAt: Date()),
            in: project)
        try ContinuityAuditStore.replaceFindings([finding()], in: project)
        try expectEqual(ContinuityAuditStore.load(in: project)?.findings.count, 1)
    }

    s.test("a re-audit carries forward a dismissed finding's status") {
        let project = tempProject()
        // The writer dismissed this finding last run.
        try ContinuityAuditStore.save(
            ContinuityAuditPayload(
                schemaVersion: 1,
                findings: [finding(aValue: "green", bValue: "brown", status: .dismissed)],
                updatedAt: Date()),
            in: project)
        // Re-audit re-detects the same conflict, freshly .open.
        try ContinuityAuditStore.replaceFindings(
            [finding(aValue: "green", bValue: "brown", status: .open)], in: project)
        let loaded = try expectNotNil(ContinuityAuditStore.load(in: project))
        try expectEqual(loaded.findings.first?.status, .dismissed)
    }

    s.test("setStatus updates one finding's triage state") {
        let project = tempProject()
        let f = finding()
        try ContinuityAuditStore.save(
            ContinuityAuditPayload(schemaVersion: 1, findings: [f], updatedAt: Date()), in: project)
        try ContinuityAuditStore.setStatus(findingId: f.id, to: .resolved, in: project)
        try expectEqual(ContinuityAuditStore.load(in: project)?.findings.first?.status, .resolved)
    }

    return s
}

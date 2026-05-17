import Foundation

/// Continuity Audit (L10) — Phase B, on-disk sidecar for audit
/// findings. Mirrors `ProposedEntitiesStore`.
///
/// File layout: `<project>/continuity-audit/audit.json`. Only findings
/// persist — claims and the fact-base are recomputed each audit run;
/// findings carry the writer's triage status, which must survive.
public struct ContinuityAuditPayload: Codable, Equatable {
    public var schemaVersion: Int
    public var findings: [ContinuityFinding]
    public var updatedAt: Date

    public init(schemaVersion: Int = 1, findings: [ContinuityFinding], updatedAt: Date) {
        self.schemaVersion = schemaVersion
        self.findings = findings
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, findings, updatedAt
    }

    /// Lazy / forward-load: every field is `decodeIfPresent` with a
    /// default, so an older or partial payload still decodes (the
    /// repo's §9.4 schema contract).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        findings = try c.decodeIfPresent([ContinuityFinding].self, forKey: .findings) ?? []
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
            ?? Date(timeIntervalSince1970: 0)
    }
}

public enum ContinuityAuditStore {
    public static let directoryName = "continuity-audit"
    public static let fileName = "audit.json"

    public static func directoryURL(in projectURL: URL) -> URL {
        projectURL.appendingPathComponent(directoryName, isDirectory: true)
    }

    public static func fileURL(in projectURL: URL) -> URL {
        directoryURL(in: projectURL).appendingPathComponent(fileName)
    }

    /// Returns nil on a missing file or malformed JSON.
    public static func load(in projectURL: URL) -> ContinuityAuditPayload? {
        guard let data = try? Data(contentsOf: fileURL(in: projectURL)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ContinuityAuditPayload.self, from: data)
    }

    public static func save(_ payload: ContinuityAuditPayload, in projectURL: URL) throws {
        try FileManager.default.createDirectory(
            at: directoryURL(in: projectURL), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(payload).write(to: fileURL(in: projectURL))
    }

    /// Replace the whole finding set — an on-demand audit re-runs the
    /// manuscript. Triage status is **carried forward**: a freshly
    /// re-detected finding that matches one the writer already
    /// dismissed or resolved inherits that status, so a re-audit never
    /// resurrects a dismissed error.
    public static func replaceFindings(
        _ findings: [ContinuityFinding],
        in projectURL: URL
    ) throws {
        var priorStatus: [String: ContinuityFinding.Status] = [:]
        if let existing = load(in: projectURL) {
            for f in existing.findings where f.status != .open {
                priorStatus[identity(of: f)] = f.status
            }
        }
        let merged = findings.map { f -> ContinuityFinding in
            guard let carried = priorStatus[identity(of: f)] else { return f }
            var updated = f
            updated.status = carried
            return updated
        }
        try save(ContinuityAuditPayload(findings: merged, updatedAt: Date()), in: projectURL)
    }

    /// Set one finding's triage status. No-op on a missing sidecar or
    /// unknown id.
    public static func setStatus(
        findingId: UUID,
        to status: ContinuityFinding.Status,
        in projectURL: URL
    ) throws {
        guard let existing = load(in: projectURL) else { return }
        let updated = existing.findings.map { f -> ContinuityFinding in
            guard f.id == findingId else { return f }
            var f2 = f
            f2.status = status
            return f2
        }
        try save(ContinuityAuditPayload(findings: updated, updatedAt: Date()), in: projectURL)
    }

    /// Content identity of a finding — what the same continuity error
    /// re-detected on a later run hashes to. Deliberately excludes the
    /// random `id` and the explanation text (which the model rewords).
    private static func identity(of f: ContinuityFinding) -> String {
        [
            f.kind.rawValue,
            f.claimA.sourceSceneId, f.claimA.value,
            f.claimB.sourceSceneId, f.claimB.value,
        ].joined(separator: "|")
    }
}

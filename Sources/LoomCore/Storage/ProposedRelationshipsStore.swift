import Foundation

/// Phase 10 step 4b — on-disk sidecar for pending relationship
/// proposals. Sibling of `ProposedEntitiesStore`; same posture —
/// single file per project, load tolerant of missing/malformed
/// JSON, `replaceProposals` supersedes a scene's prior set (the
/// Phase 9 accumulation lesson, applied from the start).
///
/// File layout: `<project>/proposed-relationships/proposed-relationships.json`.

public struct ProposedRelationshipsPayload: Codable, Equatable {
    public var proposals: [RelationshipDiscovery.Proposal]
    public var updatedAt: Date

    public init(proposals: [RelationshipDiscovery.Proposal], updatedAt: Date) {
        self.proposals = proposals
        self.updatedAt = updatedAt
    }
}

public enum ProposedRelationshipsStore {
    public static let directoryName = "proposed-relationships"
    public static let fileName = "proposed-relationships.json"

    public static func directoryURL(in projectURL: URL) -> URL {
        projectURL.appendingPathComponent(directoryName, isDirectory: true)
    }

    public static func fileURL(in projectURL: URL) -> URL {
        directoryURL(in: projectURL).appendingPathComponent(fileName)
    }

    /// Returns nil on missing-file or malformed-JSON — caller falls
    /// back to an empty queue and the next save rewrites cleanly.
    public static func load(in projectURL: URL) -> ProposedRelationshipsPayload? {
        let url = fileURL(in: projectURL)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ProposedRelationshipsPayload.self, from: data)
    }

    public static func save(_ payload: ProposedRelationshipsPayload, in projectURL: URL) throws {
        let dir = directoryURL(in: projectURL)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        try data.write(to: fileURL(in: projectURL))
    }

    /// Supersede every pending proposal anchored to `sceneId` with a
    /// fresh set — re-running discovery gives the latest read, not
    /// an accumulation. Proposals for other scenes are untouched.
    public static func replaceProposals(
        forSceneId sceneId: UUID,
        proposals: [RelationshipDiscovery.Proposal],
        in projectURL: URL
    ) throws {
        let existing = load(in: projectURL)
            ?? ProposedRelationshipsPayload(proposals: [], updatedAt: Date())
        let kept = existing.proposals.filter { $0.sourceSceneId != sceneId }
        try save(
            ProposedRelationshipsPayload(proposals: kept + proposals, updatedAt: Date()),
            in: projectURL
        )
    }

    /// Drop the proposal with the given id. No-op on missing project
    /// / unknown id.
    public static func remove(proposalId: UUID, in projectURL: URL) throws {
        guard let existing = load(in: projectURL) else { return }
        let filtered = existing.proposals.filter { $0.id != proposalId }
        try save(
            ProposedRelationshipsPayload(proposals: filtered, updatedAt: Date()),
            in: projectURL
        )
    }
}

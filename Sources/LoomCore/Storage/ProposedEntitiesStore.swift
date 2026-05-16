import Foundation

/// Phase 9 entity-discovery — on-disk sidecar for pending entity
/// proposals + their attached facts. LOOM_ENTITY_DISCOVERY_SPIKE §3.2
/// + §6.5: the spike runner writes its proposals here; the Bible
/// Workspace webview reads them via the snapshot and routes accept/
/// reject through bridge intents.
///
/// File layout: `<project>/proposed-entities/proposed-entities.json`.
/// Single file (not per-scene) because proposal counts are bounded
/// by the per-scene cap (§1: ≤ 5/scene × small scene count = dozens
/// not thousands).

public struct ProposedEntitiesPayload: Codable, Equatable {
    public var entities: [EntityDiscovery.ProposedEntity]
    public var facts: [EntityDiscovery.ProposedEntityFacts]
    public var updatedAt: Date

    public init(
        entities: [EntityDiscovery.ProposedEntity],
        facts: [EntityDiscovery.ProposedEntityFacts],
        updatedAt: Date
    ) {
        self.entities = entities
        self.facts = facts
        self.updatedAt = updatedAt
    }
}

public enum ProposedEntitiesStore {
    public static let directoryName = "proposed-entities"
    public static let fileName = "proposed-entities.json"

    public static func directoryURL(in projectURL: URL) -> URL {
        projectURL.appendingPathComponent(directoryName, isDirectory: true)
    }

    public static func fileURL(in projectURL: URL) -> URL {
        directoryURL(in: projectURL).appendingPathComponent(fileName)
    }

    /// Returns nil on missing-file or malformed-JSON. Mirrors
    /// `TemplateGenStateStore` posture — the caller falls back to
    /// an empty queue and the next `save` rewrites cleanly.
    public static func load(in projectURL: URL) -> ProposedEntitiesPayload? {
        let url = fileURL(in: projectURL)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ProposedEntitiesPayload.self, from: data)
    }

    public static func save(_ payload: ProposedEntitiesPayload, in projectURL: URL) throws {
        let dir = directoryURL(in: projectURL)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        try data.write(to: fileURL(in: projectURL))
    }

    /// Append `entities` and `facts` to the existing payload, or
    /// start fresh if the sidecar is absent. `updatedAt` bumps to
    /// now on every append.
    public static func append(
        entities: [EntityDiscovery.ProposedEntity],
        facts: [EntityDiscovery.ProposedEntityFacts],
        in projectURL: URL
    ) throws {
        let existing = load(in: projectURL)
            ?? ProposedEntitiesPayload(entities: [], facts: [], updatedAt: Date())
        let merged = ProposedEntitiesPayload(
            entities: existing.entities + entities,
            facts: existing.facts + facts,
            updatedAt: Date()
        )
        try save(merged, in: projectURL)
    }

    /// Supersede every pending proposal anchored to `sceneId` with a
    /// fresh set. Re-running entity discovery on a scene should give
    /// the latest result, not stack duplicates on top of the prior
    /// run (and earlier scene drafts that occupied the same slot).
    /// Proposals for other scenes are untouched; facts attached to
    /// the superseded proposals are dropped with them.
    public static func replaceProposals(
        forSceneId sceneId: UUID,
        entities: [EntityDiscovery.ProposedEntity],
        facts: [EntityDiscovery.ProposedEntityFacts],
        in projectURL: URL
    ) throws {
        let existing = load(in: projectURL)
            ?? ProposedEntitiesPayload(entities: [], facts: [], updatedAt: Date())
        let keptEntities = existing.entities.filter { $0.sourceSceneId != sceneId }
        let keptIds = Set(keptEntities.map(\.id))
        let keptFacts = existing.facts.filter { keptIds.contains($0.proposedEntityId) }
        let merged = ProposedEntitiesPayload(
            entities: keptEntities + entities,
            facts: keptFacts + facts,
            updatedAt: Date()
        )
        try save(merged, in: projectURL)
    }

    /// Drop the proposal with the given id, plus any facts attached
    /// to it. No-op on missing project / unknown id.
    public static func remove(proposalId: UUID, in projectURL: URL) throws {
        guard let existing = load(in: projectURL) else { return }
        let filteredEntities = existing.entities.filter { $0.id != proposalId }
        let filteredFacts = existing.facts.filter { $0.proposedEntityId != proposalId }
        let merged = ProposedEntitiesPayload(
            entities: filteredEntities,
            facts: filteredFacts,
            updatedAt: Date()
        )
        try save(merged, in: projectURL)
    }
}

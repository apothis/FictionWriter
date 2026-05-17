import Foundation
@testable import LoomCore

/// Phase 9 entity-discovery — Bible Workspace snapshot projection of
/// proposed entities. LOOM_ENTITY_DISCOVERY_SPIKE §3.4: the webview's
/// `EntityProposalsQueue.tsx` view consumes `proposedEntities` from
/// the snapshot. Additive field — existing snapshots remain decodable
/// with `proposedEntities` defaulting to `[]`.
func phase9SnapshotProposedEntitiesTests() -> TestSuite {
    let s = TestSuite("Phase9SnapshotProposedEntities")

    s.test("SnapshotProposedEntity round-trips through Codable") {
        let id = UUID()
        let sceneId = UUID()
        let proposal = SnapshotProposedEntity(
            id: id,
            kind: "character",
            canonicalName: "Marius Thorn",
            aliases: ["Dr Thorn", "Thorn"],
            oneLine: "A reclusive doctor.",
            evidenceQuote: "Marius Thorn arrived at my flat.",
            sourceSceneId: sceneId,
            sourceSceneTitle: "House Call",
            confidence: 0.85,
            attachedFacts: [
                SnapshotProposedFact(fact: "Made a house call.", certainty: "asserted", evidenceQuote: "Marius Thorn arrived.")
            ]
        )
        let data = try JSONEncoder().encode(proposal)
        let back = try JSONDecoder().decode(SnapshotProposedEntity.self, from: data)
        try expectEqual(back, proposal)
    }

    s.test("BibleWorkspaceSnapshot defaults proposedEntities to []") {
        let snap = BibleWorkspaceSnapshot(
            projectTitle: "Test",
            characters: [],
            lorebook: [],
            scenes: [],
            suggestions: []
        )
        try expectEqual(snap.proposedEntities, [])
    }

    s.test("Snapshot encode/decode round-trips proposedEntities") {
        let proposal = SnapshotProposedEntity(
            id: UUID(),
            kind: "place",
            canonicalName: "The Quay",
            aliases: [],
            oneLine: "A pub on the river road.",
            evidenceQuote: "The pub was called The Quay.",
            sourceSceneId: UUID(),
            sourceSceneTitle: "The Singer",
            confidence: 0.9,
            attachedFacts: []
        )
        let snap = BibleWorkspaceSnapshot(
            projectTitle: "Test",
            characters: [],
            lorebook: [],
            scenes: [],
            suggestions: [],
            proposedEntities: [proposal]
        )
        let data = try JSONEncoder().encode(snap)
        let back = try JSONDecoder().decode(BibleWorkspaceSnapshot.self, from: data)
        try expectEqual(back.proposedEntities.count, 1)
        try expectEqual(back.proposedEntities[0], proposal)
    }

    s.test("decoding a legacy snapshot without proposedEntities → empty list") {
        // Legacy on-disk payload from before Phase 9 lands. Should
        // decode cleanly with the new field defaulting to [].
        let legacyJSON = """
        {
          "projectTitle": "Legacy",
          "characters": [],
          "lorebook": [],
          "scenes": [],
          "suggestions": []
        }
        """
        let data = legacyJSON.data(using: .utf8)!
        let snap = try JSONDecoder().decode(BibleWorkspaceSnapshot.self, from: data)
        try expectEqual(snap.proposedEntities, [])
    }

    // MARK: - filterProposalsAgainstBible

    func proposal(
        _ name: String, kind: EntityDiscovery.Kind, aliases: [String] = []
    ) -> EntityDiscovery.ProposedEntity {
        EntityDiscovery.ProposedEntity(
            id: UUID(), kind: kind, canonicalName: name, aliases: aliases,
            oneLine: "x", evidenceQuote: "x", sourceSceneId: UUID(), confidence: 0.8
        )
    }

    s.test("filterProposalsAgainstBible drops a proposal matching a bible character") {
        // A proposal written before its entity was promoted lingers in
        // the store; the snapshot must re-check it against the bible.
        let out = EntityDiscovery.filterProposalsAgainstBible(
            [proposal("Marcus", kind: .character), proposal("Della", kind: .character)],
            characterNames: ["Marcus"], placeNames: [], objectNames: []
        )
        try expectEqual(out.count, 1)
        try expectEqual(out[0].canonicalName, "Della")
    }

    s.test("filterProposalsAgainstBible keeps proposals not in the bible") {
        let out = EntityDiscovery.filterProposalsAgainstBible(
            [proposal("Della", kind: .character)],
            characterNames: ["Marcus"], placeNames: [], objectNames: []
        )
        try expectEqual(out.count, 1)
    }

    s.test("filterProposalsAgainstBible is kind-aware") {
        // A bible *place* named "Marcus" must not suppress a *character*.
        let out = EntityDiscovery.filterProposalsAgainstBible(
            [proposal("Marcus", kind: .character)],
            characterNames: [], placeNames: ["Marcus"], objectNames: []
        )
        try expectEqual(out.count, 1)
    }

    s.test("filterProposalsAgainstBible matches case-insensitively and trims") {
        let out = EntityDiscovery.filterProposalsAgainstBible(
            [proposal("  marcus ", kind: .character)],
            characterNames: ["Marcus"], placeNames: [], objectNames: []
        )
        try expectEqual(out.count, 0)
    }

    s.test("filterProposalsAgainstBible drops a proposal whose alias matches the bible") {
        let out = EntityDiscovery.filterProposalsAgainstBible(
            [proposal("Marc", kind: .character, aliases: ["Marcus"])],
            characterNames: ["Marcus"], placeNames: [], objectNames: []
        )
        try expectEqual(out.count, 0)
    }

    s.test("build() with proposedEntities parameter produces a populated snapshot") {
        let project = Project(title: "T")
        let queue = LedgerSuggestionsQueue()
        let proposal = SnapshotProposedEntity(
            id: UUID(),
            kind: "character",
            canonicalName: "Velka",
            aliases: [],
            oneLine: "Singer.",
            evidenceQuote: "I'm Velka.",
            sourceSceneId: UUID(),
            sourceSceneTitle: "The Singer",
            confidence: 0.8,
            attachedFacts: []
        )
        let snap = BibleWorkspaceSnapshot.build(
            project: project,
            scenes: [:],
            proposedEntities: [proposal],
            suggestionsQueue: queue
        )
        try expectEqual(snap.proposedEntities.count, 1)
        try expectEqual(snap.proposedEntities[0].canonicalName, "Velka")
    }

    return s
}

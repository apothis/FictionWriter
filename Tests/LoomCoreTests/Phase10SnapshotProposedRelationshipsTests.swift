import Foundation
@testable import LoomCore

/// Phase 10 Part B — Bible Workspace snapshot projection of proposed
/// relationships. Additive field; legacy snapshots decode with [].
func phase10SnapshotProposedRelationshipsTests() -> TestSuite {
    let s = TestSuite("Phase10SnapshotProposedRelationships")

    func sample() -> SnapshotProposedRelationship {
        SnapshotProposedRelationship(
            id: UUID(),
            fromName: "Chantal",
            toName: "Jacob",
            kind: "ex-boyfriend",
            status: "past",
            evidenceQuote: "He wasn't really my type.",
            sourceSceneId: UUID(),
            sourceSceneTitle: "The Beach"
        )
    }

    s.test("SnapshotProposedRelationship round-trips through Codable") {
        let p = sample()
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(SnapshotProposedRelationship.self, from: data)
        try expectEqual(back, p)
    }

    s.test("BibleWorkspaceSnapshot defaults proposedRelationships to []") {
        let snap = BibleWorkspaceSnapshot(
            projectTitle: "Test", characters: [], lorebook: [], scenes: [], suggestions: []
        )
        try expectEqual(snap.proposedRelationships, [])
    }

    s.test("Snapshot encode/decode round-trips proposedRelationships") {
        let p = sample()
        let snap = BibleWorkspaceSnapshot(
            projectTitle: "Test", characters: [], lorebook: [], scenes: [], suggestions: [],
            proposedRelationships: [p]
        )
        let data = try JSONEncoder().encode(snap)
        let back = try JSONDecoder().decode(BibleWorkspaceSnapshot.self, from: data)
        try expectEqual(back.proposedRelationships.count, 1)
        try expectEqual(back.proposedRelationships[0], p)
    }

    s.test("legacy snapshot without proposedRelationships → empty list") {
        let legacy = """
        {"projectTitle":"Legacy","characters":[],"lorebook":[],"scenes":[],"suggestions":[]}
        """
        let snap = try JSONDecoder().decode(BibleWorkspaceSnapshot.self, from: Data(legacy.utf8))
        try expectEqual(snap.proposedRelationships, [])
    }

    s.test("SnapshotProposedRelationship defaults conflictsWithCurrent to []") {
        try expectEqual(sample().conflictsWithCurrent, [])
    }

    s.test("Snapshot encode/decode round-trips relationshipMapLayout") {
        let pos = RelationshipMapPosition(characterId: UUID(), x: 42.0, y: -7.5)
        let snap = BibleWorkspaceSnapshot(
            projectTitle: "Test", characters: [], lorebook: [], scenes: [], suggestions: [],
            relationshipMapLayout: [pos]
        )
        let data = try JSONEncoder().encode(snap)
        let back = try JSONDecoder().decode(BibleWorkspaceSnapshot.self, from: data)
        try expectEqual(back.relationshipMapLayout, [pos])
    }

    s.test("legacy snapshot without relationshipMapLayout → empty list") {
        let legacy = """
        {"projectTitle":"Legacy","characters":[],"lorebook":[],"scenes":[],"suggestions":[]}
        """
        let snap = try JSONDecoder().decode(BibleWorkspaceSnapshot.self, from: Data(legacy.utf8))
        try expectEqual(snap.relationshipMapLayout, [])
    }

    s.test("SnapshotProposedRelationship carries conflictsWithCurrent through Codable") {
        let p = SnapshotProposedRelationship(
            id: UUID(), fromName: "Chantal", toName: "Jacob", kind: "girlfriend",
            status: "current", evidenceQuote: "q", sourceSceneId: UUID(),
            sourceSceneTitle: "S", conflictsWithCurrent: ["Muriel"]
        )
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(SnapshotProposedRelationship.self, from: data)
        try expectEqual(back.conflictsWithCurrent, ["Muriel"])
    }

    s.test("legacy SnapshotProposedRelationship JSON without conflictsWithCurrent → []") {
        let legacy = """
        {"id":"\(UUID().uuidString)","fromName":"A","toName":"B","kind":"friend","status":"current","evidenceQuote":"q","sourceSceneId":"\(UUID().uuidString)","sourceSceneTitle":"S"}
        """
        let back = try JSONDecoder().decode(
            SnapshotProposedRelationship.self, from: Data(legacy.utf8)
        )
        try expectEqual(back.conflictsWithCurrent, [])
    }

    s.test("build() with proposedRelationships parameter populates the snapshot") {
        let snap = BibleWorkspaceSnapshot.build(
            project: Project(title: "T"),
            scenes: [:],
            proposedRelationships: [sample()],
            suggestionsQueue: LedgerSuggestionsQueue()
        )
        try expectEqual(snap.proposedRelationships.count, 1)
        try expectEqual(snap.proposedRelationships[0].fromName, "Chantal")
    }

    return s
}

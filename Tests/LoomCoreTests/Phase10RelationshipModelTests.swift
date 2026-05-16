import Foundation
@testable import LoomCore

/// Phase 10 — Character Relationships. Step 1: the `Relationship`
/// model gains a temporal dimension.
///
/// Relationships evolve through a story: if A dates B and later
/// dates C, C is the *current* partner and B becomes a *past* one —
/// but B is never deleted. `status` carries that; `sourceSceneId`
/// anchors when the edge was last observed (so re-discovery can
/// dedup and propose transitions).
///
/// Schema migration: existing project files have `Relationship`
/// entries with no `status`/`sourceSceneId`. They must forward-load
/// — decoding an old edge yields `.current` + nil (an existing
/// relationship is assumed live until prose says otherwise).
func phase10RelationshipModelTests() -> TestSuite {
    let s = TestSuite("Phase10RelationshipModel")

    s.test("RelationshipStatus has exactly current + past") {
        try expectEqual(Set(RelationshipStatus.allCases), Set([.current, .past]))
    }

    s.test("Relationship defaults status to .current and sourceSceneId to nil") {
        let r = Relationship(toCharacterId: UUID(), kind: "girlfriend")
        try expectEqual(r.status, .current)
        try expectNil(r.sourceSceneId)
    }

    s.test("Relationship round-trips status + sourceSceneId through Codable") {
        let scene = UUID()
        let r = Relationship(
            toCharacterId: UUID(),
            kind: "girlfriend",
            status: .past,
            notes: "year-end party",
            sourceSceneId: scene
        )
        let data = try JSONEncoder().encode(r)
        let back = try JSONDecoder().decode(Relationship.self, from: data)
        try expectEqual(back, r)
        try expectEqual(back.status, .past)
        try expectEqual(back.sourceSceneId, scene)
    }

    s.test("legacy Relationship JSON (no status/sourceSceneId) forward-loads as .current/nil") {
        let id = UUID()
        let legacy = """
        {"toCharacterId":"\(id.uuidString)","kind":"spouse","notes":"married"}
        """
        let back = try JSONDecoder().decode(Relationship.self, from: Data(legacy.utf8))
        try expectEqual(back.toCharacterId, id)
        try expectEqual(back.kind, "spouse")
        try expectEqual(back.notes, "married")
        try expectEqual(back.status, .current)
        try expectNil(back.sourceSceneId)
    }

    return s
}

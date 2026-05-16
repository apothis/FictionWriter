import Foundation
@testable import LoomCore

/// Phase 10 step 4b — `RelationshipConflict.applyAccepted`: merging
/// an accepted relationship into a character's edges, including the
/// temporal demotion the user opted into.
func phase10RelationshipAcceptTests() -> TestSuite {
    let s = TestSuite("Phase10RelationshipAccept")

    let chantal = UUID()
    let muriel = UUID()
    let jacob = UUID()

    func rel(_ to: UUID, _ kind: String, _ status: RelationshipStatus = .current) -> Relationship {
        Relationship(toCharacterId: to, kind: kind, status: status)
    }

    s.test("brand-new edge is appended") {
        let out = RelationshipConflict.applyAccepted(
            to: [],
            newEdge: rel(muriel, "girlfriend"),
            demoteConflicting: false
        )
        try expectEqual(out.count, 1)
        try expectEqual(out[0].toCharacterId, muriel)
    }

    s.test("demoteConflicting flips a prior current romantic edge to past, keeps it") {
        // Chantal was with Jacob; now accepting Muriel as girlfriend.
        let existing = [rel(jacob, "boyfriend", .current)]
        let out = RelationshipConflict.applyAccepted(
            to: existing,
            newEdge: rel(muriel, "girlfriend"),
            demoteConflicting: true
        )
        try expectEqual(out.count, 2)
        let jacobEdge = try expectNotNil(out.first { $0.toCharacterId == jacob })
        try expectEqual(jacobEdge.status, .past, "Jacob should be demoted, not deleted")
        let murielEdge = try expectNotNil(out.first { $0.toCharacterId == muriel })
        try expectEqual(murielEdge.status, .current)
    }

    s.test("demoteConflicting=false leaves prior edges untouched (two currents)") {
        let existing = [rel(jacob, "boyfriend", .current)]
        let out = RelationshipConflict.applyAccepted(
            to: existing,
            newEdge: rel(muriel, "girlfriend"),
            demoteConflicting: false
        )
        try expectEqual(out.filter { $0.status == .current }.count, 2)
    }

    s.test("re-accepting the same (character, kind) upserts rather than duplicates") {
        let existing = [rel(muriel, "girlfriend", .past)]
        let out = RelationshipConflict.applyAccepted(
            to: existing,
            newEdge: rel(muriel, "girlfriend", .current),
            demoteConflicting: false
        )
        try expectEqual(out.count, 1)
        try expectEqual(out[0].status, .current)
    }

    s.test("a different kind to the same character is a distinct edge") {
        let existing = [rel(muriel, "friend", .current)]
        let out = RelationshipConflict.applyAccepted(
            to: existing,
            newEdge: rel(muriel, "girlfriend", .current),
            demoteConflicting: false
        )
        try expectEqual(out.count, 2)
    }

    s.test("non-romantic new edge never demotes, even with demoteConflicting=true") {
        let existing = [rel(jacob, "boyfriend", .current)]
        let out = RelationshipConflict.applyAccepted(
            to: existing,
            newEdge: rel(muriel, "friend"),
            demoteConflicting: true
        )
        let jacobEdge = try expectNotNil(out.first { $0.toCharacterId == jacob })
        try expectEqual(jacobEdge.status, .current, "a new friendship must not demote a partner")
    }

    s.test("demotion skips the accepted edge's own slot") {
        // Re-accepting Muriel as current girlfriend must not demote
        // the Muriel edge itself before re-adding it.
        let existing = [rel(muriel, "girlfriend", .current)]
        let out = RelationshipConflict.applyAccepted(
            to: existing,
            newEdge: rel(muriel, "girlfriend", .current),
            demoteConflicting: true
        )
        try expectEqual(out.count, 1)
        try expectEqual(out[0].status, .current)
    }

    s.test("non-romantic existing edges survive a demoting accept") {
        let existing = [
            rel(jacob, "boyfriend", .current),
            rel(muriel, "close friend", .current),
        ]
        let out = RelationshipConflict.applyAccepted(
            to: existing,
            newEdge: rel(chantal, "wife"),
            demoteConflicting: true
        )
        let friend = try expectNotNil(out.first { $0.toCharacterId == muriel })
        try expectEqual(friend.status, .current, "friendship is not romantic — must not demote")
        let ex = try expectNotNil(out.first { $0.toCharacterId == jacob })
        try expectEqual(ex.status, .past)
    }

    return s
}

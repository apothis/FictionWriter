import Foundation
@testable import LoomCore

/// Phase 10 step 4a — `RelationshipConflict`: deciding when to prompt
/// the user to demote a prior current relationship on accept.
func phase10RelationshipConflictTests() -> TestSuite {
    let s = TestSuite("Phase10RelationshipConflict")

    func rel(_ to: UUID = UUID(), kind: String, status: RelationshipStatus = .current) -> Relationship {
        Relationship(toCharacterId: to, kind: kind, status: status)
    }

    s.test("romantic-partner kinds read as exclusive") {
        for k in ["girlfriend", "Boyfriend", "wife", "HUSBAND", "spouse", "fiancée", "lover", "life partner"] {
            try expectTrue(RelationshipConflict.isExclusiveKind(k), "\(k) should be exclusive")
        }
    }

    s.test("non-romantic kinds do not read as exclusive") {
        for k in ["friend", "close friend", "coworker", "mentor", "father", "sister", "rival", "boss"] {
            try expectFalse(RelationshipConflict.isExclusiveKind(k), "\(k) should not be exclusive")
        }
    }

    s.test("ex-girlfriend still reads as exclusive kind (status decides liveness)") {
        try expectTrue(RelationshipConflict.isExclusiveKind("ex-girlfriend"))
    }

    s.test("new exclusive kind + existing current exclusive edge → conflict") {
        let existing = [rel(kind: "girlfriend", status: .current)]
        let conflicts = RelationshipConflict.conflictingCurrent(newKind: "girlfriend", existing: existing)
        try expectEqual(conflicts.count, 1)
    }

    s.test("new exclusive kind + existing PAST exclusive edge → no conflict") {
        let existing = [rel(kind: "girlfriend", status: .past)]
        let conflicts = RelationshipConflict.conflictingCurrent(newKind: "wife", existing: existing)
        try expectEqual(conflicts.count, 0)
    }

    s.test("new non-exclusive kind → never conflicts") {
        let existing = [rel(kind: "girlfriend", status: .current)]
        let conflicts = RelationshipConflict.conflictingCurrent(newKind: "friend", existing: existing)
        try expectEqual(conflicts.count, 0)
    }

    s.test("new exclusive kind + existing current non-exclusive edge → no conflict") {
        let existing = [
            rel(kind: "friend", status: .current),
            rel(kind: "coworker", status: .current),
        ]
        let conflicts = RelationshipConflict.conflictingCurrent(newKind: "girlfriend", existing: existing)
        try expectEqual(conflicts.count, 0)
    }

    s.test("multiple current exclusive edges all surface as conflicts") {
        let existing = [
            rel(kind: "girlfriend", status: .current),
            rel(kind: "lover", status: .current),
            rel(kind: "ex-wife", status: .past),
        ]
        let conflicts = RelationshipConflict.conflictingCurrent(newKind: "wife", existing: existing)
        try expectEqual(conflicts.count, 2)
    }

    return s
}

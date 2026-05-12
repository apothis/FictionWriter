import Foundation
@testable import LoomCore

/// Phase 4.5 Session 4 — pins `ProjectSession.removeKnownFact`,
/// the Bible Workspace's facts-examiner delete affordance. Closes
/// the [`HANDOFF.md`](HANDOFF.md) §15.9 audit gap: accepted
/// ledger facts were invisible (and unremovable) once they
/// landed on `Character.knownFactsBySceneId`. The workspace's
/// facts examiner surfaces them per-scene and routes deletions
/// through this mutator.
///
/// Contract:
/// - removes the fact from the character's per-scene bucket.
/// - empty buckets are removed (keeps the dict tidy).
/// - stale id at any level → no-op (no throw).
/// - mutating call posts `didChangeNotification` + marks dirty.
func phase4_5RemoveKnownFactTests() -> TestSuite {
    let s = TestSuite("Phase4_5RemoveKnownFact")

    func makeSession() -> (ProjectSession, Character, UUID, KnownFact) {
        let session = ProjectSession(project: Project.empty(title: "Test"))
        var iris = session.addCharacter(name: "Iris")
        let sceneId = UUID()
        let fact = KnownFact(fact: "has a bruise on her collarbone", sourceSceneId: sceneId, certainty: .asserted)
        iris.knownFactsBySceneId[sceneId] = [fact]
        session.updateCharacter(iris)
        return (session, iris, sceneId, fact)
    }

    s.test("removeKnownFact deletes the fact from the character's scene bucket") {
        let (session, iris, sceneId, fact) = makeSession()
        session.removeKnownFact(characterId: iris.id, sceneId: sceneId, factId: fact.id)
        let updated = try expectNotNil(session.project.bible.characters.first { $0.id == iris.id })
        try expectNil(updated.knownFactsBySceneId[sceneId])
    }

    s.test("removeKnownFact preserves other facts in the same scene") {
        let session = ProjectSession(project: Project.empty(title: "Test"))
        var iris = session.addCharacter(name: "Iris")
        let sceneId = UUID()
        let factA = KnownFact(fact: "bruise on collarbone", sourceSceneId: sceneId, certainty: .asserted)
        let factB = KnownFact(fact: "wearing a green coat", sourceSceneId: sceneId, certainty: .asserted)
        iris.knownFactsBySceneId[sceneId] = [factA, factB]
        session.updateCharacter(iris)
        session.removeKnownFact(characterId: iris.id, sceneId: sceneId, factId: factA.id)
        let updated = try expectNotNil(session.project.bible.characters.first { $0.id == iris.id })
        let remaining = try expectNotNil(updated.knownFactsBySceneId[sceneId])
        try expectEqual(remaining.count, 1)
        try expectEqual(remaining[0].id, factB.id)
    }

    s.test("removeKnownFact preserves facts in other scenes for the same character") {
        let session = ProjectSession(project: Project.empty(title: "Test"))
        var iris = session.addCharacter(name: "Iris")
        let sceneA = UUID()
        let sceneB = UUID()
        let factA = KnownFact(fact: "a", sourceSceneId: sceneA, certainty: .asserted)
        let factB = KnownFact(fact: "b", sourceSceneId: sceneB, certainty: .asserted)
        iris.knownFactsBySceneId[sceneA] = [factA]
        iris.knownFactsBySceneId[sceneB] = [factB]
        session.updateCharacter(iris)
        session.removeKnownFact(characterId: iris.id, sceneId: sceneA, factId: factA.id)
        let updated = try expectNotNil(session.project.bible.characters.first { $0.id == iris.id })
        try expectNil(updated.knownFactsBySceneId[sceneA])
        try expectNotNil(updated.knownFactsBySceneId[sceneB])
    }

    s.test("removeKnownFact on stale characterId is a no-op") {
        let (session, _, sceneId, fact) = makeSession()
        let before = session.project.bible.characters
        session.removeKnownFact(characterId: UUID(), sceneId: sceneId, factId: fact.id)
        try expectEqual(session.project.bible.characters, before)
    }

    s.test("removeKnownFact on stale sceneId is a no-op") {
        let (session, iris, _, fact) = makeSession()
        let before = session.project.bible.characters
        session.removeKnownFact(characterId: iris.id, sceneId: UUID(), factId: fact.id)
        try expectEqual(session.project.bible.characters, before)
    }

    s.test("removeKnownFact on stale factId is a no-op") {
        let (session, iris, sceneId, _) = makeSession()
        let before = session.project.bible.characters
        session.removeKnownFact(characterId: iris.id, sceneId: sceneId, factId: UUID())
        try expectEqual(session.project.bible.characters, before)
    }

    s.test("removeKnownFact marks the session dirty + posts didChangeNotification") {
        let (session, iris, sceneId, fact) = makeSession()
        var notified = false
        let token = NotificationCenter.default.addObserver(
            forName: ProjectSession.didChangeNotification,
            object: session,
            queue: nil
        ) { _ in notified = true }
        defer { NotificationCenter.default.removeObserver(token) }
        session.removeKnownFact(characterId: iris.id, sceneId: sceneId, factId: fact.id)
        try expectTrue(notified, "expected didChangeNotification on successful remove")
        try expectTrue(session.isDirty, "expected session to be marked dirty")
    }

    return s
}

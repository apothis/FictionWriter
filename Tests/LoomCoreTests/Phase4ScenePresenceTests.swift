import Foundation
@testable import LoomCore

/// Phase 4 #7 sub-task 6 — pure-data resolver for "is character C
/// present in scene S?". Used by `LedgerKnowledge` to bucket
/// extracted facts into KNOWS / DOES NOT KNOW for the prompt layer.
///
/// Presence signals, in priority order:
/// 1. `scene.pov == characterId` — POV character is definitively present.
/// 2. `MentionIndex.count(for:in:) > 0` — `@`-reference in the prose.
/// 3. `WholeWordMatcher.anyMatch(keys: [name] + aliases, ...)` —
///    free-text name occurrence (covers prose without `@`-mentions).
///
/// Each is a "yes" signal; any one matching returns true.
func phase4ScenePresenceTests() -> TestSuite {
    let s = TestSuite("Phase4ScenePresence")

    let miaId = UUID()
    let andersId = UUID()
    let sceneId = UUID()

    func makeScene(prose: String, pov: UUID? = nil) -> Scene {
        var sc = Scene.empty(id: sceneId, title: "Scene")
        sc.prose = prose
        sc.pov = pov
        return sc
    }

    let mia = Character(id: miaId, name: "Mia", aliases: ["Miss Vance", "the librarian"])
    let anders = Character(id: andersId, name: "Anders", aliases: [])

    s.test("Scene.pov == characterId returns present (even with empty prose, empty mentions)") {
        let scene = makeScene(prose: "", pov: miaId)
        let present = ScenePresence.isPresent(
            characterId: miaId,
            in: scene,
            character: mia,
            mentions: MentionIndex()
        )
        try expectTrue(present)
    }

    s.test("mention index match returns present") {
        let scene = makeScene(prose: "")
        let mentions = MentionIndex(
            totalsByEntityId: [miaId: 1],
            perSceneByEntityId: [miaId: [sceneId: 1]]
        )
        let present = ScenePresence.isPresent(
            characterId: miaId,
            in: scene,
            character: mia,
            mentions: mentions
        )
        try expectTrue(present)
    }

    s.test("name appearing as a whole word in prose returns present (no @-mention required)") {
        let scene = makeScene(prose: "Mia walked across the room.")
        let present = ScenePresence.isPresent(
            characterId: miaId,
            in: scene,
            character: mia,
            mentions: MentionIndex()
        )
        try expectTrue(present)
    }

    s.test("alias appearing as a whole word returns present") {
        let scene = makeScene(prose: "The librarian raised an eyebrow.")
        let present = ScenePresence.isPresent(
            characterId: miaId,
            in: scene,
            character: mia,
            mentions: MentionIndex()
        )
        try expectTrue(present)
    }

    s.test("name appearing as a substring only does NOT return present (whole-word rule)") {
        let scene = makeScene(prose: "She booked a trip to Miami.")
        let present = ScenePresence.isPresent(
            characterId: miaId,
            in: scene,
            character: mia,
            mentions: MentionIndex()
        )
        try expectFalse(present)
    }

    s.test("name matching is case-insensitive") {
        let scene = makeScene(prose: "MIA pushed the door.")
        let present = ScenePresence.isPresent(
            characterId: miaId,
            in: scene,
            character: mia,
            mentions: MentionIndex()
        )
        try expectTrue(present)
    }

    s.test("a different character's POV does not satisfy presence for our character") {
        let scene = makeScene(prose: "Anders looked at the door.", pov: andersId)
        let present = ScenePresence.isPresent(
            characterId: miaId,
            in: scene,
            character: mia,
            mentions: MentionIndex()
        )
        try expectFalse(present)
    }

    s.test("none of POV / mention / prose match → not present") {
        let scene = makeScene(prose: "The wind blew the leaves around.")
        let present = ScenePresence.isPresent(
            characterId: miaId,
            in: scene,
            character: mia,
            mentions: MentionIndex()
        )
        try expectFalse(present)
    }

    return s
}

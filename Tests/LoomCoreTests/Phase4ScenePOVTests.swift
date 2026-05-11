import Foundation
@testable import LoomCore

/// Phase 4 #7 sub-task adjacent — per-scene POV picker.
///
/// Sub-task 7 (`[KNOWLEDGE-LEDGER]` prompt layer) gates on
/// `Scene.pov` being a non-nil bible-character id, but there was no UI
/// in Loom to assign POV to a scene. Without it the layer never fires
/// in production. This slice adds:
///
/// 1. `ProjectSession.setScenePOV(id:to:)` — pure setter that mutates
///    the scene's `pov` field, no-ops on a stale scene id, marks the
///    session dirty for autosave. Mirrors `setSceneStatus` /
///    `setSceneSummary`.
/// 2. `ScenePOVMenuBuilder.menuItems(characters:currentPOV:)` —
///    pure-data descriptor list for the sidebar's "Set POV" submenu.
///    Always leads with a "Clear POV" entry; one row per bible
///    character; the current selection carries `isCurrent = true` so
///    the AppKit glue can stamp a checkmark.
func phase4ScenePOVTests() -> TestSuite {
    let s = TestSuite("Phase4ScenePOV")

    // MARK: - session.setScenePOV

    s.test("session.setScenePOV updates the scene's pov field") {
        let session = ProjectSession(project: Project(title: "T"))
        let scene = session.addScene(title: "S1")
        let mia = session.addCharacter(name: "Mia")
        session.setScenePOV(id: scene.id, to: mia.id)
        try expectEqual(session.scenes[scene.id]?.pov, mia.id)
    }

    s.test("session.setScenePOV(nil) clears the pov") {
        let session = ProjectSession(project: Project(title: "T"))
        let scene = session.addScene(title: "S1")
        let mia = session.addCharacter(name: "Mia")
        session.setScenePOV(id: scene.id, to: mia.id)
        session.setScenePOV(id: scene.id, to: nil)
        try expectNil(session.scenes[scene.id]?.pov)
    }

    s.test("session.setScenePOV on a stale scene id is a no-op") {
        let session = ProjectSession(project: Project(title: "T"))
        let scene = session.addScene(title: "S1")
        let mia = session.addCharacter(name: "Mia")
        session.setScenePOV(id: UUID(), to: mia.id)
        try expectNil(session.scenes[scene.id]?.pov)
    }

    s.test("session.setScenePOV leaves the session dirty (autosave gate)") {
        let session = ProjectSession(project: Project(title: "T"))
        let scene = session.addScene(title: "S1")
        let mia = session.addCharacter(name: "Mia")
        // addScene + addCharacter already dirtied; the assertion here
        // pins that setScenePOV doesn't accidentally reset isDirty.
        session.setScenePOV(id: scene.id, to: mia.id)
        try expectTrue(session.isDirty)
    }

    // MARK: - ScenePOVMenuBuilder

    s.test("ScenePOVMenuBuilder with empty bible returns just Clear POV") {
        let items = ScenePOVMenuBuilder.menuItems(characters: [], currentPOV: nil)
        try expectEqual(items.count, 1)
        try expectEqual(items[0].title, "Clear POV")
        try expectNil(items[0].characterId)
        try expectTrue(items[0].isCurrent)
    }

    s.test("ScenePOVMenuBuilder lists every character in input order with no current") {
        let mia = Character.empty(name: "Mia")
        let anders = Character.empty(name: "Anders")
        let items = ScenePOVMenuBuilder.menuItems(characters: [mia, anders], currentPOV: nil)
        try expectEqual(items.count, 3)
        try expectEqual(items[0].title, "Clear POV")
        try expectTrue(items[0].isCurrent)
        try expectEqual(items[1].title, "Mia")
        try expectEqual(items[1].characterId, mia.id)
        try expectFalse(items[1].isCurrent)
        try expectEqual(items[2].title, "Anders")
        try expectEqual(items[2].characterId, anders.id)
        try expectFalse(items[2].isCurrent)
    }

    s.test("ScenePOVMenuBuilder marks the current POV character with isCurrent") {
        let mia = Character.empty(name: "Mia")
        let anders = Character.empty(name: "Anders")
        let items = ScenePOVMenuBuilder.menuItems(characters: [mia, anders], currentPOV: anders.id)
        try expectFalse(items[0].isCurrent)   // Clear POV
        try expectFalse(items[1].isCurrent)   // Mia
        try expectTrue(items[2].isCurrent)    // Anders
    }

    s.test("ScenePOVMenuBuilder with stale currentPOV id leaves all characters non-current") {
        let mia = Character.empty(name: "Mia")
        let items = ScenePOVMenuBuilder.menuItems(characters: [mia], currentPOV: UUID())
        try expectFalse(items[0].isCurrent)   // Clear POV — not current because currentPOV is non-nil
        try expectFalse(items[1].isCurrent)   // Mia — id mismatch
    }

    return s
}

import Foundation
@testable import LoomCore

/// Conditional lorebook activation — a scene-window gate. An entry
/// with `activateFromSceneId` / `activateUntilSceneId` set only
/// activates when the current scene falls within that window of the
/// manuscript order. Use case: plot-reveal lore that must not leak
/// into earlier scenes.
func phase4LorebookSceneGateTests() -> TestSuite {
    let s = TestSuite("Phase4LorebookSceneGate")

    let a = UUID(), b = UUID(), c = UUID()
    let flat = [a, b, c]

    s.test("an ungated entry always activates") {
        let entry = LorebookEntry(name: "x")
        try expectTrue(LorebookSceneGate.allows(entry, currentSceneId: a, flatSceneIds: flat))
    }

    s.test("activateFromSceneId denies scenes before it, allows from there on") {
        let entry = LorebookEntry(name: "x", activateFromSceneId: b)
        try expectFalse(LorebookSceneGate.allows(entry, currentSceneId: a, flatSceneIds: flat))
        try expectTrue(LorebookSceneGate.allows(entry, currentSceneId: b, flatSceneIds: flat))
        try expectTrue(LorebookSceneGate.allows(entry, currentSceneId: c, flatSceneIds: flat))
    }

    s.test("activateUntilSceneId allows up to and including it, denies after") {
        let entry = LorebookEntry(name: "x", activateUntilSceneId: b)
        try expectTrue(LorebookSceneGate.allows(entry, currentSceneId: a, flatSceneIds: flat))
        try expectTrue(LorebookSceneGate.allows(entry, currentSceneId: b, flatSceneIds: flat))
        try expectFalse(LorebookSceneGate.allows(entry, currentSceneId: c, flatSceneIds: flat))
    }

    s.test("from + until form an inclusive window") {
        let entry = LorebookEntry(name: "x", activateFromSceneId: b, activateUntilSceneId: b)
        try expectFalse(LorebookSceneGate.allows(entry, currentSceneId: a, flatSceneIds: flat))
        try expectTrue(LorebookSceneGate.allows(entry, currentSceneId: b, flatSceneIds: flat))
        try expectFalse(LorebookSceneGate.allows(entry, currentSceneId: c, flatSceneIds: flat))
    }

    s.test("a gate fails open when the current scene can't be positioned") {
        let entry = LorebookEntry(name: "x", activateFromSceneId: b)
        try expectTrue(LorebookSceneGate.allows(entry, currentSceneId: nil, flatSceneIds: flat))
        try expectTrue(LorebookSceneGate.allows(entry, currentSceneId: UUID(), flatSceneIds: flat))
    }

    s.test("a gate referencing an unknown scene id is ignored, not denied") {
        let entry = LorebookEntry(name: "x", activateFromSceneId: UUID())
        try expectTrue(LorebookSceneGate.allows(entry, currentSceneId: a, flatSceneIds: flat))
    }

    s.test("LorebookEntry round-trips the scene-gate fields") {
        let entry = LorebookEntry(
            name: "x", activateFromSceneId: b, activateUntilSceneId: c
        )
        let data = try JSONEncoder.loomPretty.encode(entry)
        let back = try JSONDecoder.loom.decode(LorebookEntry.self, from: data)
        try expectEqual(back.activateFromSceneId, b)
        try expectEqual(back.activateUntilSceneId, c)
    }

    s.test("a pre-feature lorebook entry decodes with nil gate fields") {
        let json = """
        { "id": "\(UUID().uuidString)", "name": "old", "content": "",
          "activationMode": "constant", "keys": [], "secondaryKeys": [],
          "enabled": true, "priority": 0, "positionMode": "top",
          "maxRecentScenesScanned": 3, "sticky": false }
        """
        let entry = try JSONDecoder.loom.decode(LorebookEntry.self, from: Data(json.utf8))
        try expectNil(entry.activateFromSceneId)
        try expectNil(entry.activateUntilSceneId)
    }

    s.test("LorebookEntryPatch applies the gate fields") {
        let base = LorebookEntry(name: "x")
        let patched = LorebookEntryPatch(activateFromSceneId: b).apply(to: base)
        try expectEqual(patched.activateFromSceneId, b)
    }

    s.test("a scene-gated entry is filtered from the prompt before its window") {
        var project = Project(title: "T")
        project.manuscript.orphanedSceneIds = [a, b, c]
        project.bible.lorebook = [
            LorebookEntry(
                name: "reveal", content: "X is the traitor.",
                activationMode: .constant, activateFromSceneId: b
            )
        ]
        func build(current: UUID) -> AssembledPrompt {
            var scene = Scene.empty(id: current, title: "S")
            scene.prose = "Some prose."
            return PromptBuilder.build(PromptContext(
                mode: .continueProse, project: project,
                scenes: [current: scene], currentSceneId: current,
                cursorOffset: scene.prose.count, selectionRange: nil,
                modelName: nil, contextBudgetTokens: 8192, replyBudgetTokens: 1024
            ))
        }
        try expectFalse(build(current: a).fullPrompt.contains("X is the traitor."))
        try expectTrue(build(current: b).fullPrompt.contains("X is the traitor."))
    }

    return s
}

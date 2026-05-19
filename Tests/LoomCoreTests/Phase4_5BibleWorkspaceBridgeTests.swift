import Foundation
@testable import LoomCore

/// Phase 4.5 §5.2 — Swift→JS push leg of the WKWebView bridge. The
/// snapshot is serialized to JSON and embedded directly as a JS
/// object literal inside a `window.loom.applySnapshot(...)` call.
/// JSON is a subset of valid JS object-literal syntax (modulo
/// U+2028/U+2029 in pre-ES2019, both fine on macOS 14+ WKWebView),
/// so this avoids the string-escaping dance we'd need if we
/// embedded the snapshot as a JS string literal.
///
/// The JS→Swift intent leg lands in Session 2 (CharacterPatch etc.)
/// — this suite only pins the Swift→JS direction.
func phase4_5BibleWorkspaceBridgeTests() -> TestSuite {
    let s = TestSuite("Phase4_5BibleWorkspaceBridge")

    s.test("encodeSnapshotPush wraps the JSON in window.loom.applySnapshot(...)") {
        let snap = BibleWorkspaceSnapshot(
            projectTitle: "Test", characters: [], lorebook: [], scenes: [], suggestions: []
        )
        let js = try BibleWorkspaceBridge.encodeSnapshotPush(snap)
        try expectTrue(js.hasPrefix("window.loom.applySnapshot("),
            "must start with the JS call prefix; got: \(js)")
        try expectTrue(js.hasSuffix(");"),
            "must end with );; got: \(js)")
    }

    s.test("encoded payload is the JSON-encoded snapshot (no extra escaping)") {
        let snap = BibleWorkspaceSnapshot(
            projectTitle: "Test", characters: [], lorebook: [], scenes: [], suggestions: []
        )
        let js = try BibleWorkspaceBridge.encodeSnapshotPush(snap)
        let prefix = "window.loom.applySnapshot("
        let suffix = ");"
        let middle = String(js.dropFirst(prefix.count).dropLast(suffix.count))
        // The middle must parse back as the original snapshot.
        let data = middle.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(BibleWorkspaceSnapshot.self, from: data)
        try expectEqual(decoded, snap)
    }

    s.test("encoded payload preserves character + lorebook content verbatim through round-trip") {
        let charId = UUID()
        let snap = BibleWorkspaceSnapshot(
            projectTitle: "Quoted",
            characters: [SnapshotCharacter(from: Character(
                id: charId,
                name: "Iris O'Brien",
                description: "She said \"hello\" and walked away.\nNew line."
            ))],
            lorebook: [LorebookEntry(name: "rule:dialogue", content: "use straight quotes", keys: ["dialogue"])],
            scenes: [],
            suggestions: []
        )
        let js = try BibleWorkspaceBridge.encodeSnapshotPush(snap)
        let prefix = "window.loom.applySnapshot("
        let suffix = ");"
        let middle = String(js.dropFirst(prefix.count).dropLast(suffix.count))
        let data = middle.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(BibleWorkspaceSnapshot.self, from: data)
        try expectEqual(decoded, snap)
    }

    s.test("encoded payload escapes U+2028/U+2029 (legal in JSON, illegal in pre-ES2019 JS)") {
        // Modern WKWebView (macOS 14+, ES2022) accepts these directly,
        // but the encoder still escapes them defensively so older
        // targets and any future eval-via-Function constructor calls
        // don't trip on them. JSONEncoder doesn't escape these by
        // default — the bridge has to.
        let weird = "line1\u{2028}line2\u{2029}line3"
        let snap = BibleWorkspaceSnapshot(
            projectTitle: weird,
            characters: [], lorebook: [], scenes: [], suggestions: []
        )
        let js = try BibleWorkspaceBridge.encodeSnapshotPush(snap)
        try expectFalse(js.contains("\u{2028}"),
            "U+2028 must be replaced with \\u2028 in the payload")
        try expectFalse(js.contains("\u{2029}"),
            "U+2029 must be replaced with \\u2029 in the payload")
        try expectTrue(js.contains("\\u2028"),
            "expected literal \\u2028 escape; got: \(js)")
        try expectTrue(js.contains("\\u2029"),
            "expected literal \\u2029 escape; got: \(js)")
    }

    s.test("encoded payload is single-line (no embedded newlines that would break the JS statement)") {
        // We append `;` at the end and inject via evaluateJavaScript;
        // the call expression itself should be one statement.
        // JSON string values can contain \n in their escaped form,
        // which is fine — what we forbid is raw newlines inside the
        // JS source.
        let snap = BibleWorkspaceSnapshot(
            projectTitle: "Multi\nline\ntitle",
            characters: [], lorebook: [], scenes: [], suggestions: []
        )
        let js = try BibleWorkspaceBridge.encodeSnapshotPush(snap)
        try expectFalse(js.contains("\n"),
            "encoded JS must not contain literal newlines (they're escaped to \\n inside the JSON strings)")
    }

    // MARK: - JS → Swift intent decoding (Phase 4.5 Session 2)

    s.test("decodeIntent on patchCharacter JSON yields the expected case") {
        let id = UUID()
        let json = """
        {"kind":"patchCharacter","id":"\(id.uuidString)","patch":{"name":"Daniel"}}
        """
        let intent = try BibleWorkspaceBridge.decodeIntent(Data(json.utf8))
        switch intent {
        case .patchCharacter(let decodedId, let patch):
            try expectEqual(decodedId, id)
            try expectEqual(patch.name, "Daniel")
            try expectNil(patch.description)
        default:
            try expect(false, "expected .patchCharacter")
        }
    }

    s.test("decodeIntent on patchCharacter accepts an empty patch payload") {
        // The React side may send a patch with no fields if the user
        // triggered a save with no diverging fields — should decode
        // cleanly to a no-op.
        let id = UUID()
        let json = """
        {"kind":"patchCharacter","id":"\(id.uuidString)","patch":{}}
        """
        let intent = try BibleWorkspaceBridge.decodeIntent(Data(json.utf8))
        switch intent {
        case .patchCharacter(_, let patch):
            try expectEqual(patch, CharacterPatch())
        default:
            try expect(false, "expected .patchCharacter")
        }
    }

    s.test("decodeIntent on unknown kind throws a decoding error") {
        let json = "{\"kind\":\"madeUpIntent\",\"foo\":\"bar\"}"
        try expectThrows {
            _ = try BibleWorkspaceBridge.decodeIntent(Data(json.utf8))
        }
    }

    s.test("decodeIntent on missing kind throws a decoding error") {
        let json = "{\"id\":\"abc\"}"
        try expectThrows {
            _ = try BibleWorkspaceBridge.decodeIntent(Data(json.utf8))
        }
    }

    s.test("intent round-trips through encode/decode") {
        let id = UUID()
        let intent = BibleWorkspaceIntent.patchCharacter(
            id: id,
            patch: CharacterPatch(name: "X", description: "Y", injectionMode: .keyed)
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(intent)
        let decoded = try BibleWorkspaceBridge.decodeIntent(data)
        try expectEqual(decoded, intent)
    }

    s.test("intent JSON uses a `kind` discriminator (matches JS-side contract)") {
        let intent = BibleWorkspaceIntent.patchCharacter(id: UUID(), patch: CharacterPatch())
        let data = try JSONEncoder().encode(intent)
        let json = String(data: data, encoding: .utf8) ?? ""
        try expectTrue(json.contains("\"kind\":\"patchCharacter\""),
            "encoded intent must use a `kind` discriminator; got: \(json)")
    }

    // MARK: - Session 3 intent cases (Phase 4.5 §7)

    s.test("decodeIntent on patchLorebookEntry yields the expected case") {
        let id = UUID()
        let json = """
        {"kind":"patchLorebookEntry","id":"\(id.uuidString)","patch":{"name":"scenario:other"}}
        """
        let intent = try BibleWorkspaceBridge.decodeIntent(Data(json.utf8))
        switch intent {
        case .patchLorebookEntry(let decodedId, let patch):
            try expectEqual(decodedId, id)
            try expectEqual(patch.name, "scenario:other")
        default:
            try expect(false, "expected .patchLorebookEntry")
        }
    }

    s.test("decodeIntent on addLorebookEntry yields the expected case") {
        let json = "{\"kind\":\"addLorebookEntry\",\"name\":\"new entry\"}"
        let intent = try BibleWorkspaceBridge.decodeIntent(Data(json.utf8))
        switch intent {
        case .addLorebookEntry(let name):
            try expectEqual(name, "new entry")
        default:
            try expect(false, "expected .addLorebookEntry")
        }
    }

    s.test("decodeIntent on deleteLorebookEntry yields the expected case") {
        let id = UUID()
        let json = "{\"kind\":\"deleteLorebookEntry\",\"id\":\"\(id.uuidString)\"}"
        let intent = try BibleWorkspaceBridge.decodeIntent(Data(json.utf8))
        switch intent {
        case .deleteLorebookEntry(let decodedId):
            try expectEqual(decodedId, id)
        default:
            try expect(false, "expected .deleteLorebookEntry")
        }
    }

    s.test("patchLorebookEntry round-trips through encode/decode") {
        let id = UUID()
        let intent = BibleWorkspaceIntent.patchLorebookEntry(
            id: id,
            patch: LorebookEntryPatch(content: "X", enabled: false, priority: 99)
        )
        let data = try JSONEncoder().encode(intent)
        let decoded = try BibleWorkspaceBridge.decodeIntent(data)
        try expectEqual(decoded, intent)
    }

    // MARK: - P2b — Dynamic Sheet intents

    s.test("decodeIntent on addDynamicSheet yields the expected case") {
        let intent = try BibleWorkspaceBridge.decodeIntent(
            Data("{\"kind\":\"addDynamicSheet\",\"name\":\"Mira & Cole\"}".utf8)
        )
        switch intent {
        case .addDynamicSheet(let name):
            try expectEqual(name, "Mira & Cole")
        default:
            try expect(false, "expected .addDynamicSheet")
        }
    }

    s.test("patchDynamicSheet round-trips through encode/decode") {
        let intent = BibleWorkspaceIntent.patchDynamicSheet(
            id: UUID(),
            patch: DynamicSheetPatch(roles: "A leads.", alwaysOn: true, enabled: false)
        )
        let data = try JSONEncoder().encode(intent)
        try expectEqual(try BibleWorkspaceBridge.decodeIntent(data), intent)
    }

    s.test("deleteDynamicSheet round-trips through encode/decode") {
        let intent = BibleWorkspaceIntent.deleteDynamicSheet(id: UUID())
        let data = try JSONEncoder().encode(intent)
        try expectEqual(try BibleWorkspaceBridge.decodeIntent(data), intent)
    }

    s.test("a snapshot carries the project's dynamics through encode") {
        var project = Project(title: "T")
        project.bible.dynamics = [DynamicSheet(name: "Mira & Cole", roles: "A leads.")]
        let snapshot = BibleWorkspaceSnapshot.build(
            project: project, scenes: [:], suggestionsQueue: LedgerSuggestionsQueue()
        )
        try expectEqual(snapshot.dynamics.count, 1)
        try expectEqual(snapshot.dynamics.first?.name, "Mira & Cole")
    }

    s.test("a snapshot JSON without dynamics decodes with an empty list") {
        let json = """
        {"projectTitle":"T","characters":[],"lorebook":[],"scenes":[],"suggestions":[]}
        """
        let snap = try JSONDecoder().decode(BibleWorkspaceSnapshot.self, from: Data(json.utf8))
        try expectEqual(snap.dynamics, [])
    }

    // MARK: - P2 project-tools intents

    s.test("setSceneFraming round-trips through encode/decode") {
        let intent = BibleWorkspaceIntent.setSceneFraming(
            sceneId: UUID(), framing: "Hate-sex dynamic; high tension."
        )
        let data = try JSONEncoder().encode(intent)
        try expectEqual(try BibleWorkspaceBridge.decodeIntent(data), intent)
    }

    s.test("setAntiSlopPhrases round-trips through encode/decode") {
        let intent = BibleWorkspaceIntent.setAntiSlopPhrases(
            phrases: ["a testament to", "her core"]
        )
        let data = try JSONEncoder().encode(intent)
        try expectEqual(try BibleWorkspaceBridge.decodeIntent(data), intent)
    }

    s.test("ProjectToolsSnapshot.framing carries the scene's framing text") {
        var scene = Scene.empty(title: "The Beach")
        scene.framing = "what's at stake"
        let mira = Character(name: "Mira")
        scene.undressedCharacterIds = [mira.id]
        let snap = ProjectToolsSnapshot.framing(
            scene: scene, characters: [mira], projectTitle: "P"
        )
        try expectEqual(snap.tool, "framing")
        try expectEqual(snap.framing, "what's at stake")
        try expectEqual(snap.sceneId, scene.id.uuidString)
        try expectEqual(snap.sceneCharacters.map(\.name), ["Mira"])
        try expectEqual(snap.undressedCharacterIds, [mira.id.uuidString])
    }

    s.test("setSceneUndressed intent round-trips through encode/decode") {
        let intent = BibleWorkspaceIntent.setSceneUndressed(
            sceneId: UUID(), characterIds: [UUID(), UUID()]
        )
        let data = try JSONEncoder().encode(intent)
        try expectEqual(try BibleWorkspaceBridge.decodeIntent(data), intent)
    }

    s.test("ProjectToolsSnapshot.antiSlop carries the project's phrase list") {
        var project = Project(title: "P")
        project.settings.antiSlopPhrases = ["x", "y"]
        let snap = ProjectToolsSnapshot.antiSlop(project: project)
        try expectEqual(snap.tool, "antislop")
        try expectEqual(snap.antiSlopPhrases, ["x", "y"])
    }

    // MARK: - Session 4 intent (Phase 4.5 §7) — accepted-facts examiner

    s.test("decodeIntent on deleteKnownFact yields the expected case") {
        let charId = UUID()
        let sceneId = UUID()
        let factId = UUID()
        let json = """
        {"kind":"deleteKnownFact","characterId":"\(charId.uuidString)","sceneId":"\(sceneId.uuidString)","factId":"\(factId.uuidString)"}
        """
        let intent = try BibleWorkspaceBridge.decodeIntent(Data(json.utf8))
        switch intent {
        case .deleteKnownFact(let cId, let sId, let fId):
            try expectEqual(cId, charId)
            try expectEqual(sId, sceneId)
            try expectEqual(fId, factId)
        default:
            try expect(false, "expected .deleteKnownFact")
        }
    }

    s.test("deleteKnownFact intent round-trips through encode/decode") {
        let intent = BibleWorkspaceIntent.deleteKnownFact(
            characterId: UUID(),
            sceneId: UUID(),
            factId: UUID()
        )
        let data = try JSONEncoder().encode(intent)
        let decoded = try BibleWorkspaceBridge.decodeIntent(data)
        try expectEqual(decoded, intent)
    }

    // MARK: - Session 5 intents (Phase 4.5 §7) — suggestions queue

    s.test("decodeIntent on acceptSuggestion yields the expected case") {
        let factId = UUID()
        let json = "{\"kind\":\"acceptSuggestion\",\"factId\":\"\(factId.uuidString)\"}"
        let intent = try BibleWorkspaceBridge.decodeIntent(Data(json.utf8))
        switch intent {
        case .acceptSuggestion(let decodedFactId):
            try expectEqual(decodedFactId, factId)
        default:
            try expect(false, "expected .acceptSuggestion")
        }
    }

    s.test("decodeIntent on rejectSuggestion yields the expected case") {
        let factId = UUID()
        let json = "{\"kind\":\"rejectSuggestion\",\"factId\":\"\(factId.uuidString)\"}"
        let intent = try BibleWorkspaceBridge.decodeIntent(Data(json.utf8))
        switch intent {
        case .rejectSuggestion(let decodedFactId):
            try expectEqual(decodedFactId, factId)
        default:
            try expect(false, "expected .rejectSuggestion")
        }
    }

    s.test("acceptSuggestion + rejectSuggestion round-trip through encode/decode") {
        let factId = UUID()
        for intent in [
            BibleWorkspaceIntent.acceptSuggestion(factId: factId),
            BibleWorkspaceIntent.rejectSuggestion(factId: factId),
        ] {
            let data = try JSONEncoder().encode(intent)
            let decoded = try BibleWorkspaceBridge.decodeIntent(data)
            try expectEqual(decoded, intent)
        }
    }

    return s
}

import Foundation
@testable import LoomCore

/// Phase 4.5 §5.2 — `BibleWorkspaceSnapshot` is the JSON contract
/// pushed Swift→JS over the WKScriptMessageHandler bridge. The web
/// side renders it; Swift owns the source of truth
/// (`ProjectSession`) and rebuilds + pushes a fresh snapshot on
/// every `didChangeNotification`. See [LOOM_BIBLE_WORKSPACE.md §5.2]
/// for the bridge contract.
///
/// The snapshot is intentionally flat where the source isn't:
/// - `SceneSummary` is `{ id, title }` — full `Scene` carries prose
///   blob + frontmatter we don't want to ship over the bridge.
/// - `PendingSuggestion` is a flat projection of `LedgerSuggestion`
///   exposing the fact-id (for accept/reject intents), the
///   resolved characterId, fact text, certainty, evidence quote,
///   and sourceSceneId. The web side never sees the nested
///   `KnownFact` shape — flat is friendlier for JSX rendering.
///
/// Ordering matters for stable UI: characters in `bible.characters`
/// order, scenes in `manuscript.flatSceneIds` order, suggestions
/// follow character order then per-character insertion order.
func phase4_5BibleWorkspaceSnapshotTests() -> TestSuite {
    let s = TestSuite("Phase4_5BibleWorkspaceSnapshot")

    // MARK: - Codable round-trip

    s.test("empty snapshot round-trips through JSON cleanly") {
        let snap = BibleWorkspaceSnapshot(
            projectTitle: "Untitled",
            characters: [],
            lorebook: [],
            scenes: [],
            suggestions: []
        )
        let data = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(BibleWorkspaceSnapshot.self, from: data)
        try expectEqual(decoded, snap)
    }

    s.test("populated snapshot round-trips with every field preserved") {
        let charId = UUID()
        let sceneId = UUID()
        let factId = UUID()
        let snap = BibleWorkspaceSnapshot(
            projectTitle: "Test Novel",
            characters: [Character(id: charId, name: "Iris", description: "Tired woman.")],
            lorebook: [LorebookEntry(name: "scenario:kink", content: "weighted thing", keys: ["kink"])],
            scenes: [SceneSummary(id: sceneId, title: "Opening")],
            suggestions: [
                PendingSuggestion(
                    factId: factId,
                    characterId: charId,
                    factText: "has a bruise on her collarbone",
                    certainty: "asserted",
                    evidenceQuote: "the bruise above her collarbone",
                    sourceSceneId: sceneId
                )
            ]
        )
        let data = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(BibleWorkspaceSnapshot.self, from: data)
        try expectEqual(decoded, snap)
    }

    s.test("SceneSummary round-trips") {
        let summary = SceneSummary(id: UUID(), title: "Scene 1")
        let data = try JSONEncoder().encode(summary)
        let decoded = try JSONDecoder().decode(SceneSummary.self, from: data)
        try expectEqual(decoded, summary)
    }

    s.test("PendingSuggestion round-trips with sourceSceneId nil") {
        // sourceSceneId is optional because the diff stage stamps it
        // post-resolution; a snapshot built mid-pipeline shouldn't
        // assert presence. JSON encoding has to handle the nil cleanly.
        let pending = PendingSuggestion(
            factId: UUID(),
            characterId: UUID(),
            factText: "test",
            certainty: "suspected",
            evidenceQuote: "quote",
            sourceSceneId: nil
        )
        let data = try JSONEncoder().encode(pending)
        let decoded = try JSONDecoder().decode(PendingSuggestion.self, from: data)
        try expectEqual(decoded, pending)
    }

    // MARK: - JSON shape (matters: the web side relies on field names)

    s.test("snapshot JSON keys are lowerCamelCase and match the bridge contract") {
        let snap = BibleWorkspaceSnapshot(
            projectTitle: "X",
            characters: [],
            lorebook: [],
            scenes: [],
            suggestions: []
        )
        let data = try JSONEncoder().encode(snap)
        let json = String(data: data, encoding: .utf8) ?? ""
        for key in ["projectTitle", "characters", "lorebook", "scenes", "suggestions"] {
            try expectTrue(json.contains("\"\(key)\":"),
                "encoded snapshot must contain key '\(key)'; got: \(json)")
        }
    }

    s.test("PendingSuggestion JSON keys match the bridge contract") {
        let pending = PendingSuggestion(
            factId: UUID(),
            characterId: UUID(),
            factText: "x",
            certainty: "asserted",
            evidenceQuote: "y",
            sourceSceneId: UUID()
        )
        let data = try JSONEncoder().encode(pending)
        let json = String(data: data, encoding: .utf8) ?? ""
        for key in ["factId", "characterId", "factText", "certainty", "evidenceQuote", "sourceSceneId"] {
            try expectTrue(json.contains("\"\(key)\":"), "missing key '\(key)' in: \(json)")
        }
    }

    // MARK: - Builder

    s.test("BibleWorkspaceSnapshot.build on a brand-new empty project yields all-empty arrays") {
        let project = Project(title: "Empty")
        let queue = LedgerSuggestionsQueue()
        let snap = BibleWorkspaceSnapshot.build(project: project, scenes: [:], suggestionsQueue: queue)
        try expectEqual(snap.projectTitle, "Empty")
        try expectEqual(snap.characters.count, 0)
        try expectEqual(snap.lorebook.count, 0)
        try expectEqual(snap.scenes.count, 0)
        try expectEqual(snap.suggestions.count, 0)
    }

    s.test("build mirrors project title + characters + lorebook entries by reference") {
        let iris = Character(name: "Iris", description: "tired")
        let daniel = Character(name: "Daniel", description: "watching")
        let lore = LorebookEntry(name: "scenario:tone", content: "dark", keys: ["dark"])
        var project = Project(title: "My Novel")
        project.bible.characters = [iris, daniel]
        project.bible.lorebook = [lore]
        let snap = BibleWorkspaceSnapshot.build(project: project, scenes: [:], suggestionsQueue: LedgerSuggestionsQueue())
        try expectEqual(snap.projectTitle, "My Novel")
        try expectEqual(snap.characters, [iris, daniel])
        try expectEqual(snap.lorebook, [lore])
    }

    s.test("build emits scenes in manuscript.flatSceneIds order with id+title only") {
        // Three scenes; arrange them out-of-order in the scenes
        // dictionary so we know flatSceneIds (not dict iteration) is
        // what drives the result.
        let s1 = Scene(id: UUID(), title: "Opening", prose: "")
        let s2 = Scene(id: UUID(), title: "Middle", prose: "")
        let s3 = Scene(id: UUID(), title: "Climax", prose: "")
        var project = Project(title: "Order Test")
        let chapter = Chapter(title: "Ch1", sceneIds: [s1.id, s2.id, s3.id])
        let part = Part(title: "Part 1", chapters: [chapter])
        project.manuscript.parts = [part]
        let scenes: [UUID: Scene] = [s3.id: s3, s1.id: s1, s2.id: s2]
        let snap = BibleWorkspaceSnapshot.build(project: project, scenes: scenes, suggestionsQueue: LedgerSuggestionsQueue())
        let titles = snap.scenes.map(\.title)
        try expectEqual(titles, ["Opening", "Middle", "Climax"])
        let ids = snap.scenes.map(\.id)
        try expectEqual(ids, [s1.id, s2.id, s3.id])
    }

    s.test("build flattens suggestions queue across characters in bible.characters order") {
        let iris = Character(name: "Iris")
        let daniel = Character(name: "Daniel")
        var project = Project(title: "Suggest Test")
        project.bible.characters = [iris, daniel]
        let sceneId = UUID()
        let queue = LedgerSuggestionsQueue()
        // Add Daniel's first, then Iris's — but the snapshot output
        // should follow bible.characters order (Iris first, Daniel
        // second), not insertion order.
        queue.add([
            LedgerSuggestion(
                characterId: daniel.id,
                fact: KnownFact(fact: "watches Iris", sourceSceneId: sceneId, certainty: .asserted),
                evidenceQuote: "he watched her"
            )
        ])
        queue.add([
            LedgerSuggestion(
                characterId: iris.id,
                fact: KnownFact(fact: "is tired", sourceSceneId: sceneId, certainty: .asserted),
                evidenceQuote: "she was tired"
            )
        ])
        let snap = BibleWorkspaceSnapshot.build(project: project, scenes: [:], suggestionsQueue: queue)
        try expectEqual(snap.suggestions.count, 2)
        try expectEqual(snap.suggestions[0].characterId, iris.id)
        try expectEqual(snap.suggestions[0].factText, "is tired")
        try expectEqual(snap.suggestions[1].characterId, daniel.id)
        try expectEqual(snap.suggestions[1].factText, "watches Iris")
    }

    s.test("PendingSuggestion carries the fact id (drives accept/reject intent payloads)") {
        let iris = Character(name: "Iris")
        var project = Project(title: "Id Test")
        project.bible.characters = [iris]
        let factId = UUID()
        let queue = LedgerSuggestionsQueue()
        queue.add([
            LedgerSuggestion(
                characterId: iris.id,
                fact: KnownFact(id: factId, fact: "x", certainty: .asserted),
                evidenceQuote: "y"
            )
        ])
        let snap = BibleWorkspaceSnapshot.build(project: project, scenes: [:], suggestionsQueue: queue)
        try expectEqual(snap.suggestions[0].factId, factId)
    }

    s.test("build is stable across repeated calls on unchanged inputs (snapshot equality)") {
        // The bridge pushes a fresh snapshot on every didChange; the
        // web side benefits from being able to bail out cheaply on
        // identical-snapshot pushes. Equality is the simplest signal.
        let iris = Character(name: "Iris")
        var project = Project(title: "Stable")
        project.bible.characters = [iris]
        let snap1 = BibleWorkspaceSnapshot.build(project: project, scenes: [:], suggestionsQueue: LedgerSuggestionsQueue())
        let snap2 = BibleWorkspaceSnapshot.build(project: project, scenes: [:], suggestionsQueue: LedgerSuggestionsQueue())
        try expectEqual(snap1, snap2)
    }

    return s
}

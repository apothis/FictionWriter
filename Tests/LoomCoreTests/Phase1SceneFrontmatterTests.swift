import Foundation
@testable import LoomCore

/// Sub-step 1.b — Scene .md round-trip. Pure-data tests against the
/// frontmatter parser and emitter. The on-disk format per LOOM_DATA_MODEL.md
/// §7.1: opening `---`, key:value lines (string/int/bool/uuid scalars),
/// closing `---`, then prose body verbatim.
///
/// Round-trip property is the headline: external editors must be able to
/// open a .md, edit the prose or even add an unknown frontmatter key, and
/// Loom's next save must preserve those edits. extraFrontmatter is the
/// forward-compat sink.
func phase1SceneFrontmatterTests() -> TestSuite {
    let s = TestSuite("Phase1SceneFrontmatter")

    s.test("scene with all known fields round-trips") {
        let id = UUID()
        let pov = UUID()
        let location = UUID()
        var scene = Scene.empty(id: id, title: "The Opening")
        scene.pov = pov
        scene.location = location
        scene.status = .draft
        scene.conflict = "Mia confronts the stranger at the door."
        scene.outcome = "Stranger leaves; Mia bolts the door."
        scene.summary = "Mia, alone in her flat, opens the door to a stranger…"
        scene.summaryDirty = false
        scene.targetWordCount = 1500
        scene.prose = "The wind had been picking up for an hour.\n\nShe rose from the chair."

        let text = SceneFile.encode(scene)
        let parsed = try SceneFile.decode(text, contentPath: scene.contentPath)

        try expectEqual(parsed.id, scene.id)
        try expectEqual(parsed.title, scene.title)
        try expectEqual(parsed.pov, scene.pov)
        try expectEqual(parsed.location, scene.location)
        try expectEqual(parsed.status, scene.status)
        try expectEqual(parsed.conflict, scene.conflict)
        try expectEqual(parsed.outcome, scene.outcome)
        try expectEqual(parsed.summary, scene.summary)
        try expectEqual(parsed.summaryDirty, scene.summaryDirty)
        try expectEqual(parsed.targetWordCount, scene.targetWordCount)
        try expectEqual(parsed.prose, scene.prose)
    }

    s.test("prose body preserved verbatim including blank lines") {
        var scene = Scene.empty(id: UUID(), title: "X")
        scene.prose = "Para one.\n\nPara two has _italics_.\n\n\nThree blank lines above."
        let text = SceneFile.encode(scene)
        let parsed = try SceneFile.decode(text, contentPath: scene.contentPath)
        try expectEqual(parsed.prose, scene.prose)
    }

    s.test("unknown frontmatter keys preserved on round-trip") {
        var scene = Scene.empty(id: UUID(), title: "X")
        scene.prose = "body"
        scene.extraFrontmatter = [
            "customField": "from-an-external-editor",
            "anotherKey": "42",
        ]

        let text = SceneFile.encode(scene)
        let parsed = try SceneFile.decode(text, contentPath: scene.contentPath)
        try expectEqual(parsed.extraFrontmatter, scene.extraFrontmatter)
    }

    s.test("horizontal rule inside prose body does not split frontmatter") {
        // Markdown `---` on its own line is a horizontal rule. Loom's
        // frontmatter parser only treats the FIRST `---` block at the
        // top of the file as frontmatter; later `---` lines belong to
        // the prose.
        var scene = Scene.empty(id: UUID(), title: "X")
        scene.prose = "Section one.\n\n---\n\nSection two follows a horizontal rule."
        let text = SceneFile.encode(scene)
        let parsed = try SceneFile.decode(text, contentPath: scene.contentPath)
        try expectEqual(parsed.prose, scene.prose)
    }

    s.test("decoded scene without optional fields gets sensible defaults") {
        // A minimal hand-written .md with only `id` and `title`.
        let id = UUID()
        let text = """
        ---
        id: "\(id.uuidString)"
        title: "Bare scene"
        ---

        prose body here.
        """
        let parsed = try SceneFile.decode(text, contentPath: "scenes/\(id.uuidString).md")
        try expectEqual(parsed.id, id)
        try expectEqual(parsed.title, "Bare scene")
        try expectNil(parsed.pov)
        try expectNil(parsed.location)
        try expectEqual(parsed.status, .draft)
        try expectEqual(parsed.summaryDirty, false)
        try expectEqual(parsed.prose, "prose body here.")
    }

    s.test("title with embedded quotes round-trips") {
        var scene = Scene.empty(id: UUID(), title: #"She said: "hello""#)
        scene.prose = ""
        let text = SceneFile.encode(scene)
        let parsed = try SceneFile.decode(text, contentPath: scene.contentPath)
        try expectEqual(parsed.title, scene.title)
    }

    return s
}

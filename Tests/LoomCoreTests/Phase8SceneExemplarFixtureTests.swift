import Foundation
@testable import LoomCore

// Phase 8.a §6.1 — fixture frontmatter parser for the embedder
// discrimination spike. The 20 fixtures at
// Tools/SceneExemplarSpike/fixtures/ use a YAML-style frontmatter
// extending the Phase 7 SceneTemplateSpike pattern with three new
// fields: nsfw (bool), register (axis label or "n/a"), style_axis
// (matching style label). See LOOM_SCENE_EXEMPLAR.md §8.a.1.

func phase8SceneExemplarFixtureTests() -> TestSuite {
    let s = TestSuite("Phase8SceneExemplarFixture")

    s.test("parses NSFW fixture frontmatter + body") {
        let markdown = """
            ---
            fixture_id: nsfw_01_explicit_direct
            title: After Midnight
            nsfw: true
            register: explicit-direct
            style_axis: explicit-direct
            source: original (written for spike)
            word_count: ~420
            notes: |
              Target register: anatomically specific, present-tense.
              Second line of notes.
            ---

            She gets on top of him without saying anything.
            """
        let f = try SceneExemplarFixtureParser.parse(markdown)
        try expectEqual(f.id, "nsfw_01_explicit_direct")
        try expectEqual(f.title, "After Midnight")
        try expectEqual(f.nsfw, true)
        try expectEqual(f.register, "explicit-direct")
        try expectEqual(f.styleAxis, "explicit-direct")
        try expectTrue(f.body.hasPrefix("She gets on top of him"))
    }

    s.test("parses SFW fixture with register=n/a") {
        let markdown = """
            ---
            fixture_id: sfw_01_clipped_hemingway
            title: To the Rain
            nsfw: false
            register: n/a
            style_axis: clipped-Hemingway
            source: original
            word_count: ~415
            notes: |
              Target style: short declarative sentences.
            ---

            They sat at the corner of the bar.
            """
        let f = try SceneExemplarFixtureParser.parse(markdown)
        try expectEqual(f.id, "sfw_01_clipped_hemingway")
        try expectEqual(f.nsfw, false)
        try expectEqual(f.register, "n/a")
        try expectEqual(f.styleAxis, "clipped-Hemingway")
        try expectTrue(f.body.hasPrefix("They sat at the corner of the bar"))
    }

    s.test("body strips leading blank lines after closing ---") {
        let markdown = """
            ---
            fixture_id: x
            title: x
            nsfw: false
            register: n/a
            style_axis: x
            ---


            The body starts here.
            """
        let f = try SceneExemplarFixtureParser.parse(markdown)
        try expectEqual(f.body, "The body starts here.")
    }

    s.test("block scalar 'notes: |' does not bleed into the body") {
        // The notes field uses YAML block scalar syntax. If the parser
        // mistakes the indented note lines for top-level frontmatter
        // entries, or fails to consume them and they leak into the body,
        // the test catches it.
        let markdown = """
            ---
            fixture_id: x
            title: x
            nsfw: true
            register: explicit-direct
            style_axis: explicit-direct
            notes: |
              Line 1 of notes.
              Line 2 of notes.
              Line 3 of notes.
            ---

            The real body.
            """
        let f = try SceneExemplarFixtureParser.parse(markdown)
        try expectEqual(f.id, "x")
        try expectEqual(f.body, "The real body.")
    }

    s.test("missing required fixture_id field throws") {
        let markdown = """
            ---
            title: x
            nsfw: false
            register: n/a
            style_axis: x
            ---

            body
            """
        try expectThrows {
            _ = try SceneExemplarFixtureParser.parse(markdown)
        }
    }

    s.test("no frontmatter throws") {
        let markdown = "Just a body with no frontmatter."
        try expectThrows {
            _ = try SceneExemplarFixtureParser.parse(markdown)
        }
    }

    s.test("nsfw 'true' and 'false' both parse; other values throw") {
        let okTrue = try SceneExemplarFixtureParser.parse("""
            ---
            fixture_id: x
            title: x
            nsfw: true
            register: explicit-direct
            style_axis: explicit-direct
            ---

            body
            """)
        try expectEqual(okTrue.nsfw, true)

        let okFalse = try SceneExemplarFixtureParser.parse("""
            ---
            fixture_id: x
            title: x
            nsfw: false
            register: n/a
            style_axis: x
            ---

            body
            """)
        try expectEqual(okFalse.nsfw, false)

        try expectThrows {
            _ = try SceneExemplarFixtureParser.parse("""
                ---
                fixture_id: x
                title: x
                nsfw: maybe
                register: n/a
                style_axis: x
                ---

                body
                """)
        }
    }

    return s
}

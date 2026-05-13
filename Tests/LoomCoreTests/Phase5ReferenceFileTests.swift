import Foundation
@testable import LoomCore

/// On-disk frontmatter+body encode/decode for Phase 5 reference texts
/// (LOOM_PLAN.md §5 scope-lock #3). Mirrors `SceneFile`'s shape:
/// YAML-ish frontmatter delimited by `---` lines, scalar
/// key:value pairs, double-quoted string values, prose body after
/// the closing fence.
func phase5ReferenceFileTests() -> TestSuite {
    let s = TestSuite("Phase5ReferenceFile")

    let canonicalDate = LoomISO8601.roundedToMillisecond(Date(timeIntervalSince1970: 1_700_000_000))
    let canonicalDateStr = LoomISO8601.fractionalFormatter.string(from: canonicalDate)

    s.test("encode produces frontmatter + body in the expected shape") {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let ref = ReferenceText(
            id: id,
            name: "Hemingway sample",
            nsfw: false,
            createdAt: canonicalDate,
            body: "He walked to the door.\nIt was cold."
        )
        let out = ReferenceFile.encode(ref)
        try expectTrue(out.hasPrefix("---\n"), "expected opening fence; got: \(out.prefix(20))")
        try expectTrue(out.contains("id: \"\(id.uuidString)\""))
        try expectTrue(out.contains("name: \"Hemingway sample\""))
        try expectTrue(out.contains("nsfw: false"))
        try expectTrue(out.contains("createdAt: \"\(canonicalDateStr)\""))
        try expectTrue(out.hasSuffix("He walked to the door.\nIt was cold."))
    }

    s.test("encode → decode round-trips id, name, nsfw, createdAt, body") {
        let id = UUID()
        let ref = ReferenceText(
            id: id,
            name: "Test ref",
            nsfw: true,
            createdAt: canonicalDate,
            body: "Some prose body."
        )
        let text = ReferenceFile.encode(ref)
        let decoded = try ReferenceFile.decode(text)
        try expectEqual(decoded.id, ref.id)
        try expectEqual(decoded.name, ref.name)
        try expectEqual(decoded.nsfw, ref.nsfw)
        try expectEqual(decoded.createdAt, ref.createdAt)
        try expectEqual(decoded.body, ref.body)
    }

    s.test("decode tolerates trailing newline + blank line between fence and body") {
        let text = """
        ---
        id: "00000000-0000-0000-0000-000000000001"
        name: "x"
        nsfw: false
        createdAt: "\(canonicalDateStr)"
        ---

        Body line one.
        Body line two.
        """
        let decoded = try ReferenceFile.decode(text)
        try expectEqual(decoded.body, "Body line one.\nBody line two.")
    }

    s.test("decode preserves unknown frontmatter keys via extraFrontmatter") {
        // Forward-compat: external editor adds a key Loom doesn't know
        // about. The decode must keep it; the encode must re-emit it.
        let text = """
        ---
        id: "00000000-0000-0000-0000-000000000001"
        name: "x"
        nsfw: false
        createdAt: "\(canonicalDateStr)"
        custom_tag: "user-added-2026-05"
        ---
        Body.
        """
        let decoded = try ReferenceFile.decode(text)
        try expectEqual(decoded.extraFrontmatter["custom_tag"], "user-added-2026-05")
        // And the next encode keeps it.
        let reencoded = ReferenceFile.encode(decoded)
        try expectTrue(reencoded.contains("custom_tag: \"user-added-2026-05\""))
    }

    s.test("decode rejects missing or invalid id") {
        let missing = """
        ---
        name: "x"
        nsfw: false
        createdAt: "\(canonicalDateStr)"
        ---
        Body.
        """
        try expectThrows {
            _ = try ReferenceFile.decode(missing)
        }
        let invalid = """
        ---
        id: "not-a-uuid"
        name: "x"
        nsfw: false
        createdAt: "\(canonicalDateStr)"
        ---
        Body.
        """
        try expectThrows {
            _ = try ReferenceFile.decode(invalid)
        }
    }

    s.test("decode defaults nsfw=false when absent (content-neutrality: explicit opt-in)") {
        let text = """
        ---
        id: "00000000-0000-0000-0000-000000000001"
        name: "x"
        createdAt: "\(canonicalDateStr)"
        ---
        Body.
        """
        let decoded = try ReferenceFile.decode(text)
        try expectFalse(decoded.nsfw)
    }

    s.test("decode handles a missing createdAt by using a current-time fallback (not crash)") {
        // Old hand-written references may not include createdAt;
        // resilience > strictness for a forward-load case.
        let text = """
        ---
        id: "00000000-0000-0000-0000-000000000001"
        name: "x"
        nsfw: false
        ---
        Body.
        """
        // Should not throw; createdAt becomes "around now".
        let before = Date()
        let decoded = try ReferenceFile.decode(text)
        let after = Date()
        try expectTrue(decoded.createdAt >= before.addingTimeInterval(-1))
        try expectTrue(decoded.createdAt <= after.addingTimeInterval(1))
    }

    s.test("encode of body containing internal '---' is preserved on round-trip") {
        // Horizontal-rule lines in prose must not be parsed as a
        // frontmatter close fence (which only fires on the *first*
        // post-open `---` line — the splitter is sound, this test
        // pins that behaviour against regressions).
        let id = UUID()
        let body = "Part one.\n\n---\n\nPart two after the rule."
        let ref = ReferenceText(id: id, name: "x", createdAt: canonicalDate, body: body)
        let text = ReferenceFile.encode(ref)
        let decoded = try ReferenceFile.decode(text)
        try expectEqual(decoded.body, body)
    }

    return s
}

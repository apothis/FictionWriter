import Foundation
@testable import LoomCore

/// Phase 2 #10 (pure-data, format) — entity-reference markdown
/// format. `@<name>` autocomplete inserts the canonical-name +
/// markdown link grammar `[Name](#entity/<uuid>)` so the file
/// round-trips through any markdown editor while keeping the
/// in-prose link invisible at read time (link colour is labelColor,
/// per LOOM_DESIGN_LANGUAGE.md §14.5.1).
func phase2EntityReferenceTests() -> TestSuite {
    let s = TestSuite("Phase2EntityReference")

    s.test("EntityReference.markdown writes [displayName](#entity/<uuid>)") {
        let id = UUID(uuidString: "abcd1234-aaaa-bbbb-cccc-1234567890ab")!
        let ref = EntityReference(
            category: .characters,
            id: id,
            displayName: "Mia"
        )
        try expectEqual(ref.markdown, "[Mia](#entity/abcd1234-aaaa-bbbb-cccc-1234567890ab)")
    }

    s.test("EntityReference.parse recovers the reference from markdown") {
        let id = UUID()
        let md = "[Sherlock Holmes](#entity/\(id.uuidString.lowercased()))"
        let parsed = try expectNotNil(EntityReference.parse(md))
        try expectEqual(parsed.id, id)
        try expectEqual(parsed.displayName, "Sherlock Holmes")
    }

    s.test("EntityReference.parse rejects non-entity links") {
        try expectNil(EntityReference.parse("[Click here](https://example.com)"))
        try expectNil(EntityReference.parse("Just plain text"))
        try expectNil(EntityReference.parse("[Bad](#scene/123)"))
    }

    s.test("EntityReference.parse rejects malformed UUIDs gracefully") {
        try expectNil(EntityReference.parse("[X](#entity/not-a-uuid)"))
    }

    s.test("scanReferences finds every entity link in a prose body, in order") {
        let id1 = UUID()
        let id2 = UUID()
        let prose = """
        [Mia](#entity/\(id1.uuidString.lowercased())) walked across the room.
        She nodded at [Bob](#entity/\(id2.uuidString.lowercased())) and smiled.
        """
        let found = EntityReference.scan(in: prose)
        try expectEqual(found.count, 2)
        try expectEqual(found[0].displayName, "Mia")
        try expectEqual(found[0].id, id1)
        try expectEqual(found[1].displayName, "Bob")
        try expectEqual(found[1].id, id2)
    }

    s.test("scanReferences returns [] for prose with no entity links") {
        let found = EntityReference.scan(in: "Plain prose with no links at all.")
        try expectEqual(found, [])
    }

    s.test("scanReferences ignores ordinary markdown links") {
        let prose = "See [the docs](https://example.com/docs) for details."
        try expectEqual(EntityReference.scan(in: prose), [])
    }

    return s
}

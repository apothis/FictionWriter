import Foundation
@testable import LoomCore

/// Phase 4.5 Session 2 — `CharacterPatch` is the JSON contract for
/// JS→Swift partial updates to a `Character`. Every field is
/// optional: `nil` means "leave this field alone"; a present value
/// (including an empty string or empty array) means "set this
/// field to exactly this value." This lets the React editor send
/// just the fields the user touched rather than the full character,
/// keeping intent payloads small and the diff explicit.
///
/// Semantics for collection fields:
/// - `nil`: leave the array unchanged.
/// - `[]`: clear the array (full replace with empty).
/// - `[x, y, z]`: replace the array entirely with these elements.
///
/// Optional reference fields (`avatarPath`, `canonBrief`):
/// - `nil` in the patch: leave the existing value alone.
/// - Clearing an existing nullable string requires a different
///   intent (out of scope for Session 2; not surfaced in the
///   workspace UI yet anyway).
///
/// `knownFactsBySceneId` is **not** patchable from the workspace —
/// facts are managed via the suggestions queue + facts examiner
/// flows (Sessions 4 + 5).
func phase4_5CharacterPatchTests() -> TestSuite {
    let s = TestSuite("Phase4_5CharacterPatch")

    func baseline() -> Character {
        Character(
            id: UUID(),
            name: "Iris",
            aliases: ["I"],
            role: .protagonist,
            oneLine: "tired",
            description: "She has a bruise above her collarbone.",
            personality: "guarded",
            appearance: "dark hair",
            voice: "low",
            goals: "find out",
            relationships: [],
            avatarPath: nil,
            canonBrief: nil,
            customFields: [],
            injectionMode: .constant
        )
    }

    // MARK: - apply(to:) — field-level patches

    s.test("empty patch leaves the character entirely unchanged") {
        let c = baseline()
        let patch = CharacterPatch()
        let applied = patch.apply(to: c)
        try expectEqual(applied, c)
    }

    s.test("patch with name only changes name, leaves other fields alone") {
        let c = baseline()
        let patch = CharacterPatch(name: "Daniel")
        let applied = patch.apply(to: c)
        try expectEqual(applied.name, "Daniel")
        try expectEqual(applied.aliases, c.aliases)
        try expectEqual(applied.description, c.description)
        try expectEqual(applied.role, c.role)
    }

    s.test("patch with description changes description") {
        let c = baseline()
        let patch = CharacterPatch(description: "now has a black eye too.")
        let applied = patch.apply(to: c)
        try expectEqual(applied.description, "now has a black eye too.")
    }

    s.test("patch with role changes role") {
        let c = baseline()
        let patch = CharacterPatch(role: .antagonist)
        let applied = patch.apply(to: c)
        try expectEqual(applied.role, .antagonist)
    }

    s.test("patch with injectionMode changes injection mode") {
        let c = baseline()
        let patch = CharacterPatch(injectionMode: .keyed)
        let applied = patch.apply(to: c)
        try expectEqual(applied.injectionMode, .keyed)
    }

    s.test("patch with all scalar fields applies all of them") {
        let c = baseline()
        let patch = CharacterPatch(
            name: "Daniel",
            role: .antagonist,
            oneLine: "watcher",
            description: "new desc",
            personality: "cool",
            appearance: "tall",
            voice: "smooth",
            goals: "lure",
            canonBrief: "from a fic",
            injectionMode: .keyed
        )
        let applied = patch.apply(to: c)
        try expectEqual(applied.name, "Daniel")
        try expectEqual(applied.role, .antagonist)
        try expectEqual(applied.oneLine, "watcher")
        try expectEqual(applied.description, "new desc")
        try expectEqual(applied.personality, "cool")
        try expectEqual(applied.appearance, "tall")
        try expectEqual(applied.voice, "smooth")
        try expectEqual(applied.goals, "lure")
        try expectEqual(applied.canonBrief, "from a fic")
        try expectEqual(applied.injectionMode, .keyed)
    }

    // MARK: - Array fields

    s.test("patch with aliases replaces the array entirely") {
        let c = baseline()
        let patch = CharacterPatch(aliases: ["Iris O'Brien", "I.O."])
        let applied = patch.apply(to: c)
        try expectEqual(applied.aliases, ["Iris O'Brien", "I.O."])
    }

    s.test("patch with empty aliases clears the array") {
        let c = baseline()
        let patch = CharacterPatch(aliases: [])
        let applied = patch.apply(to: c)
        try expectEqual(applied.aliases, [])
    }

    s.test("patch with nil aliases leaves the existing array alone") {
        var c = baseline()
        c.aliases = ["first", "second"]
        let patch = CharacterPatch(name: "rename only")
        let applied = patch.apply(to: c)
        try expectEqual(applied.aliases, ["first", "second"])
    }

    s.test("patch with relationships replaces the array") {
        let c = baseline()
        let other = UUID()
        let rel = Relationship(toCharacterId: other, kind: "spouse", notes: "")
        let patch = CharacterPatch(relationships: [rel])
        let applied = patch.apply(to: c)
        try expectEqual(applied.relationships.count, 1)
        try expectEqual(applied.relationships[0].toCharacterId, other)
        try expectEqual(applied.relationships[0].kind, "spouse")
    }

    s.test("patch with customFields replaces the array") {
        let c = baseline()
        let field = CharacterCustomField(label: "house", value: "Slytherin", kind: .text)
        let patch = CharacterPatch(customFields: [field])
        let applied = patch.apply(to: c)
        try expectEqual(applied.customFields.count, 1)
        try expectEqual(applied.customFields[0].label, "house")
        try expectEqual(applied.customFields[0].value, "Slytherin")
    }

    // MARK: - Codable

    s.test("empty patch round-trips through JSON cleanly") {
        let patch = CharacterPatch()
        let data = try JSONEncoder().encode(patch)
        let decoded = try JSONDecoder().decode(CharacterPatch.self, from: data)
        try expectEqual(decoded, patch)
    }

    s.test("populated patch round-trips with every field preserved") {
        let patch = CharacterPatch(
            name: "Daniel",
            aliases: ["D", "Dan"],
            role: .antagonist,
            oneLine: "x",
            description: "y",
            personality: "z",
            appearance: "aa",
            voice: "bb",
            goals: "cc",
            relationships: [Relationship(toCharacterId: UUID(), kind: "boss", notes: "tense")],
            canonBrief: "from a fic",
            customFields: [CharacterCustomField(label: "house", value: "Slytherin", kind: .text)],
            injectionMode: .keyed
        )
        let data = try JSONEncoder().encode(patch)
        let decoded = try JSONDecoder().decode(CharacterPatch.self, from: data)
        try expectEqual(decoded, patch)
    }

    s.test("absent JSON keys decode as nil (the bridge sends only changed fields)") {
        // The React side only sends fields whose value diverged from
        // the snapshot — so a typical patch payload contains 1-2
        // keys, not all 13. Decoder must treat missing keys as nil
        // (no-op for that field) rather than throwing.
        let json = "{\"name\":\"Daniel\"}"
        let decoded = try JSONDecoder().decode(CharacterPatch.self, from: Data(json.utf8))
        try expectEqual(decoded.name, "Daniel")
        try expectNil(decoded.description)
        try expectNil(decoded.aliases)
        try expectNil(decoded.role)
    }

    return s
}

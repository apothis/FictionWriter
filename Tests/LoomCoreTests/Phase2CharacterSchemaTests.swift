import Foundation
@testable import LoomCore

/// Phase 2 #3 — Full Character schema, adding the two genuinely-new
/// fields that today's schema lacks: `canonBrief: String?` and
/// `customFields: [CharacterCustomField]`.
///
/// Per HANDOFF §9.1 row 3 — the rest of the documented "full"
/// shape (role / aliases / personality / appearance / voice / goals
/// / relationships / knownFactsBySceneId) is already present on the
/// struct from Phase 1; `description` continues to serve as the
/// long-form-notes free-form field, so we don't add a parallel
/// `notes` here.
///
/// §9.4 risk #2: keep customFields minimal — label + value + kind
/// enum. No schema-for-the-schema. Phase 5 templates need a place
/// to extend (HP `house`, MCU `team`), not a generic ORM.
func phase2CharacterSchemaTests() -> TestSuite {
    let s = TestSuite("Phase2CharacterSchema")

    s.test("Character defaults canonBrief to nil and customFields to empty") {
        let c = Character.empty(name: "Mia")
        try expectNil(c.canonBrief)
        try expectEqual(c.customFields, [])
    }

    s.test("CustomFieldKind covers the minimal-viable set") {
        let expected: Set<CustomFieldKind> = [.text, .multilineText]
        try expectEqual(Set(CustomFieldKind.allCases), expected)
    }

    s.test("Character with canonBrief + customFields round-trips") {
        let house = CharacterCustomField(label: "House", value: "Slytherin", kind: .text)
        let wand = CharacterCustomField(label: "Wand", value: "Blackthorn, dragon heartstring, 13¾", kind: .text)
        let backstory = CharacterCustomField(
            label: "Backstory",
            value: "Multiple paragraphs of canon-informed history.",
            kind: .multilineText
        )
        var c = Character(name: "Severus Snape")
        c.canonBrief = "From harrypotter.fandom.com — half-blood, Slytherin, Potions/DADA professor."
        c.customFields = [house, wand, backstory]

        let data = try JSONEncoder.loomPretty.encode(c)
        let back = try JSONDecoder.loom.decode(Character.self, from: data)
        try expectEqual(back, c)
    }

    s.test("Phase 1 Character JSON without canonBrief/customFields decodes with defaults — §9.4 risk #1") {
        // Hand-rolled minimal Character JSON (the historical "{name,
        // description} minimum" surface the handoff cites). The decode
        // path must accept this and populate the new fields with their
        // defaults; no migration step required.
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "name": "Mia",
          "description": "She lives in the flat above the bakery."
        }
        """
        let decoded = try JSONDecoder.loom.decode(Character.self, from: Data(json.utf8))
        try expectEqual(decoded.name, "Mia")
        try expectEqual(decoded.description, "She lives in the flat above the bakery.")
        try expectNil(decoded.canonBrief)
        try expectEqual(decoded.customFields, [])
        // Existing-schema fields remain at their defaults too.
        try expectEqual(decoded.role, .supporting)
        try expectEqual(decoded.aliases, [])
    }

    s.test("CharacterCustomField round-trips and preserves label/value/kind") {
        let f = CharacterCustomField(label: "Affiliation", value: "Avengers", kind: .text)
        let data = try JSONEncoder().encode(f)
        let back = try JSONDecoder().decode(CharacterCustomField.self, from: data)
        try expectEqual(back, f)
        try expectEqual(back.label, "Affiliation")
        try expectEqual(back.value, "Avengers")
        try expectEqual(back.kind, .text)
    }

    return s
}

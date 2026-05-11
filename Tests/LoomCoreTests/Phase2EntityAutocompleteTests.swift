import Foundation
@testable import LoomCore

/// Phase 2 #10 (pure-data) — entity-mention autocomplete.
/// Pure projection: given a project + a partial `@name` query
/// (already stripped of the `@`), return a ranked list of candidate
/// entities by name or alias. The NSTextView popover UI wires this
/// in the EditorViewController layer; the data contract lives here.
func phase2EntityAutocompleteTests() -> TestSuite {
    let s = TestSuite("Phase2EntityAutocomplete")

    s.test("empty query returns all entities (alphabetical by name)") {
        var project = Project.empty(title: "T")
        project.bible.characters = [Character(name: "Mia"), Character(name: "Bob")]
        project.bible.settings = [Setting(name: "221B")]

        let matches = EntityAutocomplete.matches(for: "", in: project)
        try expectEqual(matches.map(\.displayName), ["221B", "Bob", "Mia"])
    }

    s.test("prefix match on name (case-insensitive)") {
        var project = Project.empty(title: "T")
        project.bible.characters = [Character(name: "Mia"), Character(name: "Mike"), Character(name: "Bob")]

        let matches = EntityAutocomplete.matches(for: "mi", in: project)
        let names = matches.map(\.displayName)
        try expectEqual(names, ["Mia", "Mike"])
    }

    s.test("alias prefix also matches; displayName is still the canonical name") {
        var project = Project.empty(title: "T")
        var holmes = Character(name: "Sherlock Holmes")
        holmes.aliases = ["Sigerson", "the detective"]
        project.bible.characters = [holmes]

        let matches = EntityAutocomplete.matches(for: "sig", in: project)
        try expectEqual(matches.count, 1)
        try expectEqual(matches[0].displayName, "Sherlock Holmes")
        try expectEqual(matches[0].ref.category, .characters)
        try expectEqual(matches[0].ref.id, holmes.id)
    }

    s.test("query is treated as a prefix, not a substring") {
        // "ock" must NOT match "Sherlock" — that's substring, not prefix.
        var project = Project.empty(title: "T")
        project.bible.characters = [Character(name: "Sherlock Holmes")]

        let matches = EntityAutocomplete.matches(for: "ock", in: project)
        try expectEqual(matches.count, 0)
    }

    s.test("matches include all three entity categories") {
        var project = Project.empty(title: "T")
        project.bible.characters = [Character(name: "Mia")]
        project.bible.settings = [Setting(name: "Mansion")]
        project.bible.objects = [BibleObject(name: "Map")]

        let matches = EntityAutocomplete.matches(for: "m", in: project)
        let categories = Set(matches.map(\.ref.category))
        try expectEqual(categories, [.characters, .settings, .objects])
    }

    s.test("results are de-duplicated when alias and name both match the prefix") {
        var project = Project.empty(title: "T")
        var stark = Character(name: "Tony")
        stark.aliases = ["Tony Stark", "Tone"]
        project.bible.characters = [stark]

        let matches = EntityAutocomplete.matches(for: "to", in: project)
        try expectEqual(matches.count, 1)
        try expectEqual(matches[0].ref.id, stark.id)
    }

    return s
}

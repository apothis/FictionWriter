import Foundation
@testable import LoomCore

/// Sub-step 1.g — character mutations on ProjectSession.
/// "Pure: adding a character to a Project produces expected Bible state."
func phase1CharacterAddTests() -> TestSuite {
    let s = TestSuite("Phase1CharacterAdd")

    s.test("addCharacter appends to bible.characters") {
        let session = ProjectSession(project: Project(title: "T"))
        try expectEqual(session.project.bible.characters.count, 0)
        let character = session.addCharacter(name: "Mia")
        try expectEqual(session.project.bible.characters.count, 1)
        try expectEqual(session.project.bible.characters[0].id, character.id)
        try expectEqual(character.name, "Mia")
    }

    s.test("updateCharacter mutates in place by id, preserves order") {
        let session = ProjectSession(project: Project(title: "T"))
        _ = session.addCharacter(name: "Mia")
        let bob = session.addCharacter(name: "Bob")
        var updated = bob
        updated.description = "The stranger at the door."
        updated.role = .antagonist
        session.updateCharacter(updated)
        try expectEqual(session.project.bible.characters[1].id, bob.id)
        try expectEqual(session.project.bible.characters[1].description, "The stranger at the door.")
        try expectEqual(session.project.bible.characters[1].role, .antagonist)
    }

    s.test("updateCharacter with unknown id is a no-op") {
        let session = ProjectSession(project: Project(title: "T"))
        let mia = session.addCharacter(name: "Mia")
        let stranger = Character(id: UUID(), name: "Stranger")
        session.updateCharacter(stranger)
        try expectEqual(session.project.bible.characters.count, 1)
        try expectEqual(session.project.bible.characters[0].id, mia.id)
    }

    s.test("deleteCharacter removes the matching entry") {
        let session = ProjectSession(project: Project(title: "T"))
        let mia = session.addCharacter(name: "Mia")
        let bob = session.addCharacter(name: "Bob")
        session.deleteCharacter(id: mia.id)
        try expectEqual(session.project.bible.characters.count, 1)
        try expectEqual(session.project.bible.characters[0].id, bob.id)
    }

    s.test("deleteCharacter of an absent id is a no-op") {
        let session = ProjectSession(project: Project(title: "T"))
        _ = session.addCharacter(name: "Mia")
        session.deleteCharacter(id: UUID())
        try expectEqual(session.project.bible.characters.count, 1)
    }

    s.test("character mutations bump the changeCounter") {
        let session = ProjectSession(project: Project(title: "T"))
        let initial = session.changeCounter
        let mia = session.addCharacter(name: "Mia")
        try expectGreaterThan(session.changeCounter, initial)
        let after = session.changeCounter
        var updated = mia
        updated.description = "X"
        session.updateCharacter(updated)
        try expectGreaterThan(session.changeCounter, after)
    }

    return s
}

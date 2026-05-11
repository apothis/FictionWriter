import Foundation
@testable import LoomCore

/// Phase 2 #5 follow-on — Setting + BibleObject mutations on
/// ProjectSession. Mirrors the Phase 1 character-mutation contract
/// (Phase1CharacterAddTests) for the two new entity types so the
/// upcoming list-detail Bible inspector (#4) has CRUD parity across
/// categories.
///
/// Tests-first per the always-TDD memory contract.
func phase2BibleEntityMutationsTests() -> TestSuite {
    let s = TestSuite("Phase2BibleEntityMutations")

    // MARK: Setting

    s.test("addSetting appends to bible.settings") {
        let session = ProjectSession(project: Project(title: "T"))
        try expectEqual(session.project.bible.settings.count, 0)
        let setting = session.addSetting(name: "221B Baker Street")
        try expectEqual(session.project.bible.settings.count, 1)
        try expectEqual(session.project.bible.settings[0].id, setting.id)
        try expectEqual(setting.name, "221B Baker Street")
    }

    s.test("updateSetting mutates in place by id, preserves order") {
        let session = ProjectSession(project: Project(title: "T"))
        _ = session.addSetting(name: "221B")
        let reichenbach = session.addSetting(name: "Reichenbach Falls")
        var updated = reichenbach
        updated.description = "A torrent of black, billowing water."
        updated.sensoryNotes = "Mist; spray; the roar."
        session.updateSetting(updated)
        try expectEqual(session.project.bible.settings[1].id, reichenbach.id)
        try expectEqual(session.project.bible.settings[1].description, "A torrent of black, billowing water.")
        try expectEqual(session.project.bible.settings[1].sensoryNotes, "Mist; spray; the roar.")
    }

    s.test("updateSetting with unknown id is a no-op") {
        let session = ProjectSession(project: Project(title: "T"))
        let baker = session.addSetting(name: "221B")
        let stranger = Setting(name: "Unknown")
        session.updateSetting(stranger)
        try expectEqual(session.project.bible.settings.count, 1)
        try expectEqual(session.project.bible.settings[0].id, baker.id)
    }

    s.test("deleteSetting removes the matching entry") {
        let session = ProjectSession(project: Project(title: "T"))
        let a = session.addSetting(name: "A")
        let b = session.addSetting(name: "B")
        session.deleteSetting(id: a.id)
        try expectEqual(session.project.bible.settings.count, 1)
        try expectEqual(session.project.bible.settings[0].id, b.id)
    }

    s.test("deleteSetting of an absent id is a no-op") {
        let session = ProjectSession(project: Project(title: "T"))
        _ = session.addSetting(name: "A")
        session.deleteSetting(id: UUID())
        try expectEqual(session.project.bible.settings.count, 1)
    }

    s.test("setting mutations bump the changeCounter") {
        let session = ProjectSession(project: Project(title: "T"))
        let initial = session.changeCounter
        let setting = session.addSetting(name: "A")
        try expectGreaterThan(session.changeCounter, initial)
        let after = session.changeCounter
        var updated = setting
        updated.description = "X"
        session.updateSetting(updated)
        try expectGreaterThan(session.changeCounter, after)
    }

    // MARK: BibleObject

    s.test("addObject appends to bible.objects") {
        let session = ProjectSession(project: Project(title: "T"))
        try expectEqual(session.project.bible.objects.count, 0)
        let object = session.addObject(name: "Persian Slipper")
        try expectEqual(session.project.bible.objects.count, 1)
        try expectEqual(session.project.bible.objects[0].id, object.id)
        try expectEqual(object.name, "Persian Slipper")
    }

    s.test("updateObject mutates in place by id, preserves order") {
        let session = ProjectSession(project: Project(title: "T"))
        _ = session.addObject(name: "Pipe")
        let slipper = session.addObject(name: "Slipper")
        var updated = slipper
        updated.description = "Persian; on the mantel."
        updated.significance = "Holmes stores tobacco in the toe."
        session.updateObject(updated)
        try expectEqual(session.project.bible.objects[1].id, slipper.id)
        try expectEqual(session.project.bible.objects[1].description, "Persian; on the mantel.")
        try expectEqual(session.project.bible.objects[1].significance, "Holmes stores tobacco in the toe.")
    }

    s.test("updateObject with unknown id is a no-op") {
        let session = ProjectSession(project: Project(title: "T"))
        let pipe = session.addObject(name: "Pipe")
        let stranger = BibleObject(name: "Unknown")
        session.updateObject(stranger)
        try expectEqual(session.project.bible.objects.count, 1)
        try expectEqual(session.project.bible.objects[0].id, pipe.id)
    }

    s.test("deleteObject removes the matching entry") {
        let session = ProjectSession(project: Project(title: "T"))
        let a = session.addObject(name: "A")
        let b = session.addObject(name: "B")
        session.deleteObject(id: a.id)
        try expectEqual(session.project.bible.objects.count, 1)
        try expectEqual(session.project.bible.objects[0].id, b.id)
    }

    s.test("deleteObject of an absent id is a no-op") {
        let session = ProjectSession(project: Project(title: "T"))
        _ = session.addObject(name: "A")
        session.deleteObject(id: UUID())
        try expectEqual(session.project.bible.objects.count, 1)
    }

    s.test("object mutations bump the changeCounter") {
        let session = ProjectSession(project: Project(title: "T"))
        let initial = session.changeCounter
        let object = session.addObject(name: "A")
        try expectGreaterThan(session.changeCounter, initial)
        let after = session.changeCounter
        var updated = object
        updated.description = "X"
        session.updateObject(updated)
        try expectGreaterThan(session.changeCounter, after)
    }

    return s
}

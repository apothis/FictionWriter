import Foundation
@testable import LoomCore

/// Phase 2 #7 (matcher layer) — BibleInjector. Given a project +
/// recent-prose window, returns which entities should be injected
/// into the prompt. Constant entities always; keyed entities only
/// when their name or any alias appears in the recent prose.
///
/// Pure-data tests-first. The PromptBuilder integration that
/// consumes this comes next (step C).
func phase2BibleInjectorTests() -> TestSuite {
    let s = TestSuite("Phase2BibleInjector")

    s.test("constant entities always inject, even with empty recent prose") {
        var project = Project.empty(title: "T")
        var mia = Character(name: "Mia")
        mia.injectionMode = .constant
        project.bible.characters = [mia]

        let activated = BibleInjector.activated(in: project, recentProse: "")
        try expectEqual(activated.characters.count, 1)
        try expectEqual(activated.characters[0].id, mia.id)
    }

    s.test("keyed entity DOES NOT inject when its name is not in recent prose") {
        var project = Project.empty(title: "T")
        var bob = Character(name: "Bob")
        bob.injectionMode = .keyed
        project.bible.characters = [bob]

        let activated = BibleInjector.activated(in: project, recentProse: "The cat sat on the mat.")
        try expectEqual(activated.characters.count, 0)
    }

    s.test("keyed entity INJECTS when its name appears in recent prose") {
        var project = Project.empty(title: "T")
        var bob = Character(name: "Bob")
        bob.injectionMode = .keyed
        project.bible.characters = [bob]

        let activated = BibleInjector.activated(in: project, recentProse: "Bob opened the door.")
        try expectEqual(activated.characters.count, 1)
        try expectEqual(activated.characters[0].id, bob.id)
    }

    s.test("keyed entity INJECTS when an alias appears in recent prose") {
        var project = Project.empty(title: "T")
        var holmes = Character(name: "Sherlock Holmes")
        holmes.aliases = ["the detective", "Sigerson"]
        holmes.injectionMode = .keyed
        project.bible.characters = [holmes]

        let activated = BibleInjector.activated(
            in: project,
            recentProse: "Sigerson glanced at the door."
        )
        try expectEqual(activated.characters.count, 1)
        try expectEqual(activated.characters[0].id, holmes.id)
    }

    s.test("keyed matching is case-insensitive") {
        var project = Project.empty(title: "T")
        var mia = Character(name: "Mia")
        mia.injectionMode = .keyed
        project.bible.characters = [mia]

        let activated = BibleInjector.activated(in: project, recentProse: "MIA was furious.")
        try expectEqual(activated.characters.count, 1)
    }

    s.test("keyed matching is word-boundary respecting (no substring false positives)") {
        // A keyed entity named "Mia" must NOT match the substring "mia"
        // in "amiable" / "Miami". Word-boundary regex behaviour.
        var project = Project.empty(title: "T")
        var mia = Character(name: "Mia")
        mia.injectionMode = .keyed
        project.bible.characters = [mia]

        let prose = "He was amiable, in Miami, his name sounded like miasma."
        let activated = BibleInjector.activated(in: project, recentProse: prose)
        try expectEqual(activated.characters.count, 0)
    }

    s.test("settings + objects participate in the same keyed/constant logic") {
        var project = Project.empty(title: "T")
        var baker = Setting(name: "221B")
        baker.injectionMode = .keyed
        var slipper = BibleObject(name: "Slipper")
        slipper.injectionMode = .keyed
        var pipe = BibleObject(name: "Pipe")
        pipe.injectionMode = .constant
        project.bible.settings = [baker]
        project.bible.objects = [slipper, pipe]

        let activated = BibleInjector.activated(
            in: project,
            recentProse: "He stood inside 221B, lighting the pipe carefully."
        )
        // 221B keyed → matches; slipper keyed → no match; pipe
        // constant → always.
        try expectEqual(activated.settings.count, 1)
        try expectEqual(activated.settings[0].name, "221B")
        try expectEqual(activated.objects.count, 1)
        try expectEqual(activated.objects[0].name, "Pipe")
    }

    s.test("keyed entity with empty name (or whitespace-only) is skipped, not a match-all bug") {
        var project = Project.empty(title: "T")
        var blank = Character(name: "")
        blank.injectionMode = .keyed
        project.bible.characters = [blank]

        let activated = BibleInjector.activated(in: project, recentProse: "Plenty of prose here.")
        try expectEqual(activated.characters.count, 0)
    }

    s.test("multiple constant + keyed entities resolve correctly") {
        var project = Project.empty(title: "T")
        var mia = Character(name: "Mia"); mia.injectionMode = .constant
        var bob = Character(name: "Bob"); bob.injectionMode = .keyed
        var eve = Character(name: "Eve"); eve.injectionMode = .keyed
        project.bible.characters = [mia, bob, eve]

        let activated = BibleInjector.activated(in: project, recentProse: "Bob met Mia at the corner.")
        // Mia always (constant); Bob matches; Eve doesn't.
        try expectEqual(Set(activated.characters.map(\.name)), ["Mia", "Bob"])
    }

    return s
}

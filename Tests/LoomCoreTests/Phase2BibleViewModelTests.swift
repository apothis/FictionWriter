import Foundation
@testable import LoomCore

/// Phase 2 #4 — pure-data viewmodel behind the list-detail Bible
/// inspector. Owns filter state + selection state + the projection
/// from `Project.bible` to the on-screen section/row list.
///
/// Tests-first per the always-TDD memory contract. The viewmodel
/// stays free of AppKit so this contract pins behaviour the
/// upcoming UI smoke tests don't need to re-prove.
func phase2BibleViewModelTests() -> TestSuite {
    let s = TestSuite("Phase2BibleViewModel")

    s.test("default viewmodel has filter=.all and no selection") {
        let vm = BibleInspectorViewModel()
        try expectEqual(vm.filter, .all)
        try expectNil(vm.selection)
    }

    s.test("BibleCategory.allCases is [.characters, .settings, .objects, .lorebook]") {
        // Order matters — drives the list section render order.
        // Phase 4 §14.1 #10 added .lorebook as the trailing entry.
        try expectEqual(BibleCategory.allCases, [.characters, .settings, .objects, .lorebook])
    }

    s.test("sections(for:) returns one row per category in .all filter, even when empty") {
        let project = Project.empty(title: "T")
        let vm = BibleInspectorViewModel()
        let sections = vm.sections(for: project)
        try expectEqual(sections.count, 4)
        try expectEqual(sections.map(\.category), [.characters, .settings, .objects, .lorebook])
        try expectEqual(sections[0].items, [])
        try expectEqual(sections[1].items, [])
        try expectEqual(sections[2].items, [])
        try expectEqual(sections[3].items, [])
    }

    s.test("sections(for:) projects entities into items with name + ref") {
        var project = Project.empty(title: "T")
        let mia = Character(name: "Mia")
        project.bible.characters = [mia]
        project.bible.settings = [Setting(name: "221B")]
        project.bible.objects = [BibleObject(name: "Pipe")]

        let vm = BibleInspectorViewModel()
        let sections = vm.sections(for: project)
        try expectEqual(sections[0].items.count, 1)
        try expectEqual(sections[0].items[0].name, "Mia")
        try expectEqual(sections[0].items[0].ref.category, .characters)
        try expectEqual(sections[0].items[0].ref.id, mia.id)
        try expectEqual(sections[1].items[0].name, "221B")
        try expectEqual(sections[2].items[0].name, "Pipe")
    }

    s.test("sections(for:) with .category filter returns only that section") {
        var project = Project.empty(title: "T")
        project.bible.characters = [Character(name: "Mia")]
        project.bible.settings = [Setting(name: "221B")]

        let vm = BibleInspectorViewModel(filter: .category(.settings))
        let sections = vm.sections(for: project)
        try expectEqual(sections.count, 1)
        try expectEqual(sections[0].category, .settings)
        try expectEqual(sections[0].items.count, 1)
    }

    s.test("count(of:in:) returns the per-category entity count") {
        var project = Project.empty(title: "T")
        project.bible.characters = [Character(name: "A"), Character(name: "B")]
        project.bible.settings = [Setting(name: "X")]

        let vm = BibleInspectorViewModel()
        try expectEqual(vm.count(of: .characters, in: project), 2)
        try expectEqual(vm.count(of: .settings, in: project), 1)
        try expectEqual(vm.count(of: .objects, in: project), 0)
    }

    s.test("totalCount sums across categories") {
        var project = Project.empty(title: "T")
        project.bible.characters = [Character(name: "A"), Character(name: "B")]
        project.bible.settings = [Setting(name: "X")]
        project.bible.objects = [BibleObject(name: "P"), BibleObject(name: "Q"), BibleObject(name: "R")]

        let vm = BibleInspectorViewModel()
        try expectEqual(vm.totalCount(in: project), 6)
    }

    s.test("entity(for:in:) resolves a ref back to its name") {
        var project = Project.empty(title: "T")
        let mia = Character(name: "Mia")
        project.bible.characters = [mia]

        let vm = BibleInspectorViewModel()
        let ref = BibleEntityRef(category: .characters, id: mia.id)
        let item = vm.entity(for: ref, in: project)
        try expectEqual(item?.name, "Mia")
    }

    s.test("entity(for:in:) returns nil for a stale ref") {
        let project = Project.empty(title: "T")
        let vm = BibleInspectorViewModel()
        let stale = BibleEntityRef(category: .characters, id: UUID())
        try expectNil(vm.entity(for: stale, in: project))
    }

    s.test("reconcileSelection picks the first entity in current filter when none selected") {
        var project = Project.empty(title: "T")
        let mia = Character(name: "Mia")
        project.bible.characters = [mia]

        let vm = BibleInspectorViewModel()
        let changed = vm.reconcileSelection(in: project)
        try expectTrue(changed)
        try expectEqual(vm.selection?.category, .characters)
        try expectEqual(vm.selection?.id, mia.id)
    }

    s.test("reconcileSelection clears a stale selection") {
        let project = Project.empty(title: "T")   // no entities
        let vm = BibleInspectorViewModel(
            filter: .all,
            selection: BibleEntityRef(category: .characters, id: UUID())
        )
        let changed = vm.reconcileSelection(in: project)
        try expectTrue(changed)
        try expectNil(vm.selection)
    }

    s.test("reconcileSelection is a no-op when current selection is still valid") {
        var project = Project.empty(title: "T")
        let mia = Character(name: "Mia")
        project.bible.characters = [mia]

        let vm = BibleInspectorViewModel(
            selection: BibleEntityRef(category: .characters, id: mia.id)
        )
        let changed = vm.reconcileSelection(in: project)
        try expectFalse(changed)
        try expectEqual(vm.selection?.id, mia.id)
    }

    s.test("reconcileSelection respects the current filter when picking a fallback") {
        // Filter is .settings; the only entity is a Character — no
        // valid selection exists for this filter, so selection stays
        // nil.
        var project = Project.empty(title: "T")
        project.bible.characters = [Character(name: "Mia")]

        let vm = BibleInspectorViewModel(filter: .category(.settings))
        let changed = vm.reconcileSelection(in: project)
        try expectFalse(changed)
        try expectNil(vm.selection)
    }

    s.test("setFilter clears a selection that's incompatible with the new filter") {
        var project = Project.empty(title: "T")
        let mia = Character(name: "Mia")
        project.bible.characters = [mia]

        let vm = BibleInspectorViewModel(
            filter: .all,
            selection: BibleEntityRef(category: .characters, id: mia.id)
        )
        vm.setFilter(.category(.settings), in: project)
        try expectEqual(vm.filter, .category(.settings))
        // Mia is a character; not visible under the .settings filter.
        try expectNil(vm.selection)
    }

    s.test("setFilter preserves a selection that's compatible") {
        var project = Project.empty(title: "T")
        let mia = Character(name: "Mia")
        project.bible.characters = [mia]

        let vm = BibleInspectorViewModel(
            filter: .all,
            selection: BibleEntityRef(category: .characters, id: mia.id)
        )
        vm.setFilter(.category(.characters), in: project)
        try expectEqual(vm.filter, .category(.characters))
        try expectEqual(vm.selection?.id, mia.id)
    }

    return s
}

import Foundation
@testable import LoomCore

/// Phase 4 §14.1 #10 — Lorebook entries surface as a first-class
/// section in the Bible inspector. Schema + injection plumbing
/// landed Phase 2 #8 already; this slice ships the inspector list +
/// detail-editor surface so users can rename/edit existing entries
/// (e.g. the sphiratrioth pack) and add their own without dropping
/// to `bible/lorebook.json`.
///
/// Pure-data tests pin the `BibleCategory` + `BibleInspectorViewModel`
/// projection contract; the controller / detail editor are AppKit
/// glue covered by honest-smoke (build + launch).
func phase4LorebookCategoryTests() -> TestSuite {
    let s = TestSuite("Phase4LorebookCategory")

    s.test("BibleCategory.allCases includes .lorebook as the last entry") {
        try expectEqual(BibleCategory.allCases.last, .lorebook)
        try expectEqual(BibleCategory.allCases.count, 4)
    }

    s.test("BibleInspectorViewModel.count(of: .lorebook) reports the project's lorebook count") {
        var project = Project(title: "T")
        project.bible.lorebook = [
            LorebookEntry(name: "Entry A"),
            LorebookEntry(name: "Entry B"),
        ]
        let vm = BibleInspectorViewModel()
        try expectEqual(vm.count(of: .lorebook, in: project), 2)
    }

    s.test("BibleInspectorViewModel.sections includes a Lorebook section in display order") {
        var project = Project(title: "T")
        project.bible.lorebook = [LorebookEntry(name: "Anti-Positive Bias")]
        let vm = BibleInspectorViewModel()
        let sections = vm.sections(for: project)
        try expectEqual(sections.map(\.category), [.characters, .settings, .objects, .lorebook])
        let lorebook = try expectNotNil(sections.first(where: { $0.category == .lorebook }))
        try expectEqual(lorebook.title, "Lorebook")
        try expectEqual(lorebook.items.count, 1)
        try expectEqual(lorebook.items[0].name, "Anti-Positive Bias")
    }

    s.test("BibleInspectorViewModel.totalCount includes lorebook entries") {
        var project = Project(title: "T")
        project.bible.characters = [Character.empty(name: "Mia")]
        project.bible.lorebook = [LorebookEntry(name: "Entry")]
        let vm = BibleInspectorViewModel()
        try expectEqual(vm.totalCount(in: project), 2)
    }

    s.test("category filter set to .lorebook returns only the lorebook section") {
        var project = Project(title: "T")
        project.bible.characters = [Character.empty(name: "Mia")]
        project.bible.lorebook = [LorebookEntry(name: "Entry")]
        let vm = BibleInspectorViewModel(filter: .category(.lorebook))
        let sections = vm.sections(for: project)
        try expectEqual(sections.count, 1)
        try expectEqual(sections[0].category, .lorebook)
    }

    s.test("entity ref lookup resolves lorebook items") {
        var project = Project(title: "T")
        let entry = LorebookEntry(name: "Entry")
        project.bible.lorebook = [entry]
        let vm = BibleInspectorViewModel()
        let ref = BibleEntityRef(category: .lorebook, id: entry.id)
        let item = try expectNotNil(vm.entity(for: ref, in: project))
        try expectEqual(item.name, "Entry")
    }

    return s
}

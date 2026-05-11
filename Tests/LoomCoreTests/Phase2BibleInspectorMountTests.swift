import Foundation
import AppKit
@testable import LoomCore

/// Phase 2 #4 — honest smoke test for the rewritten
/// BibleInspectorViewController (list-detail two-pane).
///
/// UI rendering itself isn't unit-tested; the underlying state
/// transitions (filter, selection, section list) are pinned in
/// Phase2BibleViewModelTests. This suite proves the controller
/// mounts, exposes the viewmodel, and routes the public actions
/// (setFilter, selectEntity, addEntity-in-category) through to
/// the viewmodel + session correctly.
func phase2BibleInspectorMountTests() -> TestSuite {
    let s = TestSuite("Phase2BibleInspectorMount")

    func freshSession() -> ProjectSession {
        ProjectSession(project: Project.empty(title: "Test"))
    }

    s.test("controller mounts with a viewmodel in default state (filter=.all, no selection)") {
        let session = freshSession()
        let vc = BibleInspectorViewController(session: session)
        _ = vc.view
        try expectEqual(vc.viewModel.filter, .all)
        try expectNil(vc.viewModel.selection)
    }

    s.test("on mount, when bible is non-empty, selection is auto-picked via reconcileSelection") {
        let session = freshSession()
        let mia = session.addCharacter(name: "Mia")
        let vc = BibleInspectorViewController(session: session)
        _ = vc.view
        try expectEqual(vc.viewModel.selection?.category, .characters)
        try expectEqual(vc.viewModel.selection?.id, mia.id)
    }

    s.test("setFilter routes to the viewmodel and reconciles selection") {
        let session = freshSession()
        let mia = session.addCharacter(name: "Mia")
        let vc = BibleInspectorViewController(session: session)
        _ = vc.view
        try expectEqual(vc.viewModel.selection?.id, mia.id)

        // Switch to Settings filter; Mia is a character so the
        // selection should clear (no settings exist).
        vc.setFilter(.category(.settings))
        try expectEqual(vc.viewModel.filter, .category(.settings))
        try expectNil(vc.viewModel.selection)

        // Switch back to All; reconcile picks Mia again.
        vc.setFilter(.all)
        try expectEqual(vc.viewModel.filter, .all)
        try expectEqual(vc.viewModel.selection?.id, mia.id)
    }

    s.test("selectEntity routes to the viewmodel") {
        let session = freshSession()
        let mia = session.addCharacter(name: "Mia")
        let bob = session.addCharacter(name: "Bob")
        let vc = BibleInspectorViewController(session: session)
        _ = vc.view

        // Default selection is the first character (Mia per add order).
        try expectEqual(vc.viewModel.selection?.id, mia.id)
        vc.selectEntity(BibleEntityRef(category: .characters, id: bob.id))
        try expectEqual(vc.viewModel.selection?.id, bob.id)
    }

    s.test("addEntity(in:) routes through the session for each category") {
        let session = freshSession()
        let vc = BibleInspectorViewController(session: session)
        _ = vc.view

        let c = vc.addEntity(in: .characters)
        try expectEqual(session.project.bible.characters.count, 1)
        try expectEqual(session.project.bible.characters[0].id, c.id)
        try expectEqual(c.category, .characters)

        let st = vc.addEntity(in: .settings)
        try expectEqual(session.project.bible.settings.count, 1)
        try expectEqual(session.project.bible.settings[0].id, st.id)
        try expectEqual(st.category, .settings)

        let o = vc.addEntity(in: .objects)
        try expectEqual(session.project.bible.objects.count, 1)
        try expectEqual(session.project.bible.objects[0].id, o.id)
        try expectEqual(o.category, .objects)
    }

    s.test("addEntity selects the newly-created entity") {
        let session = freshSession()
        let vc = BibleInspectorViewController(session: session)
        _ = vc.view
        let added = vc.addEntity(in: .settings)
        try expectEqual(vc.viewModel.selection, added)
    }

    s.test("deleteSelected routes through the session and clears selection") {
        let session = freshSession()
        let mia = session.addCharacter(name: "Mia")
        let vc = BibleInspectorViewController(session: session)
        _ = vc.view
        try expectEqual(vc.viewModel.selection?.id, mia.id)

        vc.deleteSelected()
        try expectEqual(session.project.bible.characters.count, 0)
        try expectNil(vc.viewModel.selection)
    }

    s.test("deleteSelected is a no-op when nothing is selected") {
        let session = freshSession()
        let vc = BibleInspectorViewController(session: session)
        _ = vc.view
        try expectNil(vc.viewModel.selection)
        vc.deleteSelected()   // must not crash
        try expectEqual(session.project.bible.characters.count, 0)
    }

    return s
}

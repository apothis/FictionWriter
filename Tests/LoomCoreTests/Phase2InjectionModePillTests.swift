import Foundation
import AppKit
@testable import LoomCore

/// Phase 2 #7 (UI layer) — per-entity injection-mode pill on the
/// Bible detail editor. Mounts the inspector with one of each entity
/// type selected and verifies the public `setInjectionMode(_:)` API
/// routes through to the session.
func phase2InjectionModePillTests() -> TestSuite {
    let s = TestSuite("Phase2InjectionModePill")

    func freshSession() -> ProjectSession {
        ProjectSession(project: Project(title: "T"))
    }

    s.test("Character: setInjectionMode(.keyed) round-trips through session") {
        let session = freshSession()
        let mia = session.addCharacter(name: "Mia")
        let vc = BibleInspectorViewController(session: session)
        _ = vc.view
        vc.selectEntity(BibleEntityRef(category: .characters, id: mia.id))
        vc.setInjectionMode(.keyed)
        let updated = try expectNotNil(session.project.bible.characters.first { $0.id == mia.id })
        try expectEqual(updated.injectionMode, .keyed)
        // Switching back to .constant also writes through.
        vc.setInjectionMode(.constant)
        let again = try expectNotNil(session.project.bible.characters.first { $0.id == mia.id })
        try expectEqual(again.injectionMode, .constant)
    }

    s.test("Setting: setInjectionMode(.keyed) round-trips through session") {
        let session = freshSession()
        let baker = session.addSetting(name: "221B")
        let vc = BibleInspectorViewController(session: session)
        _ = vc.view
        vc.selectEntity(BibleEntityRef(category: .settings, id: baker.id))
        vc.setInjectionMode(.keyed)
        let updated = try expectNotNil(session.project.bible.settings.first { $0.id == baker.id })
        try expectEqual(updated.injectionMode, .keyed)
    }

    s.test("BibleObject: setInjectionMode(.keyed) round-trips through session") {
        let session = freshSession()
        let pipe = session.addObject(name: "Pipe")
        let vc = BibleInspectorViewController(session: session)
        _ = vc.view
        vc.selectEntity(BibleEntityRef(category: .objects, id: pipe.id))
        vc.setInjectionMode(.keyed)
        let updated = try expectNotNil(session.project.bible.objects.first { $0.id == pipe.id })
        try expectEqual(updated.injectionMode, .keyed)
    }

    s.test("setInjectionMode is a no-op when no entity is selected") {
        let session = freshSession()
        let vc = BibleInspectorViewController(session: session)
        _ = vc.view
        try expectNil(vc.viewModel.selection)
        vc.setInjectionMode(.keyed)   // must not crash; no entity to touch
        try expectEqual(session.project.bible.characters.count, 0)
    }

    return s
}

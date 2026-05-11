import Foundation
import AppKit
@testable import LoomCore

/// Phase 2 #11 (UI integration) — BibleInspectorViewController
/// surfaces the per-entity mention count from MentionIndex. The
/// sparkline view itself is honest UI; this smoke pins the controller
/// API the view (or its replacement label "N mentions") plugs into.
func phase2MentionDisplayTests() -> TestSuite {
    let s = TestSuite("Phase2MentionDisplay")

    s.test("mentionCount(for:) reports zero for an entity with no mentions") {
        let session = ProjectSession(project: Project(title: "T"))
        let mia = session.addCharacter(name: "Mia")
        let scene = session.addScene(title: "S1")
        session.updateProse(id: scene.id, prose: "Plain prose, no mentions.")

        let vc = BibleInspectorViewController(session: session)
        _ = vc.view
        let ref = BibleEntityRef(category: .characters, id: mia.id)
        try expectEqual(vc.mentionCount(for: ref), 0)
    }

    s.test("mentionCount(for:) reports the markdown-link count across all scenes") {
        let session = ProjectSession(project: Project(title: "T"))
        let mia = session.addCharacter(name: "Mia")
        let s1 = session.addScene(title: "A")
        let s2 = session.addScene(title: "B")
        let s3 = session.addScene(title: "C")
        let mention = EntityReference(category: .characters, id: mia.id, displayName: "Mia").markdown
        session.updateProse(id: s1.id, prose: "\(mention) opened the door.")
        session.updateProse(id: s2.id, prose: "No mention here.")
        session.updateProse(id: s3.id, prose: "\(mention) and \(mention).")

        let vc = BibleInspectorViewController(session: session)
        _ = vc.view
        try expectEqual(vc.mentionCount(for: BibleEntityRef(category: .characters, id: mia.id)), 3)
    }

    s.test("mentionCount(for:) updates after the prose changes") {
        let session = ProjectSession(project: Project(title: "T"))
        let mia = session.addCharacter(name: "Mia")
        let scene = session.addScene(title: "S1")
        let mention = EntityReference(category: .characters, id: mia.id, displayName: "Mia").markdown

        let vc = BibleInspectorViewController(session: session)
        _ = vc.view
        let ref = BibleEntityRef(category: .characters, id: mia.id)
        try expectEqual(vc.mentionCount(for: ref), 0)

        session.updateProse(id: scene.id, prose: "\(mention) walked away.")
        try expectEqual(vc.mentionCount(for: ref), 1)
    }

    return s
}

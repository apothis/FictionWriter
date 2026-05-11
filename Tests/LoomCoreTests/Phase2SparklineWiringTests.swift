import Foundation
import AppKit
@testable import LoomCore

/// Phase 2.5 (#11 follow-on) — Bible inspector serves the sparkline
/// its data + routes marker clicks back to the session.
func phase2SparklineWiringTests() -> TestSuite {
    let s = TestSuite("Phase2SparklineWiring")

    s.test("sparklineLayout(for:) computes a layout from current scenes + mention index") {
        let session = ProjectSession(project: Project(title: "T"))
        let mia = session.addCharacter(name: "Mia")
        let s1 = session.addScene(title: "A")
        let s2 = session.addScene(title: "B")
        let s3 = session.addScene(title: "C")
        let mention = EntityReference(category: .characters, id: mia.id, displayName: "Mia").markdown
        session.updateProse(id: s1.id, prose: "\(mention) opens the door.")
        session.updateProse(id: s2.id, prose: "No mention.")
        session.updateProse(id: s3.id, prose: "\(mention) closes it.")

        let vc = BibleInspectorViewController(session: session)
        _ = vc.view
        let ref = BibleEntityRef(category: .characters, id: mia.id)
        let layout = vc.sparklineLayout(for: ref)
        try expectEqual(layout.totalScenes, 3)
        try expectEqual(layout.markers.count, 2)
        try expectEqual(layout.markers[0].sceneId, s1.id)
        try expectEqual(layout.markers[1].sceneId, s3.id)
    }

    s.test("scrollToScene(_:) routes through session.selectScene(id:)") {
        let session = ProjectSession(project: Project(title: "T"))
        _ = session.addCharacter(name: "Mia")
        let s1 = session.addScene(title: "A")
        let s2 = session.addScene(title: "B")
        session.selectScene(id: s1.id)

        let vc = BibleInspectorViewController(session: session)
        _ = vc.view
        try expectEqual(session.currentSceneId, s1.id)
        vc.scrollToScene(s2.id)
        try expectEqual(session.currentSceneId, s2.id)
    }

    return s
}

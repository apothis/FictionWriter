import Foundation
import AppKit
@testable import LoomCore

/// Phase 2 #10 (UI integration) — `EditorViewController` exposes a
/// public mention-context API: detect what's under the cursor and
/// apply a chosen match by replacing the `@xxx` substring with the
/// canonical entity markdown.
///
/// The actual popover view is honest UI — mount it, type, watch
/// suggestions appear. This suite pins the controller-level contract
/// (what the popover plugs into).
func phase2EditorMentionTests() -> TestSuite {
    let s = TestSuite("Phase2EditorMention")

    func freshSession(with characters: [String]) -> ProjectSession {
        let session = ProjectSession(project: Project(title: "T"))
        for n in characters { _ = session.addCharacter(name: n) }
        return session
    }

    s.test("currentMentionContext returns nil when there's no @-context at the cursor") {
        let session = freshSession(with: ["Mia"])
        let vc = EditorViewController(session: session)
        _ = vc.view
        let scene = session.addScene(title: "S1")
        session.selectScene(id: scene.id)
        session.updateProse(id: scene.id, prose: "Plain prose.")
        vc.reloadFromSession()
        vc.setCursorOffsetForTesting(scene.prose.count)
        try expectNil(vc.currentMentionContext())
    }

    s.test("currentMentionContext returns context + matches when cursor is in @-mention") {
        let session = freshSession(with: ["Mia", "Mike", "Bob"])
        let vc = EditorViewController(session: session)
        _ = vc.view
        let scene = session.addScene(title: "S1")
        session.selectScene(id: scene.id)
        session.updateProse(id: scene.id, prose: "Hello @M")
        vc.reloadFromSession()
        vc.setCursorOffsetForTesting(8)
        let result = try expectNotNil(vc.currentMentionContext())
        try expectEqual(result.context.partialQuery, "M")
        try expectEqual(Set(result.matches.map(\.displayName)), ["Mia", "Mike"])
    }

    s.test("applyMention replaces the @-substring with the entity markdown") {
        let session = freshSession(with: ["Mia"])
        let vc = EditorViewController(session: session)
        _ = vc.view
        let scene = session.addScene(title: "S1")
        session.selectScene(id: scene.id)
        session.updateProse(id: scene.id, prose: "Hello @Mia")
        vc.reloadFromSession()
        vc.setCursorOffsetForTesting(10)   // after "@Mia"

        let result = try expectNotNil(vc.currentMentionContext())
        let miaMatch = try expectNotNil(result.matches.first { $0.displayName == "Mia" })
        vc.applyMention(miaMatch)
        let updated = try expectNotNil(session.scenes[scene.id])
        try expectTrue(updated.prose.hasPrefix("Hello [Mia](#entity/"))
        try expectTrue(updated.prose.hasSuffix(")"))
    }

    return s
}

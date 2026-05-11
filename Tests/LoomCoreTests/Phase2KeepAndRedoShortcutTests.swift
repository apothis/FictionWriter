import Foundation
import AppKit
@testable import LoomCore

/// Phase 2 follow-on (HANDOFF §9.2) — wire ⌘⇧R for Keep & Redo.
/// The tray button label promises the binding; this suite pins the
/// controller-level routing it plugs into. The NSEvent local monitor
/// in `viewDidAppear` is honest UI (verified by running the app).
func phase2KeepAndRedoShortcutTests() -> TestSuite {
    let s = TestSuite("Phase2KeepAndRedoShortcut")

    s.test("triggerKeepAndRedoShortcut is a no-op when the machine is .idle") {
        let session = ProjectSession(project: Project(title: "T"))
        let vc = EditorViewController(session: session)
        _ = vc.view
        try expectEqual(vc.acceptanceState, .idle)
        vc.triggerKeepAndRedoShortcut()    // must not crash
        try expectEqual(vc.acceptanceState, .idle)
    }

    s.test("triggerKeepAndRedoShortcut transitions out of .awaiting back to .idle") {
        let session = ProjectSession(project: Project(title: "T"))
        let scene = session.addScene(title: "S1")
        session.selectScene(id: scene.id)
        session.updateProse(id: scene.id, prose: "Some prose here.")

        let vc = EditorViewController(session: session)
        _ = vc.view
        vc.reloadFromSession()

        // Prime acceptance state — pretend a generation just landed.
        let range = NSRange(location: 0, length: 4)
        vc.primeAcceptanceForTesting(range: range, mode: .rewrite)
        try expectEqual(vc.acceptanceState, .awaiting(insertedRange: range, mode: .rewrite))

        vc.triggerKeepAndRedoShortcut()
        try expectEqual(vc.acceptanceState, .idle)
    }

    return s
}

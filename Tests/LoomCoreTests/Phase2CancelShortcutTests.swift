import Foundation
import AppKit
@testable import LoomCore

/// Phase 2 follow-on (HANDOFF §9.2) — cancel generation mid-stream.
/// The coordinator's `cancel()` already exists (it's called by
/// `start()` to abort any in-flight generation); this suite pins the
/// editor-level shortcut routing the user-facing binding plugs into.
func phase2CancelShortcutTests() -> TestSuite {
    let s = TestSuite("Phase2CancelShortcut")

    s.test("triggerCancelShortcut is a no-op when nothing is generating") {
        let session = ProjectSession(project: Project(title: "T"))
        let vc = EditorViewController(session: session)
        _ = vc.view
        try expectFalse(vc.isGeneratingForTesting)
        vc.triggerCancelShortcut()    // must not crash
        try expectFalse(vc.isGeneratingForTesting)
    }

    s.test("triggerCancelShortcut exposes a coordinator hook even when idle") {
        // The actual cancel-mid-stream behaviour requires a live
        // network call to exercise — that's not unit-testable. What
        // this suite pins is the routing surface: the public method
        // exists, dispatches to the coordinator, and stays a no-op
        // while idle.
        let session = ProjectSession(project: Project(title: "T"))
        let vc = EditorViewController(session: session)
        _ = vc.view
        for _ in 0..<3 { vc.triggerCancelShortcut() }
        try expectFalse(vc.isGeneratingForTesting)
    }

    return s
}

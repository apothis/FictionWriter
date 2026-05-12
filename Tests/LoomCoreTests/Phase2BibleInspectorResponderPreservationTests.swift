import Foundation
import AppKit
@testable import LoomCore

/// Regression suite for the inspector responder-clobber bug
/// reported 2026-05-12 (Phase 4.5 side-fix, surfaced during the
/// Bible Workspace pilot but unrelated to it).
///
/// **Symptom**: typing into the character description text view
/// only registered one keystroke at a time — each keystroke
/// triggered `BibleDetailBridge.textDidChange` → `writeBack()` →
/// `ProjectSession.updateCharacter` → `markChanged` →
/// `didChangeNotification` → `BibleInspectorViewController.reload()`
/// → `renderDetail()` which tore down the entire detail editor
/// view tree on every keystroke. Tearing down the NSTextView
/// removed first responder; the next keystroke had no responder
/// and produced the system beep.
///
/// **Fix**: `renderDetail()` preserves the existing detail editor
/// when the selected entity hasn't changed. Field values that may
/// have shifted out of band (mention count, suggestions, etc.) are
/// diff-applied in place via `BibleDetailEditor.refreshInPlace()`.
/// The text view + name field NSResponders survive across the
/// notification, so subsequent keystrokes find their responder.
///
/// This is a thin honest-smoke suite — the responder layer itself
/// can't be unit-tested without a running NSApp event loop. We
/// pin: the editor INSTANCE identity is stable across notifications
/// that don't change the selection.
func phase2BibleInspectorResponderPreservationTests() -> TestSuite {
    let s = TestSuite("Phase2BibleInspectorResponderPreservation")

    func freshSession() -> ProjectSession {
        ProjectSession(project: Project.empty(title: "Test"))
    }

    /// Pump the runloop briefly so `didChangeNotification` observers
    /// registered with `queue: .main` get a chance to dispatch
    /// before the test assertions run. The observer block is queued
    /// onto OperationQueue.main asynchronously, so a synchronous
    /// `session.updateCharacter(...)` returns before the reload
    /// fires. See `feedback_tdd_async_callbacks` memory.
    func flushMainQueue() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }

    s.test("detail editor instance survives a self-write notification (same selection)") {
        let session = freshSession()
        _ = session.addCharacter(name: "Iris")
        let vc = BibleInspectorViewController(session: session)
        _ = vc.view
        // Sanity: a detail editor was mounted for the auto-selected
        // first character.
        let beforeIdentity = try expectNotNil(vc.__detailEditorIdentityForTests)
        // Self-write: mutate the same character (mirrors what
        // BibleDetailEditor.writeBack does after each keystroke).
        var c = session.project.bible.characters[0]
        c.description = "added a letter"
        session.updateCharacter(c)
        flushMainQueue()
        // After the didChangeNotification fires + the observer block
        // dispatches, the detail editor must be the SAME instance —
        // not a fresh one. A torn-down + rebuilt instance would have
        // a different mountToken.
        let afterIdentity = try expectNotNil(vc.__detailEditorIdentityForTests)
        try expectEqual(afterIdentity, beforeIdentity)
    }

    s.test("detail editor IS rebuilt when the selected entity changes") {
        let session = freshSession()
        let iris = session.addCharacter(name: "Iris")
        let daniel = session.addCharacter(name: "Daniel")
        let vc = BibleInspectorViewController(session: session)
        _ = vc.view
        // Auto-selects the first character (Iris by add order).
        let irisIdentity = try expectNotNil(vc.__detailEditorIdentityForTests)
        // Switching selection MUST rebuild — we're now editing a
        // different entity.
        vc.selectEntity(BibleEntityRef(category: .characters, id: daniel.id))
        let danielIdentity = try expectNotNil(vc.__detailEditorIdentityForTests)
        try expectFalse(danielIdentity == irisIdentity,
            "detail editor should be rebuilt on selection change; instance preserved instead")
        _ = iris
    }

    s.test("detail editor is torn down when the selected entity is deleted") {
        let session = freshSession()
        let iris = session.addCharacter(name: "Iris")
        let vc = BibleInspectorViewController(session: session)
        _ = vc.view
        try expectNotNil(vc.__detailEditorIdentityForTests)
        // Delete the selected character — reconcileSelection sets
        // selection to nil (it doesn't auto-pick a replacement);
        // renderDetail then tears down the editor and shows the
        // empty placeholder.
        session.deleteCharacter(id: iris.id)
        flushMainQueue()
        try expectNil(vc.__detailEditorIdentityForTests)
    }

    return s
}

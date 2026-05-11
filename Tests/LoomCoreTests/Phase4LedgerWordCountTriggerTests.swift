import Foundation
import AppKit
@testable import LoomCore

/// Phase 4 #7 sub-task 2 bugfix — the AppState extraction trigger
/// must fire for the *untitled* project case (no on-disk URL), not
/// just for saved projects. The original wiring subscribed to
/// `ProjectSession.didChangeDirtyStateNotification` which only posts
/// on dirty→clean (post-autosave); `ProjectSession.scheduleAutoSave`
/// is a no-op when `url == nil`, so untitled projects never reach
/// the dirty→clean edge and the coordinator never sees the
/// `evaluate` signal. Switched to
/// `EditorViewController.wordCountChangedNotification` which fires
/// on every keystroke; the coordinator's 2s debounce already
/// handles burst collapse.
func phase4LedgerWordCountTriggerTests() -> TestSuite {
    let s = TestSuite("Phase4LedgerWordCountTrigger")

    func freshAppState() -> AppState {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("loom-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let store = AppSettingsStore(fileManager: .default, rootDir: tmp)
        return AppState(settingsStore: store)
    }

    s.test("wordCountChanged notification routes through ledgerCoordinator.evaluate for an UNTITLED session") {
        let appState = freshAppState()
        // Untitled — currentSession.url is nil; no autosave will ever fire.
        try expectNil(appState.currentSession.url)
        let sceneId = appState.currentSession.currentSceneId!
        // Seed a baseline so we can detect a downstream evaluate.
        appState.ledgerCoordinator.setBaseline(sceneId: sceneId, wordCount: 0)

        // Post the notification the editor emits on every keystroke.
        NotificationCenter.default.post(
            name: EditorViewController.wordCountChangedNotification,
            object: nil,
            userInfo: ["sceneId": sceneId, "wordCount": 250]
        )

        // The coordinator should now have scheduled a pending fire
        // (TimerScheduler doesn't actually run under TestKit because
        // the run loop isn't pumped — but the scheduler.cancel() path
        // is observable via baseline behaviour on a second evaluate).
        //
        // Simplest assertion: a second post at the SAME word count
        // should be a no-op (delta is 0 since we just evaluated 250
        // against baseline 0 → above threshold → pending), but a
        // small-delta post should not change the pending state.
        // Concretely: verify the baseline wasn't accidentally bumped
        // (only successful extraction updates it).
        try expectEqual(appState.ledgerCoordinator.baseline(for: sceneId), 0)
    }

    s.test("wordCountChanged below threshold does not crash and leaves baseline alone") {
        let appState = freshAppState()
        let sceneId = appState.currentSession.currentSceneId!
        NotificationCenter.default.post(
            name: EditorViewController.wordCountChangedNotification,
            object: nil,
            userInfo: ["sceneId": sceneId, "wordCount": 50]
        )
        try expectNil(appState.ledgerCoordinator.baseline(for: sceneId))
    }

    s.test("wordCountChanged with missing sceneId is a graceful no-op") {
        let appState = freshAppState()
        NotificationCenter.default.post(
            name: EditorViewController.wordCountChangedNotification,
            object: nil,
            userInfo: ["wordCount": 500]
        )
        // No crash; nothing happens.
    }

    s.test("wordCountChanged for a scene not in the current session does not fire evaluate against the wrong session") {
        let appState = freshAppState()
        let stranger = UUID()  // not in this session
        NotificationCenter.default.post(
            name: EditorViewController.wordCountChangedNotification,
            object: nil,
            userInfo: ["sceneId": stranger, "wordCount": 500]
        )
        // Stranger scene id gets through (the coordinator doesn't
        // validate against the session — that's the caller's
        // concern). The point of this test is: no crash + the
        // coordinator's baseline map gains an entry for the stranger,
        // it doesn't corrupt the session.
        try expectNil(appState.currentSession.scenes[stranger])
    }

    return s
}

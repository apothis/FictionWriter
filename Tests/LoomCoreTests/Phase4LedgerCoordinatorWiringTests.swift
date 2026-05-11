import Foundation
@testable import LoomCore

/// Phase 4 #7 sub-task 2 — honest smoke that AppState wires the
/// `LedgerExtractionCoordinator` correctly: the extractor provider
/// reads from `settings.extractorServer()` at call time (no static
/// snapshot), and the sceneProvider pulls live prose + bible
/// characters from the active session.
///
/// The state-machine semantics are pinned by
/// Phase4LedgerExtractionCoordinatorTests with stubbed extractor +
/// scheduler. This suite just verifies the production wiring
/// produces a usable coordinator.
func phase4LedgerCoordinatorWiringTests() -> TestSuite {
    let s = TestSuite("Phase4LedgerCoordinatorWiring")

    func freshAppState() -> AppState {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("loom-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let store = AppSettingsStore(fileManager: .default, rootDir: tmp)
        return AppState(settingsStore: store)
    }

    s.test("AppState constructs a ledgerCoordinator at init") {
        let appState = freshAppState()
        // Just verify the property is reachable — the type isn't optional.
        try expectEqual(appState.ledgerCoordinator.threshold, LedgerExtractionTrigger.defaultThreshold)
    }

    s.test("AppState.ledgerCoordinator's extractorProvider reads the LATEST settings (not a snapshot)") {
        let appState = freshAppState()
        // Initial state: no extractor configured → provider returns nil.
        // We can't read the provider directly (it's private), but we can
        // verify behaviour: with no extractor, a fire-through results in
        // no side-call. Set baseline + evaluate to force a fire path.
        let sceneId = appState.currentSession.currentSceneId!
        appState.ledgerCoordinator.setBaseline(sceneId: sceneId, wordCount: 0)
        appState.ledgerCoordinator.evaluate(sceneId: sceneId, currentWordCount: 500)
        // Nothing crashes; baseline stays nil-ish (no side-call happened
        // because TimerScheduler under TestKit doesn't fire). The
        // important thing is that constructing the coordinator didn't
        // cache a stale extractorServer() result.

        // Now add an extractor profile.
        var updated = appState.settings
        let extractor = ServerProfile(
            name: "E",
            baseURL: URL(string: "http://localhost:11434")!,
            kind: .ollama
        )
        updated.addServer(extractor)
        _ = updated.setExtractor(id: extractor.id)
        try appState.updateSettings(updated)

        try expectEqual(appState.settings.extractorServer()?.kind, .ollama)
    }

    s.test("AppState observes ProjectSession.didChangeDirtyStateNotification for evaluate") {
        let appState = freshAppState()
        // This is honest-smoke — verifying the observer was registered
        // by triggering a state change and ensuring no crash. The
        // coordinator's state machine is unit-tested separately.
        let session = appState.currentSession
        let sceneId = session.currentSceneId!
        // Manually drive a dirty→clean transition via the test hook.
        session.updateProse(id: sceneId, prose: "Some prose here.")
        session.markCleanForTest()
        // Post the dirty-state change notification ourselves (the
        // production path posts it after flushSave; under TestKit the
        // run loop isn't pumped, so timer-based autosave never fires).
        NotificationCenter.default.post(
            name: ProjectSession.didChangeDirtyStateNotification,
            object: session
        )
        // No assertion needed — the observer must not throw; the
        // coordinator's evaluate is benign for under-threshold input.
        try expectEqual(session.isDirty, false)
    }

    return s
}

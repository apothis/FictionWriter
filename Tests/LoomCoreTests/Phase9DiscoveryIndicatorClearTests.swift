import Foundation
@testable import LoomCore

/// Phase 9 — the in-flight discovery indicator must clear on EVERY
/// completion path, not just the "produced ≥1 proposal" one.
///
/// Live-smoke bug: a 3587-word scene ran discovery to completion
/// (`entity-discovery produced 0 proposals`) but the amber
/// "Discovering 1 scene…" pulse-dot never cleared. Root cause:
/// `handleEntityDiscoveryComplete`'s success branch did
/// `guard !proposals.isEmpty else { return }` BEFORE posting
/// `proposedEntitiesDidChangeNotification` — so a null-discovery
/// result cleared `discoveringSceneIds` in memory but never told
/// the Bible Workspace to rebuild its snapshot.
///
/// The fix posts the notification unconditionally on exit. These
/// tests pin all three completion paths.
func phase9DiscoveryIndicatorClearTests() -> TestSuite {
    let s = TestSuite("Phase9DiscoveryIndicatorClear")

    func freshAppState() -> AppState {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("loom-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let store = AppSettingsStore(fileManager: .default, rootDir: tmp)
        return AppState(settingsStore: store)
    }

    struct StubError: Error {}

    func tempProjectURL() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("loom-indicator-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    s.test("0-proposal discovery posts proposedEntitiesDidChange (clears indicator)") {
        let appState = freshAppState()
        let project = tempProjectURL()
        defer { try? FileManager.default.removeItem(at: project) }
        var fired = false
        let token = NotificationCenter.default.addObserver(
            forName: AppState.proposedEntitiesDidChangeNotification,
            object: appState, queue: nil
        ) { _ in fired = true }
        defer { NotificationCenter.default.removeObserver(token) }

        appState.handleEntityDiscoveryComplete(
            projectURL: project,
            sceneId: UUID(),
            result: .success([])
        )
        try expectTrue(fired, "empty-success must post the change notification")
    }

    s.test("failed discovery posts proposedEntitiesDidChange (clears indicator)") {
        let appState = freshAppState()
        let project = tempProjectURL()
        defer { try? FileManager.default.removeItem(at: project) }
        var fired = false
        let token = NotificationCenter.default.addObserver(
            forName: AppState.proposedEntitiesDidChangeNotification,
            object: appState, queue: nil
        ) { _ in fired = true }
        defer { NotificationCenter.default.removeObserver(token) }

        appState.handleEntityDiscoveryComplete(
            projectURL: project,
            sceneId: UUID(),
            result: .failure(StubError())
        )
        try expectTrue(fired, "failure must post the change notification")
    }

    return s
}

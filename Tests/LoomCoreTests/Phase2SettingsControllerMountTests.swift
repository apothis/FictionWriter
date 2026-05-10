import Foundation
import AppKit
@testable import LoomCore

/// Phase 2 (Settings UI): honest smoke for SettingsViewController.
/// Verifies the controller instantiates with both child VCs, can
/// switch tabs, and that the Servers tab's mutation surface
/// round-trips through AppState (servers added/removed/promoted
/// land in `AppState.settings.servers` and persist via
/// `AppState.updateSettings`).
///
/// UI rendering itself isn't unit-tested; the underlying
/// `AppSettings.addServer/removeServer/setDefault/updateServer`
/// mutations are pure-data and tested in
/// Phase2AppSettingsMutationsTests.
func phase2SettingsControllerMountTests() -> TestSuite {
    let s = TestSuite("Phase2SettingsControllerMount")

    func freshAppState() -> AppState {
        // Use an in-memory store rooted at a temp dir so the test
        // doesn't touch the user's real settings.json.
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("loom-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let store = AppSettingsStore(fileManager: .default, rootDir: tmp)
        return AppState(settingsStore: store)
    }

    s.test("controller instantiates with two tabs and starts on .servers") {
        let appState = freshAppState()
        let vc = SettingsViewController(appState: appState)
        _ = vc.view  // force loadView
        try expectEqual(vc.currentTab, .servers)
        try expectNotNil(vc.serversTabVC)
        try expectNotNil(vc.projectTabVC)
    }

    s.test("showTab(.project) switches the active tab") {
        let appState = freshAppState()
        let vc = SettingsViewController(appState: appState)
        _ = vc.view
        vc.showTab(.project)
        try expectEqual(vc.currentTab, .project)
        vc.showTab(.servers)
        try expectEqual(vc.currentTab, .servers)
    }

    s.test("adding a server via the controller persists through AppState.updateSettings") {
        let appState = freshAppState()
        let vc = SettingsViewController(appState: appState)
        _ = vc.view
        let beforeCount = appState.settings.servers.count
        try vc.serversTabVC.addServer(name: "Test", baseURL: URL(string: "http://192.168.1.1:5001")!)
        try expectEqual(appState.settings.servers.count, beforeCount + 1)
        // First server added → auto-default.
        try expectEqual(appState.settings.defaultServerId, appState.settings.servers.last?.id)
    }

    s.test("removing a server via the controller persists through AppState.updateSettings") {
        let appState = freshAppState()
        let vc = SettingsViewController(appState: appState)
        _ = vc.view
        try vc.serversTabVC.addServer(name: "A", baseURL: URL(string: "http://a")!)
        try vc.serversTabVC.addServer(name: "B", baseURL: URL(string: "http://b")!)
        let bID = appState.settings.servers[1].id
        try vc.serversTabVC.removeServer(id: bID)
        try expectEqual(appState.settings.servers.count, 1)
        try expectEqual(appState.settings.servers[0].name, "A")
    }

    return s
}

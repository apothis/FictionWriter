import Foundation
import AppKit
@testable import LoomCore

/// Phase 4 #7 sub-task 1 bugfix — the Servers-tab action buttons
/// must enable as soon as the table has at least one row, not key
/// off `tableView.selectedRow >= 0`. On macOS 26 with `style = .inset`,
/// the visual row-highlight pill is decoupled from the table's
/// reported selection in some click paths, leaving the user staring
/// at a visually-selected row with disabled buttons.
///
/// The fix: enable buttons whenever `servers.count > 0`; the click
/// handler validates `selectedRow` at action time and falls back to
/// "the first row of the relevant kind" so a stale selection-state
/// quirk doesn't strand the user.
func phase4ExtractorButtonEnableTests() -> TestSuite {
    let s = TestSuite("Phase4ExtractorButtonEnable")

    func freshAppState() -> AppState {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("loom-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let store = AppSettingsStore(fileManager: .default, rootDir: tmp)
        return AppState(settingsStore: store)
    }

    s.test("setExtractor(id:) with a stale -1 selection still designates the first Ollama profile") {
        let appState = freshAppState()
        let vc = SettingsViewController(appState: appState)
        _ = vc.view
        try vc.serversTabVC.addServer(name: "W", baseURL: URL(string: "http://w")!, kind: .kobold)
        try vc.serversTabVC.addServer(name: "E", baseURL: URL(string: "http://e")!, kind: .ollama)
        let extractorId = appState.settings.servers[1].id

        // Simulate the bug: button was clicked while tableView.selectedRow
        // reported -1 (the inset-style selection quirk). The new
        // fallback path picks the first ollama-kind profile.
        vc.serversTabVC.setExtractorViaFallbackForTest()

        try expectEqual(appState.settings.extractorServerId, extractorId)
    }

    s.test("fallback prefers ollama-kind profiles when multiple exist") {
        let appState = freshAppState()
        let vc = SettingsViewController(appState: appState)
        _ = vc.view
        try vc.serversTabVC.addServer(name: "K1", baseURL: URL(string: "http://a")!, kind: .kobold)
        try vc.serversTabVC.addServer(name: "K2", baseURL: URL(string: "http://b")!, kind: .kobold)
        try vc.serversTabVC.addServer(name: "Ollama", baseURL: URL(string: "http://c")!, kind: .ollama)
        let ollamaId = appState.settings.servers[2].id

        vc.serversTabVC.setExtractorViaFallbackForTest()
        try expectEqual(appState.settings.extractorServerId, ollamaId)
    }

    s.test("fallback no-ops when no ollama-kind profile exists") {
        let appState = freshAppState()
        let vc = SettingsViewController(appState: appState)
        _ = vc.view
        try vc.serversTabVC.addServer(name: "K", baseURL: URL(string: "http://a")!, kind: .kobold)
        vc.serversTabVC.setExtractorViaFallbackForTest()
        try expectNil(appState.settings.extractorServerId)
    }

    return s
}

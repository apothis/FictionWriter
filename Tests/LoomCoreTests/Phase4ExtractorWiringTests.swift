import Foundation
import AppKit
@testable import LoomCore

/// Phase 4 #7 sub-task 1 — honest smoke that the Servers tab controller
/// surfaces the new kind + extractor operations. Pure-data mutations
/// are in Phase4ExtractorServerTests; this suite confirms they're
/// reachable through the same `serversTabVC` shape Phase 2's
/// AppState.updateSettings round-trip uses.
func phase4ExtractorWiringTests() -> TestSuite {
    let s = TestSuite("Phase4ExtractorWiring")

    func freshAppState() -> AppState {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("loom-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let store = AppSettingsStore(fileManager: .default, rootDir: tmp)
        return AppState(settingsStore: store)
    }

    s.test("addServer with kind: .ollama persists the kind on the profile") {
        let appState = freshAppState()
        let vc = SettingsViewController(appState: appState)
        _ = vc.view
        try vc.serversTabVC.addServer(
            name: "Extractor",
            baseURL: URL(string: "http://localhost:11434")!,
            kind: .ollama
        )
        let stored = try expectNotNil(appState.settings.servers.first)
        try expectEqual(stored.kind, .ollama)
        try expectEqual(stored.name, "Extractor")
    }

    s.test("addServer defaults to kind: .kobold when not specified (back-compat)") {
        let appState = freshAppState()
        let vc = SettingsViewController(appState: appState)
        _ = vc.view
        try vc.serversTabVC.addServer(name: "Writer", baseURL: URL(string: "http://192.168.1.201:5001")!)
        let stored = try expectNotNil(appState.settings.servers.first)
        try expectEqual(stored.kind, .kobold)
    }

    s.test("setExtractor(id:) persists extractorServerId through AppState.updateSettings") {
        let appState = freshAppState()
        let vc = SettingsViewController(appState: appState)
        _ = vc.view
        try vc.serversTabVC.addServer(name: "W", baseURL: URL(string: "http://w")!, kind: .kobold)
        try vc.serversTabVC.addServer(name: "E", baseURL: URL(string: "http://e")!, kind: .ollama)
        let extractorId = appState.settings.servers[1].id
        try vc.serversTabVC.setExtractor(id: extractorId)
        try expectEqual(appState.settings.extractorServerId, extractorId)
    }

    s.test("setExtractor(id:) rejects an unknown id (throws unknownId)") {
        let appState = freshAppState()
        let vc = SettingsViewController(appState: appState)
        _ = vc.view
        try vc.serversTabVC.addServer(name: "W", baseURL: URL(string: "http://w")!, kind: .kobold)
        do {
            try vc.serversTabVC.setExtractor(id: UUID())
            try expectTrue(false, "expected throw")
        } catch ServersTabViewController.ServersTabError.unknownId {
            // expected
        } catch {
            try expectTrue(false, "wrong error: \(error)")
        }
    }

    s.test("removing the extractor profile via the controller clears extractorServerId") {
        let appState = freshAppState()
        let vc = SettingsViewController(appState: appState)
        _ = vc.view
        try vc.serversTabVC.addServer(name: "W", baseURL: URL(string: "http://w")!, kind: .kobold)
        try vc.serversTabVC.addServer(name: "E", baseURL: URL(string: "http://e")!, kind: .ollama)
        let extractorId = appState.settings.servers[1].id
        try vc.serversTabVC.setExtractor(id: extractorId)
        try expectEqual(appState.settings.extractorServerId, extractorId)
        try vc.serversTabVC.removeServer(id: extractorId)
        try expectNil(appState.settings.extractorServerId)
    }

    return s
}

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

    s.test("addServer persists an explicit model field") {
        let appState = freshAppState()
        let vc = SettingsViewController(appState: appState)
        _ = vc.view
        try vc.serversTabVC.addServer(
            name: "Extractor", baseURL: URL(string: "http://localhost:11434")!,
            kind: .ollama, model: "gemma4_2b:latest"
        )
        let stored = try expectNotNil(appState.settings.servers.first)
        try expectEqual(stored.model, "gemma4_2b:latest")
    }

    s.test("addServer treats a blank model as nil") {
        let appState = freshAppState()
        let vc = SettingsViewController(appState: appState)
        _ = vc.view
        try vc.serversTabVC.addServer(
            name: "W", baseURL: URL(string: "http://w")!, kind: .kobold, model: "   "
        )
        let stored = try expectNotNil(appState.settings.servers.first)
        try expectNil(stored.model)
    }

    s.test("updateServer edits fields in place, preserving id, and sets the model") {
        let appState = freshAppState()
        let vc = SettingsViewController(appState: appState)
        _ = vc.view
        try vc.serversTabVC.addServer(name: "Writer", baseURL: URL(string: "http://192.168.1.201:5001")!, kind: .kobold)
        let id = try expectNotNil(appState.settings.servers.first?.id)
        // Edit: rename + pin a model, same URL/kind.
        try vc.serversTabVC.updateServer(
            id: id, name: "Home Writer",
            baseURL: URL(string: "http://192.168.1.201:5001")!,
            kind: .kobold, model: "gemma-4-31B-it-Thinking"
        )
        try expectEqual(appState.settings.servers.count, 1)
        let updated = try expectNotNil(appState.settings.servers.first)
        try expectEqual(updated.id, id, "id is preserved across edit")
        try expectEqual(updated.name, "Home Writer")
        try expectEqual(updated.model, "gemma-4-31B-it-Thinking")
    }

    s.test("updateServer that keeps the same URL preserves probed capabilities") {
        let appState = freshAppState()
        let vc = SettingsViewController(appState: appState)
        _ = vc.view
        // Seed a profile with cached capabilities directly via settings.
        var settings = appState.settings
        let probed = ServerProfile(
            name: "W", baseURL: URL(string: "http://192.168.1.201:5001")!, kind: .kobold,
            capabilities: ServerCapabilities(modelName: "probed-model", trueMaxContext: 16384, version: "1.x")
        )
        settings.addServer(probed)
        try appState.updateSettings(settings)
        // Edit only the model, same URL/kind → capabilities should survive.
        try vc.serversTabVC.updateServer(
            id: probed.id, name: "W",
            baseURL: URL(string: "http://192.168.1.201:5001")!,
            kind: .kobold, model: "pinned-model"
        )
        let updated = try expectNotNil(appState.settings.servers.first)
        try expectEqual(updated.model, "pinned-model")
        try expectEqual(updated.capabilities?.modelName, "probed-model", "caps survive a same-URL edit")
        try expectEqual(updated.capabilities?.trueMaxContext, 16384)
    }

    s.test("refreshWriterCapabilitiesFromProbe persists the probed model onto the default profile, idempotently") {
        let appState = freshAppState()
        var settings = appState.settings
        settings.addServer(ServerProfile(name: "W", baseURL: URL(string: "http://192.168.1.201:5001")!, kind: .kobold))
        try appState.updateSettings(settings)
        // First probe result populates capabilities.
        let changed = appState.refreshWriterCapabilitiesFromProbe(modelName: "gemma-4-31B-it", trueMaxContext: 16384)
        try expectTrue(changed)
        let stored = try expectNotNil(appState.settings.writerServer())
        try expectEqual(stored.capabilities?.modelName, "gemma-4-31B-it")
        try expectEqual(stored.capabilities?.trueMaxContext, 16384)
        // Same values on the next tick → no-op (no settings churn).
        try expectFalse(appState.refreshWriterCapabilitiesFromProbe(modelName: "gemma-4-31B-it", trueMaxContext: 16384))
        // A model swap on the backend → persisted.
        try expectTrue(appState.refreshWriterCapabilitiesFromProbe(modelName: "Goetia-24B", trueMaxContext: 32768))
        try expectEqual(appState.settings.writerServer()?.capabilities?.modelName, "Goetia-24B")
    }

    s.test("refreshWriterCapabilitiesFromProbe is a no-op with a nil model name (failed/old probe)") {
        let appState = freshAppState()
        var settings = appState.settings
        settings.addServer(ServerProfile(name: "W", baseURL: URL(string: "http://w")!, kind: .kobold))
        try appState.updateSettings(settings)
        try expectFalse(appState.refreshWriterCapabilitiesFromProbe(modelName: nil, trueMaxContext: nil))
        try expectNil(appState.settings.writerServer()?.capabilities?.modelName)
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

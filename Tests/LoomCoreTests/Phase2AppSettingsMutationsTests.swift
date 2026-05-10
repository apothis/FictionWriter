import Foundation
@testable import LoomCore

/// Phase 2 (Settings UI): pure-data mutations on AppSettings that
/// drive the Servers tab. Adding the first server should auto-promote
/// it to default; removing the default should reassign to the first
/// remaining server (or nil if the list empties); setDefault should
/// validate that the target ID actually exists.
func phase2AppSettingsMutationsTests() -> TestSuite {
    let s = TestSuite("Phase2AppSettingsMutations")

    s.test("addServer appends to the list") {
        var settings = AppSettings()
        let profile = ServerProfile(name: "Home", baseURL: URL(string: "http://192.168.1.201:5001")!)
        settings.addServer(profile)
        try expectEqual(settings.servers.count, 1)
        try expectEqual(settings.servers[0].name, "Home")
    }

    s.test("addServer auto-promotes the first server to default") {
        var settings = AppSettings()
        let profile = ServerProfile(name: "Home", baseURL: URL(string: "http://192.168.1.201:5001")!)
        settings.addServer(profile)
        try expectEqual(settings.defaultServerId, profile.id)
    }

    s.test("addServer does NOT change the default when one already exists") {
        let first = ServerProfile(name: "First", baseURL: URL(string: "http://a")!)
        var settings = AppSettings(servers: [first], defaultServerId: first.id)
        let second = ServerProfile(name: "Second", baseURL: URL(string: "http://b")!)
        settings.addServer(second)
        try expectEqual(settings.defaultServerId, first.id)
    }

    s.test("removeServer drops the entry by id") {
        let a = ServerProfile(name: "A", baseURL: URL(string: "http://a")!)
        let b = ServerProfile(name: "B", baseURL: URL(string: "http://b")!)
        var settings = AppSettings(servers: [a, b], defaultServerId: a.id)
        settings.removeServer(id: b.id)
        try expectEqual(settings.servers.count, 1)
        try expectEqual(settings.servers[0].id, a.id)
    }

    s.test("removeServer reassigns the default when the removed server WAS the default") {
        let a = ServerProfile(name: "A", baseURL: URL(string: "http://a")!)
        let b = ServerProfile(name: "B", baseURL: URL(string: "http://b")!)
        var settings = AppSettings(servers: [a, b], defaultServerId: a.id)
        settings.removeServer(id: a.id)
        try expectEqual(settings.defaultServerId, b.id, "default should fall to the first remaining server")
    }

    s.test("removeServer clears the default when the last server is removed") {
        let a = ServerProfile(name: "A", baseURL: URL(string: "http://a")!)
        var settings = AppSettings(servers: [a], defaultServerId: a.id)
        settings.removeServer(id: a.id)
        try expectTrue(settings.servers.isEmpty)
        try expectNil(settings.defaultServerId)
    }

    s.test("removeServer on an unknown id is a no-op") {
        let a = ServerProfile(name: "A", baseURL: URL(string: "http://a")!)
        var settings = AppSettings(servers: [a], defaultServerId: a.id)
        settings.removeServer(id: UUID())
        try expectEqual(settings.servers.count, 1)
        try expectEqual(settings.defaultServerId, a.id)
    }

    s.test("setDefault accepts an id that is in the servers list") {
        let a = ServerProfile(name: "A", baseURL: URL(string: "http://a")!)
        let b = ServerProfile(name: "B", baseURL: URL(string: "http://b")!)
        var settings = AppSettings(servers: [a, b], defaultServerId: a.id)
        let ok = settings.setDefault(id: b.id)
        try expectTrue(ok)
        try expectEqual(settings.defaultServerId, b.id)
    }

    s.test("setDefault rejects an id that is NOT in the servers list (returns false, leaves state unchanged)") {
        let a = ServerProfile(name: "A", baseURL: URL(string: "http://a")!)
        var settings = AppSettings(servers: [a], defaultServerId: a.id)
        let ok = settings.setDefault(id: UUID())
        try expectFalse(ok)
        try expectEqual(settings.defaultServerId, a.id)
    }

    s.test("updateServer rewrites name and baseURL by id") {
        let original = ServerProfile(name: "Old", baseURL: URL(string: "http://old")!)
        var settings = AppSettings(servers: [original], defaultServerId: original.id)
        var edited = original
        edited.name = "New"
        edited.baseURL = URL(string: "http://new")!
        let ok = settings.updateServer(edited)
        try expectTrue(ok)
        try expectEqual(settings.servers[0].name, "New")
        try expectEqual(settings.servers[0].baseURL.absoluteString, "http://new")
        try expectEqual(settings.servers[0].id, original.id, "id is stable across edits")
    }

    s.test("updateServer rejects an unknown id (returns false)") {
        let a = ServerProfile(name: "A", baseURL: URL(string: "http://a")!)
        var settings = AppSettings(servers: [a])
        let ghost = ServerProfile(name: "Ghost", baseURL: URL(string: "http://ghost")!)
        let ok = settings.updateServer(ghost)
        try expectFalse(ok)
        try expectEqual(settings.servers.count, 1)
        try expectEqual(settings.servers[0].name, "A")
    }

    return s
}

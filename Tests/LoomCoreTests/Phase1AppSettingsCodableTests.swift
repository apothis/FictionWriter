import Foundation
@testable import LoomCore

/// Sub-step 1.c — AppSettings round-trip + lazy-versioning. AppSettings
/// is the global app-level settings file (~/Library/Application Support/
/// Loom/settings.json) holding server profiles + defaultServerId. Per-
/// project settings live on Project.settings; AppSettings is the slot
/// for cross-project preferences (server list is the only Phase 1 entry).
func phase1AppSettingsCodableTests() -> TestSuite {
    let s = TestSuite("Phase1AppSettingsCodable")

    s.test("default AppSettings round-trips") {
        let a = AppSettings.defaults
        let data = try JSONEncoder.loomPretty.encode(a)
        let decoded = try JSONDecoder.loom.decode(AppSettings.self, from: data)
        try expectEqual(decoded, a)
    }

    s.test("populated AppSettings round-trips") {
        let p1 = ServerProfile(name: "Local", baseURL: URL(string: "http://localhost:5001")!)
        let p2 = ServerProfile(name: "Workstation", baseURL: URL(string: "http://10.0.0.5:5001")!)
        var a = AppSettings.defaults
        a.servers = [p1, p2]
        a.defaultServerId = p1.id

        let data = try JSONEncoder.loomPretty.encode(a)
        let decoded = try JSONDecoder.loom.decode(AppSettings.self, from: data)
        try expectEqual(decoded, a)
    }

    s.test("AppSettings JSON missing 'defaultServerId' decodes with nil") {
        let json = """
        {
          "schemaVersion": 1,
          "servers": []
        }
        """
        let decoded = try JSONDecoder.loom.decode(AppSettings.self, from: Data(json.utf8))
        try expectNil(decoded.defaultServerId)
        try expectEqual(decoded.servers.count, 0)
    }

    return s
}

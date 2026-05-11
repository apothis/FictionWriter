import Foundation
@testable import LoomCore

/// Phase 4 #7 sub-task 1 — `AppSettings.extractorServerId` is the
/// sibling of `defaultServerId` for the role-routed extractor
/// (Ollama running gemma4_2b in the production design, per
/// LOOM_LEDGER_SPIKE.md §12). The writer (`defaultServerId`) and the
/// extractor (`extractorServerId`) are independent ids; either can be
/// nil (e.g., user hasn't added an extractor yet). Selecting them
/// goes through helpers that resolve the right `ServerProfile` from
/// the unified `servers` list.
func phase4ExtractorServerTests() -> TestSuite {
    let s = TestSuite("Phase4ExtractorServer")

    s.test("default AppSettings has extractorServerId == nil") {
        let a = AppSettings.defaults
        try expectNil(a.extractorServerId)
    }

    s.test("AppSettings with extractorServerId round-trips through Codable") {
        let writer = ServerProfile(name: "Writer", baseURL: URL(string: "http://192.168.1.201:5001")!, kind: .kobold)
        let extractor = ServerProfile(name: "Extractor", baseURL: URL(string: "http://localhost:11434")!, kind: .ollama)
        var a = AppSettings.defaults
        a.servers = [writer, extractor]
        a.defaultServerId = writer.id
        a.extractorServerId = extractor.id

        let data = try JSONEncoder.loomPretty.encode(a)
        let decoded = try JSONDecoder.loom.decode(AppSettings.self, from: data)
        try expectEqual(decoded, a)
        try expectEqual(decoded.extractorServerId, extractor.id)
    }

    s.test("Phase 1/2/3 AppSettings JSON (no extractorServerId) decodes with nil") {
        // Verbatim shape of a pre-Phase-4 settings.json bundle: schemaVersion
        // + servers + defaultServerId only. Forward-load contract.
        let json = """
        {
          "schemaVersion": 1,
          "servers": [
            {
              "id": "11111111-1111-1111-1111-111111111111",
              "name": "Writer",
              "baseURL": "http://192.168.1.201:5001/"
            }
          ],
          "defaultServerId": "11111111-1111-1111-1111-111111111111"
        }
        """
        let decoded = try JSONDecoder.loom.decode(AppSettings.self, from: Data(json.utf8))
        try expectNil(decoded.extractorServerId)
        try expectEqual(decoded.defaultServerId?.uuidString, "11111111-1111-1111-1111-111111111111")
    }

    s.test("writerServer() resolves the profile matching defaultServerId") {
        let writer = ServerProfile(name: "W", baseURL: URL(string: "http://w")!, kind: .kobold)
        let extractor = ServerProfile(name: "E", baseURL: URL(string: "http://e")!, kind: .ollama)
        var a = AppSettings.defaults
        a.servers = [writer, extractor]
        a.defaultServerId = writer.id
        let resolved = try expectNotNil(a.writerServer())
        try expectEqual(resolved.id, writer.id)
    }

    s.test("writerServer() returns nil when defaultServerId is unset") {
        var a = AppSettings.defaults
        a.servers = [ServerProfile(name: "W", baseURL: URL(string: "http://w")!)]
        a.defaultServerId = nil
        try expectNil(a.writerServer())
    }

    s.test("extractorServer() resolves the profile matching extractorServerId") {
        let writer = ServerProfile(name: "W", baseURL: URL(string: "http://w")!, kind: .kobold)
        let extractor = ServerProfile(name: "E", baseURL: URL(string: "http://e")!, kind: .ollama)
        var a = AppSettings.defaults
        a.servers = [writer, extractor]
        a.extractorServerId = extractor.id
        let resolved = try expectNotNil(a.extractorServer())
        try expectEqual(resolved.id, extractor.id)
    }

    s.test("extractorServer() returns nil when extractorServerId is unset") {
        var a = AppSettings.defaults
        a.servers = [ServerProfile(name: "W", baseURL: URL(string: "http://w")!)]
        a.extractorServerId = nil
        try expectNil(a.extractorServer())
    }

    s.test("setExtractor(id:) accepts an id that is in the servers list") {
        let extractor = ServerProfile(name: "E", baseURL: URL(string: "http://e")!, kind: .ollama)
        var a = AppSettings.defaults
        a.servers = [extractor]
        let ok = a.setExtractor(id: extractor.id)
        try expectTrue(ok)
        try expectEqual(a.extractorServerId, extractor.id)
    }

    s.test("setExtractor(id:) rejects an unknown id (returns false, state unchanged)") {
        let extractor = ServerProfile(name: "E", baseURL: URL(string: "http://e")!, kind: .ollama)
        var a = AppSettings.defaults
        a.servers = [extractor]
        a.extractorServerId = extractor.id
        let ok = a.setExtractor(id: UUID())
        try expectFalse(ok)
        try expectEqual(a.extractorServerId, extractor.id)
    }

    s.test("setExtractor(id: nil) clears the extractor (unsets the role)") {
        let extractor = ServerProfile(name: "E", baseURL: URL(string: "http://e")!, kind: .ollama)
        var a = AppSettings.defaults
        a.servers = [extractor]
        a.extractorServerId = extractor.id
        let ok = a.setExtractor(id: nil)
        try expectTrue(ok)
        try expectNil(a.extractorServerId)
    }

    s.test("removeServer clears extractorServerId when the removed server WAS the extractor") {
        let writer = ServerProfile(name: "W", baseURL: URL(string: "http://w")!, kind: .kobold)
        let extractor = ServerProfile(name: "E", baseURL: URL(string: "http://e")!, kind: .ollama)
        var a = AppSettings(servers: [writer, extractor], defaultServerId: writer.id)
        a.extractorServerId = extractor.id
        a.removeServer(id: extractor.id)
        try expectNil(a.extractorServerId)  // removing the extractor profile drops its role assignment
    }

    s.test("removeServer leaves extractorServerId intact when the removed server was a different profile") {
        let writer = ServerProfile(name: "W", baseURL: URL(string: "http://w")!, kind: .kobold)
        let extractor = ServerProfile(name: "E", baseURL: URL(string: "http://e")!, kind: .ollama)
        let other = ServerProfile(name: "O", baseURL: URL(string: "http://o")!, kind: .kobold)
        var a = AppSettings(servers: [writer, extractor, other], defaultServerId: writer.id)
        a.extractorServerId = extractor.id
        a.removeServer(id: other.id)
        try expectEqual(a.extractorServerId, extractor.id)
    }

    return s
}

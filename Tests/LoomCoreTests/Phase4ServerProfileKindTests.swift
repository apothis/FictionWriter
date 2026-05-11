import Foundation
@testable import LoomCore

/// Phase 4 #7 sub-task 1 — `ServerProfile` gains a `kind` discriminator
/// so a single `AppSettings.servers` list can hold both the writer
/// (KoboldCpp, the existing single-role default) and the extractor
/// (Ollama, new for the ledger pipeline). Lazy-versioned per §9.4:
/// every pre-Phase-4 settings.json on disk has profiles with no `kind`
/// field; those must decode to `.kobold` so the forward-load contract
/// holds.
func phase4ServerProfileKindTests() -> TestSuite {
    let s = TestSuite("Phase4ServerProfileKind")

    s.test("ServerKind raw values are stable on-disk strings") {
        try expectEqual(ServerKind.kobold.rawValue, "kobold")
        try expectEqual(ServerKind.ollama.rawValue, "ollama")
    }

    s.test("ServerProfile default kind is .kobold (back-compat default)") {
        let p = ServerProfile(name: "Local", baseURL: URL(string: "http://localhost:5001")!)
        try expectEqual(p.kind, .kobold)
    }

    s.test("ServerProfile with explicit .ollama kind round-trips through Codable") {
        let p = ServerProfile(
            name: "Extractor",
            baseURL: URL(string: "http://localhost:11434")!,
            kind: .ollama
        )
        let data = try JSONEncoder.loomPretty.encode(p)
        let decoded = try JSONDecoder.loom.decode(ServerProfile.self, from: data)
        try expectEqual(decoded.kind, .ollama)
        try expectEqual(decoded, p)
    }

    s.test("Phase 1/2/3 ServerProfile JSON (no `kind` field) decodes with .kobold (forward-load contract)") {
        // Verbatim shape of a pre-Phase-4 profile entry: id, name, baseURL,
        // optional capabilities + lastProbed. Phase 4 settings bundles on
        // disk look like this; they must load forward without rewriting.
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "name": "Old Writer",
          "baseURL": "http://192.168.1.201:5001/"
        }
        """
        let decoded = try JSONDecoder.loom.decode(ServerProfile.self, from: Data(json.utf8))
        try expectEqual(decoded.kind, .kobold, "missing kind decodes as kobold for back-compat")
        try expectEqual(decoded.name, "Old Writer")
    }

    s.test("AppSettings JSON with multiple profiles where some lack `kind` decodes mixed-kind correctly") {
        // Real shape: a Phase 4 settings.json after the user has added an
        // Ollama extractor next to their legacy kobold writer. The kobold
        // entry was written pre-Phase-4 (no kind field); the ollama entry
        // was written post-Phase-4 (explicit kind).
        let json = """
        {
          "schemaVersion": 1,
          "servers": [
            {
              "id": "11111111-1111-1111-1111-111111111111",
              "name": "Writer",
              "baseURL": "http://192.168.1.201:5001/"
            },
            {
              "id": "22222222-2222-2222-2222-222222222222",
              "name": "Extractor",
              "baseURL": "http://localhost:11434/",
              "kind": "ollama"
            }
          ],
          "defaultServerId": "11111111-1111-1111-1111-111111111111"
        }
        """
        let decoded = try JSONDecoder.loom.decode(AppSettings.self, from: Data(json.utf8))
        try expectEqual(decoded.servers.count, 2)
        try expectEqual(decoded.servers[0].kind, .kobold, "legacy entry → kobold")
        try expectEqual(decoded.servers[1].kind, .ollama, "explicit entry → ollama")
    }

    return s
}

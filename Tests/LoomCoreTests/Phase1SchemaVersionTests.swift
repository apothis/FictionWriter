import Foundation
@testable import LoomCore

/// Sub-step 1.b — schema version + forward-compat smoke. Pure data tests
/// against synthetic project.json content that simulates older / newer
/// formats. The lazy-versioning posture: additive fields use
/// `decodeIfPresent`, so a project.json missing a recently-added field
/// decodes cleanly with the field's default value.
func phase1SchemaVersionTests() -> TestSuite {
    let s = TestSuite("Phase1SchemaVersion")

    s.test("project.json missing optional 'author' decodes with nil") {
        // Hand-rolled JSON missing the `author` field entirely. The struct
        // declares author as `String?` so decodeIfPresent should let this
        // through.
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "title": "Old Project",
          "createdAt": "2026-01-01T00:00:00Z",
          "schemaVersion": 1,
          "kind": "originalFiction",
          "settings": \(defaultSettingsJSON()),
          "manuscript": {
            "partIds": [],
            "orphanedSceneIds": []
          },
          "bible": {
            "characters": []
          }
        }
        """

        let decoded = try JSONDecoder.loom.decode(Project.self, from: Data(json.utf8))
        try expectNil(decoded.author)
        try expectEqual(decoded.title, "Old Project")
        try expectEqual(decoded.schemaVersion, 1)
    }

    s.test("project.json with an unknown future field decodes (extra ignored)") {
        // Unknown keys are silently ignored by JSONDecoder by default.
        // This pins the "future-version-tolerant load" behaviour.
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "title": "Future Project",
          "createdAt": "2026-01-01T00:00:00Z",
          "schemaVersion": 99,
          "kind": "originalFiction",
          "futureFieldFromPhase42": "ignored",
          "settings": \(defaultSettingsJSON()),
          "manuscript": {
            "partIds": [],
            "orphanedSceneIds": []
          },
          "bible": {
            "characters": []
          }
        }
        """

        let decoded = try JSONDecoder.loom.decode(Project.self, from: Data(json.utf8))
        try expectEqual(decoded.title, "Future Project")
        try expectEqual(decoded.schemaVersion, 99)
    }

    return s
}

/// Embeddable JSON for ProjectSettings — uses the in-memory defaults so
/// the test isn't sensitive to GenerationDefaults field changes that
/// happen via the lazy-versioning path.
private func defaultSettingsJSON() -> String {
    let settings = ProjectSettings.defaults
    let data = try! JSONEncoder().encode(settings)
    return String(data: data, encoding: .utf8)!
}

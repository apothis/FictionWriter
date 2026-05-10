import Foundation
@testable import LoomCore

/// Sub-step 1.g — selected inspector tab persists per project across
/// reopens. Stored on Project as `selectedInspectorTab: InspectorTab?`
/// (additive; nil when never set, defaults to .bible in the UI).
///
/// `notes` is the second additive field this sub-step adds; covered
/// here too since it's the simplest possible Codable round-trip.
func phase1InspectorTabPersistenceTests() -> TestSuite {
    let s = TestSuite("Phase1InspectorTabPersistence")

    s.test("Project.selectedInspectorTab defaults to nil") {
        let p = Project.empty(title: "X")
        try expectNil(p.selectedInspectorTab)
    }

    s.test("selectedInspectorTab round-trips through Codable") {
        var p = Project.empty(title: "X")
        p.selectedInspectorTab = .history
        let data = try JSONEncoder.loomPretty.encode(p)
        let decoded = try JSONDecoder.loom.decode(Project.self, from: data)
        try expectEqual(decoded.selectedInspectorTab, .history)
    }

    s.test("missing selectedInspectorTab in legacy JSON decodes as nil") {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "title": "Old",
          "createdAt": "2026-01-01T00:00:00Z",
          "schemaVersion": 1,
          "kind": "originalFiction",
          "settings": \(legacyDefaultSettingsJSON()),
          "manuscript": {"partIds":[],"orphanedSceneIds":[],"trashedSceneIds":[]},
          "bible": {"characters":[]}
        }
        """
        let decoded = try JSONDecoder.loom.decode(Project.self, from: Data(json.utf8))
        try expectNil(decoded.selectedInspectorTab)
        try expectEqual(decoded.notes, "")
    }

    s.test("session.setSelectedInspectorTab updates the project") {
        let session = ProjectSession(project: Project.empty(title: "X"))
        session.setSelectedInspectorTab(.notes)
        try expectEqual(session.project.selectedInspectorTab, .notes)
    }

    s.test("session.updateNotes updates Project.notes") {
        let session = ProjectSession(project: Project.empty(title: "X"))
        session.updateNotes("first thought\n\nsecond thought")
        try expectEqual(session.project.notes, "first thought\n\nsecond thought")
    }

    return s
}

/// Used to build the JSON fixture for the missing-fields test. Pulled
/// out so a future GenerationDefaults addition doesn't break this test.
private func legacyDefaultSettingsJSON() -> String {
    let s = ProjectSettings.defaults
    let data = try! JSONEncoder().encode(s)
    return String(data: data, encoding: .utf8)!
}

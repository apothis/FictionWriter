import Foundation
@testable import LoomCore

/// Planned Project mode — Phase 4 item 4. The style-library editor:
/// the `StyleLibrary.upserting`/`removing` mutation helpers and the
/// `upsertStyle`/`deleteStyle` bridge intents that persist to the
/// app-level `styles.json`.
func plannedProjectStyleEditorTests() -> TestSuite {
    let s = TestSuite("PlannedProjectStyleEditor")

    s.test("upserting appends a style with a new id") {
        let lib = [Style(name: "Noir", type: .genre)]
        let added = Style(name: "Cozy", type: .genre)
        let out = StyleLibrary.upserting(added, into: lib)
        try expectEqual(out.count, 2)
        try expectEqual(out.last?.name, "Cozy")
    }

    s.test("upserting replaces a style with an existing id, preserving order") {
        let a = Style(name: "Noir", type: .genre)
        let b = Style(name: "Cozy", type: .genre)
        let lib = [a, b]
        var editedA = a
        editedA.descriptor = "Now with rain."
        let out = StyleLibrary.upserting(editedA, into: lib)
        try expectEqual(out.count, 2)
        try expectEqual(out[0].descriptor, "Now with rain.")
        try expectEqual(out[1].name, "Cozy")
    }

    s.test("removing drops the matching id and is a no-op when absent") {
        let a = Style(name: "Noir", type: .genre)
        let b = Style(name: "Cozy", type: .genre)
        try expectEqual(StyleLibrary.removing(id: a.id, from: [a, b]).map(\.name), ["Cozy"])
        try expectEqual(StyleLibrary.removing(id: UUID(), from: [a, b]).count, 2)
    }

    s.test("upsertStyle intent round-trips through Codable") {
        let intent = BibleWorkspaceIntent.upsertStyle(
            style: Style(name: "Hardboiled", type: .register, descriptor: "Terse.")
        )
        let data = try JSONEncoder().encode(intent)
        let obj = try (JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        try expectEqual(obj["kind"] as? String, "upsertStyle")
        try expectNotNil(obj["style"] as? [String: Any])
        let back = try JSONDecoder().decode(BibleWorkspaceIntent.self, from: data)
        try expectEqual(back, intent)
    }

    s.test("deleteStyle intent round-trips through Codable") {
        let id = UUID()
        let intent = BibleWorkspaceIntent.deleteStyle(id: id)
        let data = try JSONEncoder().encode(intent)
        let obj = try (JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        try expectEqual(obj["kind"] as? String, "deleteStyle")
        try expectEqual(obj["id"] as? String, id.uuidString)
        let back = try JSONDecoder().decode(BibleWorkspaceIntent.self, from: data)
        try expectEqual(back, intent)
    }

    s.test("closeWizardWindow intent round-trips through Codable") {
        let intent = BibleWorkspaceIntent.closeWizardWindow
        let data = try JSONEncoder().encode(intent)
        let obj = try (JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        try expectEqual(obj["kind"] as? String, "closeWizardWindow")
        let back = try JSONDecoder().decode(BibleWorkspaceIntent.self, from: data)
        try expectEqual(back, intent)
    }

    return s
}

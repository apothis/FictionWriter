import Foundation
@testable import LoomCore

/// Phase 9 in-flight signal — `BibleWorkspaceSnapshot.discoveringSceneIds`.
/// Mirrors `extractingTemplateIds` / `ingestingReferenceIds` patterns:
/// snapshot carries the in-flight set so the React UI can flip a
/// "Discovering…" indicator without polling. Encoded as `[String]`
/// (uppercase UUID strings) for direct JS `Array.includes` use.
func phase9DiscoveringSceneIdsTests() -> TestSuite {
    let s = TestSuite("Phase9DiscoveringSceneIds")

    s.test("snapshot defaults discoveringSceneIds to []") {
        let snap = BibleWorkspaceSnapshot(
            projectTitle: "T",
            characters: [],
            lorebook: [],
            scenes: [],
            suggestions: []
        )
        try expectEqual(snap.discoveringSceneIds, [])
    }

    s.test("snapshot encode/decode round-trips discoveringSceneIds") {
        let id1 = UUID()
        let id2 = UUID()
        let snap = BibleWorkspaceSnapshot(
            projectTitle: "T",
            characters: [],
            lorebook: [],
            scenes: [],
            suggestions: [],
            discoveringSceneIds: [id1, id2]
        )
        let data = try JSONEncoder().encode(snap)
        let back = try JSONDecoder().decode(BibleWorkspaceSnapshot.self, from: data)
        try expectEqual(Set(back.discoveringSceneIds), Set([id1, id2]))
    }

    s.test("legacy snapshot without discoveringSceneIds → []") {
        let json = """
        {
          "projectTitle": "Legacy",
          "characters": [],
          "lorebook": [],
          "scenes": [],
          "suggestions": []
        }
        """
        let snap = try JSONDecoder().decode(BibleWorkspaceSnapshot.self, from: json.data(using: .utf8)!)
        try expectEqual(snap.discoveringSceneIds, [])
    }

    s.test("encoded wire format uses uppercase UUID strings") {
        let id = UUID()
        let snap = BibleWorkspaceSnapshot(
            projectTitle: "T",
            characters: [],
            lorebook: [],
            scenes: [],
            suggestions: [],
            discoveringSceneIds: [id]
        )
        let data = try JSONEncoder().encode(snap)
        let obj = try (JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let arr = try expectNotNil(obj["discoveringSceneIds"] as? [String])
        try expectEqual(arr, [id.uuidString])
    }

    return s
}

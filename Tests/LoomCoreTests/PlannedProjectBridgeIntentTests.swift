import Foundation
@testable import LoomCore

/// Planned Project mode — Phase 4 item 2. The guided-creation wizard
/// runs two operations that the existing fire-and-forget intent
/// system can't express: `generateOutline` (an async request whose
/// `GeneratedOutline` result must come back to JS) and
/// `createPlannedProject` (carries the edited outline forward to
/// disk). Both ride a `requestId` so the JS `postRequest` promise
/// map can pair the reply. This suite pins the wire shape of the
/// two intents and the Swift→JS `resolveReply` envelope.
func plannedProjectBridgeIntentTests() -> TestSuite {
    let s = TestSuite("PlannedProjectBridgeIntent")

    func sampleOutline() -> OutlineGeneration.GeneratedOutline {
        let id = UUID()
        return OutlineGeneration.GeneratedOutline(
            manuscript: Manuscript(orphanedSceneIds: [id]),
            scenes: [Scene(
                id: id, title: "Opening", status: .todo,
                summary: "She arrives.", targetWordCount: 1_500
            )]
        )
    }

    s.test("GeneratedOutline round-trips through Codable") {
        let outline = sampleOutline()
        let data = try JSONEncoder().encode(outline)
        let back = try JSONDecoder().decode(
            OutlineGeneration.GeneratedOutline.self, from: data
        )
        try expectEqual(back, outline)
    }

    s.test("generateOutline encodes with kind + requestId + config") {
        let config = PlannedProjectConfig(
            premise: "A heist goes wrong.",
            characterSketch: "Mara, a tired locksmith.",
            lengthScenario: .novella
        )
        let intent = BibleWorkspaceIntent.generateOutline(
            requestId: "req-1", config: config
        )
        let data = try JSONEncoder().encode(intent)
        let obj = try (JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        try expectEqual(obj["kind"] as? String, "generateOutline")
        try expectEqual(obj["requestId"] as? String, "req-1")
        let cfg = try expectNotNil(obj["config"] as? [String: Any])
        try expectEqual(cfg["premise"] as? String, "A heist goes wrong.")
    }

    s.test("generateOutline round-trips through Codable") {
        let intent = BibleWorkspaceIntent.generateOutline(
            requestId: "req-2",
            config: PlannedProjectConfig(premise: "P", characterSketch: "C")
        )
        let data = try JSONEncoder().encode(intent)
        let back = try JSONDecoder().decode(BibleWorkspaceIntent.self, from: data)
        try expectEqual(back, intent)
    }

    s.test("createPlannedProject encodes kind + requestId + title + config + outline") {
        let intent = BibleWorkspaceIntent.createPlannedProject(
            requestId: "req-3",
            title: "Nightlock",
            config: PlannedProjectConfig(premise: "P", characterSketch: "C"),
            outline: sampleOutline()
        )
        let data = try JSONEncoder().encode(intent)
        let obj = try (JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        try expectEqual(obj["kind"] as? String, "createPlannedProject")
        try expectEqual(obj["requestId"] as? String, "req-3")
        try expectEqual(obj["title"] as? String, "Nightlock")
        try expectNotNil(obj["config"] as? [String: Any])
        try expectNotNil(obj["outline"] as? [String: Any])
    }

    s.test("createPlannedProject round-trips through Codable") {
        let intent = BibleWorkspaceIntent.createPlannedProject(
            requestId: "req-4",
            title: "Nightlock",
            config: PlannedProjectConfig(premise: "P", characterSketch: "C"),
            outline: sampleOutline()
        )
        let data = try JSONEncoder().encode(intent)
        let back = try JSONDecoder().decode(BibleWorkspaceIntent.self, from: data)
        try expectEqual(back, intent)
    }

    s.test("encodeReply wraps a value in window.loomWizard.resolveReply with ok:true") {
        let js = try BibleWorkspaceBridge.encodeReply(
            requestId: "req-5", value: sampleOutline()
        )
        try expectTrue(js.hasPrefix("window.loomWizard.resolveReply("),
            "must call resolveReply; got: \(js)")
        try expectTrue(js.hasSuffix(");"), "must end with );; got: \(js)")
        let middle = String(js.dropFirst("window.loomWizard.resolveReply(".count).dropLast(2))
        let obj = try (JSONSerialization.jsonObject(
            with: middle.data(using: .utf8)!) as? [String: Any]) ?? [:]
        try expectEqual(obj["requestId"] as? String, "req-5")
        try expectEqual(obj["ok"] as? Bool, true)
        try expectNotNil(obj["value"] as? [String: Any])
    }

    s.test("encodeReplyError wraps a message with ok:false") {
        let js = BibleWorkspaceBridge.encodeReplyError(
            requestId: "req-6", message: "writer server unreachable"
        )
        try expectTrue(js.hasPrefix("window.loomWizard.resolveReply("),
            "must call resolveReply; got: \(js)")
        let middle = String(js.dropFirst("window.loomWizard.resolveReply(".count).dropLast(2))
        let obj = try (JSONSerialization.jsonObject(
            with: middle.data(using: .utf8)!) as? [String: Any]) ?? [:]
        try expectEqual(obj["requestId"] as? String, "req-6")
        try expectEqual(obj["ok"] as? Bool, false)
        try expectEqual(obj["error"] as? String, "writer server unreachable")
    }

    return s
}

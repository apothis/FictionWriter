import Foundation
@testable import LoomCore

/// AO3-style work framing — content elements + authorial stance.
/// `playedStraight` elements feed an anti-softening system clause.
func phase4WorkFramingTests() -> TestSuite {
    let s = TestSuite("Phase4WorkFraming")

    s.test("FramedElement round-trips; stance defaults to playedStraight") {
        let e = FramedElement(name: "non-consent")
        try expectEqual(e.stance, .playedStraight)
        let data = try JSONEncoder.loomPretty.encode(
            FramedElement(name: "violence", stance: .critiqued)
        )
        try expectEqual(
            try JSONDecoder.loom.decode(FramedElement.self, from: data).stance, .critiqued
        )
    }

    s.test("a FramedElement without a stance decodes as playedStraight") {
        let e = try JSONDecoder.loom.decode(
            FramedElement.self, from: Data("{\"name\":\"incest\"}".utf8)
        )
        try expectEqual(e.stance, .playedStraight)
    }

    s.test("ContentStance covers the three cases") {
        try expectEqual(
            Set(ContentStance.allCases), [.playedStraight, .subverted, .critiqued]
        )
    }

    s.test("workFraming defaults empty and round-trips through Project") {
        try expectEqual(ProjectSettings.defaults.workFraming, [])
        var p = Project(title: "X")
        p.settings.workFraming = [FramedElement(name: "torture", stance: .playedStraight)]
        let data = try JSONEncoder.loomPretty.encode(p)
        let back = try JSONDecoder.loom.decode(Project.self, from: data)
        try expectEqual(back.settings.workFraming.first?.name, "torture")
    }

    s.test("WorkFramingPrompt: empty framing yields no addendum") {
        try expectTrue(WorkFramingPrompt.systemAddendum([]).isEmpty)
    }

    s.test("WorkFramingPrompt: only played-straight elements feed the clause") {
        let addendum = WorkFramingPrompt.systemAddendum([
            FramedElement(name: "non-consent", stance: .playedStraight),
            FramedElement(name: "graphic violence", stance: .critiqued),
            FramedElement(name: "a tragic twist", stance: .subverted),
        ])
        try expectTrue(addendum.contains("non-consent"))
        try expectFalse(addendum.contains("graphic violence"))
        try expectFalse(addendum.contains("a tragic twist"))
        try expectTrue(addendum.lowercased().contains("without"))
    }

    s.test("a played-straight element reaches the assembled system prompt") {
        var project = Project(title: "T")
        project.settings.workFraming = [
            FramedElement(name: "an unredeemed villain", stance: .playedStraight)
        ]
        let scene = Scene.empty(id: UUID(), title: "S")
        project.manuscript.orphanedSceneIds = [scene.id]
        let result = PromptBuilder.build(PromptContext(
            mode: .continueProse, project: project, scenes: [scene.id: scene],
            currentSceneId: scene.id, cursorOffset: 0, selectionRange: nil,
            modelName: nil, contextBudgetTokens: 8192, replyBudgetTokens: 1024
        ))
        try expectTrue(result.systemBlock.contains("an unredeemed villain"))
    }

    s.test("setWorkFraming intent round-trips through encode/decode") {
        let intent = BibleWorkspaceIntent.setWorkFraming(elements: [
            FramedElement(name: "incest", stance: .playedStraight),
        ])
        let data = try JSONEncoder().encode(intent)
        try expectEqual(try BibleWorkspaceBridge.decodeIntent(data), intent)
    }

    return s
}

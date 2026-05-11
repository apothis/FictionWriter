import Foundation
@testable import LoomCore

/// Phase 2 #11 — mention sparkline data layer. Pure projection from
/// a project (scenes + bible) into a per-entity mention count, with
/// per-scene breakdown for the sparkline's marker dots.
///
/// Render-time (sparkline view) is a Phase 4+ polish iteration if
/// the layout is fragile; this contract is the data foundation
/// either way.
func phase2MentionIndexTests() -> TestSuite {
    let s = TestSuite("Phase2MentionIndex")

    s.test("mention count of zero when prose has no entity links") {
        var project = Project.empty(title: "T")
        let mia = Character(name: "Mia")
        project.bible.characters = [mia]
        let scene = Scene.empty(id: UUID(), title: "S1")
        let scenes: [UUID: Scene] = [scene.id: { var c = scene; c.prose = "Plain prose, no links."; return c }()]
        project.manuscript.orphanedSceneIds = [scene.id]

        let index = MentionIndex.build(for: project, scenes: scenes)
        try expectEqual(index.totalCount(for: mia.id), 0)
    }

    s.test("each markdown reference adds one to the count for that entity") {
        var project = Project.empty(title: "T")
        let mia = Character(name: "Mia")
        project.bible.characters = [mia]
        let sceneId = UUID()
        let prose = "Hello \(EntityReference(category: .characters, id: mia.id, displayName: "Mia").markdown), again \(EntityReference(category: .characters, id: mia.id, displayName: "Mia").markdown)."
        var scene = Scene.empty(id: sceneId, title: "S1")
        scene.prose = prose
        project.manuscript.orphanedSceneIds = [sceneId]

        let index = MentionIndex.build(for: project, scenes: [sceneId: scene])
        try expectEqual(index.totalCount(for: mia.id), 2)
    }

    s.test("per-scene breakdown lists the count under that scene id") {
        var project = Project.empty(title: "T")
        let mia = Character(name: "Mia")
        project.bible.characters = [mia]
        let s1 = UUID(), s2 = UUID(), s3 = UUID()
        let mention = EntityReference(category: .characters, id: mia.id, displayName: "Mia").markdown
        var sceneA = Scene.empty(id: s1, title: "A"); sceneA.prose = "\(mention) was here."
        var sceneB = Scene.empty(id: s2, title: "B"); sceneB.prose = "No mention."
        var sceneC = Scene.empty(id: s3, title: "C"); sceneC.prose = "\(mention) and \(mention) again."
        project.manuscript.orphanedSceneIds = [s1, s2, s3]

        let index = MentionIndex.build(for: project, scenes: [s1: sceneA, s2: sceneB, s3: sceneC])
        try expectEqual(index.count(for: mia.id, in: s1), 1)
        try expectEqual(index.count(for: mia.id, in: s2), 0)
        try expectEqual(index.count(for: mia.id, in: s3), 2)
        try expectEqual(index.totalCount(for: mia.id), 3)
    }

    s.test("mentions to unknown entity ids are ignored") {
        var project = Project.empty(title: "T")
        let mia = Character(name: "Mia")
        project.bible.characters = [mia]
        // Reference to a stranger id — should not bleed into mia's count.
        let stranger = UUID()
        var scene = Scene.empty(id: UUID(), title: "S1")
        scene.prose = "Hello \(EntityReference(category: nil, id: stranger, displayName: "Ghost").markdown)."
        project.manuscript.orphanedSceneIds = [scene.id]

        let index = MentionIndex.build(for: project, scenes: [scene.id: scene])
        try expectEqual(index.totalCount(for: mia.id), 0)
        try expectEqual(index.totalCount(for: stranger), 0)   // not in bible — not tracked
    }

    s.test("settings + objects participate in the same index") {
        var project = Project.empty(title: "T")
        let baker = Setting(name: "221B")
        let pipe = BibleObject(name: "Pipe")
        project.bible.settings = [baker]
        project.bible.objects = [pipe]
        let bakerMention = EntityReference(category: .settings, id: baker.id, displayName: "221B").markdown
        let pipeMention = EntityReference(category: .objects, id: pipe.id, displayName: "Pipe").markdown
        var scene = Scene.empty(id: UUID(), title: "S1")
        scene.prose = "\(bakerMention) and the \(pipeMention) on the mantel."
        project.manuscript.orphanedSceneIds = [scene.id]

        let index = MentionIndex.build(for: project, scenes: [scene.id: scene])
        try expectEqual(index.totalCount(for: baker.id), 1)
        try expectEqual(index.totalCount(for: pipe.id), 1)
    }

    return s
}

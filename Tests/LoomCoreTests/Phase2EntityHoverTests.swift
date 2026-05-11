import Foundation
import AppKit
@testable import LoomCore

/// Phase 2.5 (#10 follow-on) — hover-preview popover for resolved
/// entity links in prose. Resolver pin-points the entity by id and
/// returns the info the popover shows (name + role chip + 200-char
/// description excerpt); the editor hosts the popover view and
/// drives visibility via mouseMoved → referenceAt → showPopover.
func phase2EntityHoverTests() -> TestSuite {
    let s = TestSuite("Phase2EntityHover")

    s.test("EntityHoverResolver: returns nil for an id that doesn't match any entity") {
        let project = Project.empty(title: "T")
        try expectNil(EntityHoverResolver.info(for: UUID(), in: project))
    }

    s.test("EntityHoverResolver: returns Character info") {
        var project = Project.empty(title: "T")
        var mia = Character(name: "Mia")
        mia.role = .protagonist
        mia.description = "Mia is the central voice — a quiet observer who notices what others miss."
        project.bible.characters = [mia]

        let info = try expectNotNil(EntityHoverResolver.info(for: mia.id, in: project))
        try expectEqual(info.displayName, "Mia")
        try expectEqual(info.roleLabel, "protagonist")
        try expectTrue(info.descriptionExcerpt.contains("Mia is the central voice"))
    }

    s.test("EntityHoverResolver: returns Setting info with no role chip") {
        var project = Project.empty(title: "T")
        let baker = Setting(name: "221B", description: "Holmes's cluttered sitting-room.")
        project.bible.settings = [baker]
        let info = try expectNotNil(EntityHoverResolver.info(for: baker.id, in: project))
        try expectEqual(info.displayName, "221B")
        try expectNil(info.roleLabel)   // settings have no role
    }

    s.test("EntityHoverResolver: trims description to 200 chars + ellipsis") {
        var project = Project.empty(title: "T")
        let longDescription = String(repeating: "abcdef ", count: 60)   // ~420 chars
        var mia = Character(name: "Mia")
        mia.description = longDescription
        project.bible.characters = [mia]
        let info = try expectNotNil(EntityHoverResolver.info(for: mia.id, in: project))
        try expectTrue(info.descriptionExcerpt.count <= 201)   // 200 + ellipsis
        try expectTrue(info.descriptionExcerpt.hasSuffix("…"))
    }

    s.test("Editor hover routing: pointing at a non-link location returns nil") {
        let session = ProjectSession(project: Project(title: "T"))
        _ = session.addCharacter(name: "Mia")
        let scene = session.addScene(title: "S1")
        session.selectScene(id: scene.id)
        session.updateProse(id: scene.id, prose: "Plain text here.")
        let vc = EditorViewController(session: session)
        _ = vc.view
        vc.reloadFromSession()
        try expectNil(vc.hoverInfoAt(characterIndex: 5))
    }

    s.test("Editor hover routing: pointing inside an entity link returns the info") {
        let session = ProjectSession(project: Project(title: "T"))
        let mia = session.addCharacter(name: "Mia")
        var updated = mia
        updated.description = "Protagonist."
        session.updateCharacter(updated)
        let scene = session.addScene(title: "S1")
        session.selectScene(id: scene.id)
        let mention = EntityReference(category: .characters, id: mia.id, displayName: "Mia").markdown
        let prose = "Hello \(mention) end."
        session.updateProse(id: scene.id, prose: prose)
        let mStart = (prose as NSString).range(of: mention).location

        let vc = EditorViewController(session: session)
        _ = vc.view
        vc.reloadFromSession()
        let info = try expectNotNil(vc.hoverInfoAt(characterIndex: mStart + 2))
        try expectEqual(info.displayName, "Mia")
    }

    return s
}

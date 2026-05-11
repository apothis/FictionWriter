import Foundation
import AppKit
@testable import LoomCore

/// Phase 3 §D — sidebar tree shows Part > Chapter > Scene hierarchy.
/// Drives NSOutlineViewDataSource methods directly to verify the
/// projection. Phase 3's hierarchy is opt-in: a project with only
/// orphan scenes still renders them flat under the Manuscript group
/// (Phase 1/2 behaviour preserved).
func phase3SidebarTreeTests() -> TestSuite {
    let s = TestSuite("Phase3SidebarTree")

    s.test("Manuscript group renders Parts first, then orphan scenes") {
        let session = ProjectSession(project: Project(title: "T"), scenes: [:])
        let orphan = session.addScene()
        let part = session.addPart(title: "Act 1")
        let sidebar = SidebarController(session: session)
        let ov = NSOutlineView()
        let manuscript = sidebar.outlineView(ov, child: 0, ofItem: nil)
        // 1 part + 1 orphan = 2 children.
        try expectEqual(sidebar.outlineView(ov, numberOfChildrenOfItem: manuscript), 2)
        let first = sidebar.outlineView(ov, child: 0, ofItem: manuscript) as? SidebarItem
        if case .part(let id) = first! {
            try expectEqual(id, part.id)
        } else {
            throw TestFailure(message: "expected .part(_)", file: #file, line: #line)
        }
        let second = sidebar.outlineView(ov, child: 1, ofItem: manuscript) as? SidebarItem
        if case .scene(let id) = second! {
            try expectEqual(id, orphan.id)
        } else {
            throw TestFailure(message: "expected .scene(_)", file: #file, line: #line)
        }
    }

    s.test("Part exposes its Chapters as children") {
        let session = ProjectSession(project: Project(title: "T"), scenes: [:])
        let part = session.addPart(title: "Act 1")
        _ = session.addChapter(title: "Ch 1", in: part.id)
        let chap2 = session.addChapter(title: "Ch 2", in: part.id)!
        let sidebar = SidebarController(session: session)
        let ov = NSOutlineView()
        let partItem: Any = SidebarItem.part(part.id)
        try expectEqual(sidebar.outlineView(ov, numberOfChildrenOfItem: partItem), 2)
        let second = sidebar.outlineView(ov, child: 1, ofItem: partItem) as? SidebarItem
        if case .chapter(let id) = second! {
            try expectEqual(id, chap2.id)
        } else {
            throw TestFailure(message: "expected .chapter(_)", file: #file, line: #line)
        }
    }

    s.test("Chapter exposes its Scenes as children") {
        let session = ProjectSession(project: Project(title: "T"), scenes: [:])
        let part = session.addPart(title: "Act 1")
        let chap = session.addChapter(title: "Ch 1", in: part.id)!
        let scene = session.addScene()
        session.placeScene(scene.id, in: chap.id)

        let sidebar = SidebarController(session: session)
        let ov = NSOutlineView()
        let chapItem: Any = SidebarItem.chapter(chap.id)
        try expectEqual(sidebar.outlineView(ov, numberOfChildrenOfItem: chapItem), 1)
        let child = sidebar.outlineView(ov, child: 0, ofItem: chapItem) as? SidebarItem
        if case .scene(let id) = child! {
            try expectEqual(id, scene.id)
        } else {
            throw TestFailure(message: "expected .scene(_)", file: #file, line: #line)
        }
    }

    s.test("Parts and Chapters are expandable; Scenes and Trash leaves are not") {
        let session = ProjectSession(project: Project(title: "T"), scenes: [:])
        let part = session.addPart(title: "Act 1")
        let chap = session.addChapter(title: "Ch 1", in: part.id)!
        let scene = session.addScene()
        let sidebar = SidebarController(session: session)
        let ov = NSOutlineView()
        try expectTrue(sidebar.outlineView(ov, isItemExpandable: SidebarItem.part(part.id)))
        try expectTrue(sidebar.outlineView(ov, isItemExpandable: SidebarItem.chapter(chap.id)))
        try expectFalse(sidebar.outlineView(ov, isItemExpandable: SidebarItem.scene(scene.id)))
    }

    s.test("Selecting a Part or Chapter is rejected — only scenes are selectable") {
        let session = ProjectSession(project: Project(title: "T"), scenes: [:])
        let part = session.addPart(title: "Act 1")
        let chap = session.addChapter(title: "Ch 1", in: part.id)!
        let scene = session.addScene()
        let sidebar = SidebarController(session: session)
        let ov = NSOutlineView()
        try expectFalse(sidebar.outlineView(ov, shouldSelectItem: SidebarItem.part(part.id)))
        try expectFalse(sidebar.outlineView(ov, shouldSelectItem: SidebarItem.chapter(chap.id)))
        try expectTrue(sidebar.outlineView(ov, shouldSelectItem: SidebarItem.scene(scene.id)))
    }

    s.test("Phase 1/2 (no parts) projects still render flat scenes under Manuscript") {
        // Regression check on the existing Phase 1 contract.
        let session = ProjectSession(project: Project(title: "T"), scenes: [:])
        _ = session.addScene()
        _ = session.addScene()
        let sidebar = SidebarController(session: session)
        let ov = NSOutlineView()
        let manuscript = sidebar.outlineView(ov, child: 0, ofItem: nil)
        try expectEqual(sidebar.outlineView(ov, numberOfChildrenOfItem: manuscript), 2)
    }

    return s
}

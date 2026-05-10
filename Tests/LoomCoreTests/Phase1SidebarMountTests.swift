import Foundation
import AppKit
@testable import LoomCore

/// Sub-step 1.e — honest smoke for SidebarController. Drives the
/// NSOutlineViewDataSource methods directly (no actual outline view
/// instance needed beyond a placeholder argument) to verify that the
/// sidebar's view of a session matches the session's contents. UI
/// rendering itself isn't unit-tested per the project's TDD posture.
func phase1SidebarMountTests() -> TestSuite {
    let s = TestSuite("Phase1SidebarMount")

    s.test("two top-level rows: Manuscript and Trash") {
        let session = ProjectSession(project: Project(title: "T"), scenes: [:])
        _ = session.addScene()
        let sidebar = SidebarController(session: session)
        let outlineView = NSOutlineView()
        let count = sidebar.outlineView(outlineView, numberOfChildrenOfItem: nil)
        try expectEqual(count, 2)
    }

    s.test("Manuscript group contains all orphaned scenes") {
        let session = ProjectSession(project: Project(title: "T"), scenes: [:])
        let s1 = session.addScene()
        _ = session.addScene()
        _ = session.addScene()
        let sidebar = SidebarController(session: session)
        let outlineView = NSOutlineView()
        let manuscript = sidebar.outlineView(outlineView, child: 0, ofItem: nil) as? SidebarItem
        let group = try expectNotNil(manuscript)
        if case .group(let kind) = group {
            try expectEqual(kind, .manuscript)
        } else {
            throw TestFailure(message: "expected .group(.manuscript)", file: #file, line: #line)
        }
        let manuscriptCount = sidebar.outlineView(outlineView, numberOfChildrenOfItem: group)
        try expectEqual(manuscriptCount, 3)
        let firstScene = sidebar.outlineView(outlineView, child: 0, ofItem: group) as? SidebarItem
        if case .scene(let id) = firstScene! {
            try expectEqual(id, s1.id)
        } else {
            throw TestFailure(message: "expected .scene(_)", file: #file, line: #line)
        }
    }

    s.test("Trash group reflects deleted scenes only") {
        let session = ProjectSession(project: Project(title: "T"), scenes: [:])
        let s1 = session.addScene()
        let s2 = session.addScene()
        session.deleteScene(id: s1.id)
        let sidebar = SidebarController(session: session)
        let outlineView = NSOutlineView()
        let trash = sidebar.outlineView(outlineView, child: 1, ofItem: nil) as? SidebarItem
        let group = try expectNotNil(trash)
        try expectEqual(sidebar.outlineView(outlineView, numberOfChildrenOfItem: group), 1)
        // And the manuscript group has 1 (s2), not 2.
        let manuscript = sidebar.outlineView(outlineView, child: 0, ofItem: nil) as? SidebarItem
        try expectEqual(sidebar.outlineView(outlineView, numberOfChildrenOfItem: manuscript), 1)
        let firstAlive = sidebar.outlineView(outlineView, child: 0, ofItem: manuscript) as? SidebarItem
        if case .scene(let id) = firstAlive! {
            try expectEqual(id, s2.id)
        } else {
            throw TestFailure(message: "expected .scene(_)", file: #file, line: #line)
        }
    }

    return s
}

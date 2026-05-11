import Foundation
import AppKit
@testable import LoomCore

/// Phase 2.5 follow-on (#10 polish) — `MentionPopover` smoke. The
/// data layer (EntityMentionContext, EntityAutocomplete,
/// EditorViewController.currentMentionContext/applyMention) was
/// shipped in Phase 2 #10. This suite pins the popover lifecycle:
///   - visibility tracks whether the cursor is in an @-context;
///   - the popover's published `matches` reflect the current query;
///   - selecting a row routes through applyMention(_:).
///
/// The visual rendering (panel position, table cell layout) is
/// honest UI — verified by running the app.
func phase2MentionPopoverTests() -> TestSuite {
    let s = TestSuite("Phase2MentionPopover")

    func setupEditor(with characters: [String], prose: String, cursorOffset: Int) -> (ProjectSession, EditorViewController, Scene) {
        let session = ProjectSession(project: Project(title: "T"))
        for n in characters { _ = session.addCharacter(name: n) }
        let scene = session.addScene(title: "S1")
        session.selectScene(id: scene.id)
        session.updateProse(id: scene.id, prose: prose)
        let vc = EditorViewController(session: session)
        _ = vc.view
        vc.reloadFromSession()
        vc.setCursorOffsetForTesting(cursorOffset)
        return (session, vc, scene)
    }

    s.test("popover stays hidden when the cursor is not in an @-context") {
        let (_, vc, _) = setupEditor(with: ["Mia"], prose: "Plain prose.", cursorOffset: 12)
        vc.refreshMentionPopover()
        try expectFalse(vc.isMentionPopoverVisibleForTesting)
    }

    s.test("popover becomes visible when the cursor enters an @-context") {
        let (_, vc, _) = setupEditor(with: ["Mia", "Mike"], prose: "Hello @M", cursorOffset: 8)
        vc.refreshMentionPopover()
        try expectTrue(vc.isMentionPopoverVisibleForTesting)
        let names = vc.mentionPopoverMatchesForTesting.map(\.displayName)
        try expectEqual(Set(names), ["Mia", "Mike"])
    }

    s.test("popover hides again when the cursor leaves the @-context") {
        let (_, vc, _) = setupEditor(with: ["Mia"], prose: "Hello @Mia", cursorOffset: 10)
        vc.refreshMentionPopover()
        try expectTrue(vc.isMentionPopoverVisibleForTesting)
        // Simulate the user moving the cursor away by trimming the
        // prose to remove the @-mention entirely.
        vc.setCursorOffsetForTesting(0)
        vc.refreshMentionPopover()
        try expectFalse(vc.isMentionPopoverVisibleForTesting)
    }

    s.test("commitMentionPopoverSelection inserts the highlighted entity's markdown") {
        let (session, vc, scene) = setupEditor(with: ["Mia"], prose: "Hello @M", cursorOffset: 8)
        vc.refreshMentionPopover()
        // Default highlight is row 0 — Mia is the only match.
        vc.commitMentionPopoverSelection()
        let updated = try expectNotNil(session.scenes[scene.id])
        try expectTrue(updated.prose.hasPrefix("Hello [Mia](#entity/"))
        // Popover dismisses on commit.
        try expectFalse(vc.isMentionPopoverVisibleForTesting)
    }

    s.test("dismissMentionPopover hides + does not modify prose") {
        let (session, vc, scene) = setupEditor(with: ["Mia"], prose: "Hello @M", cursorOffset: 8)
        vc.refreshMentionPopover()
        try expectTrue(vc.isMentionPopoverVisibleForTesting)
        vc.dismissMentionPopover()
        try expectFalse(vc.isMentionPopoverVisibleForTesting)
        let updated = try expectNotNil(session.scenes[scene.id])
        try expectEqual(updated.prose, "Hello @M")
    }

    s.test("moveMentionPopoverSelection cycles between matches") {
        let (_, vc, _) = setupEditor(with: ["Mia", "Mike", "Marcus"], prose: "Hi @M", cursorOffset: 5)
        vc.refreshMentionPopover()
        try expectEqual(vc.mentionPopoverSelectedIndexForTesting, 0)
        vc.moveMentionPopoverSelection(by: 1)
        try expectEqual(vc.mentionPopoverSelectedIndexForTesting, 1)
        vc.moveMentionPopoverSelection(by: 1)
        try expectEqual(vc.mentionPopoverSelectedIndexForTesting, 2)
        // Wraps at the end.
        vc.moveMentionPopoverSelection(by: 1)
        try expectEqual(vc.mentionPopoverSelectedIndexForTesting, 0)
        // Backwards wraps too.
        vc.moveMentionPopoverSelection(by: -1)
        try expectEqual(vc.mentionPopoverSelectedIndexForTesting, 2)
    }

    return s
}

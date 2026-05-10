import Foundation
@testable import LoomCore

/// Phase 2 (Settings UI): mutators on ProjectSession for the project-
/// level settings that the Settings window's Project tab edits —
/// memory, author's note, AN depth lines, context/reply token
/// budgets. Each setter must (a) write through to
/// `project.settings.*` and (b) flag the session dirty so the
/// debounced auto-save persists the change.
func phase2ProjectSettingsMutationsTests() -> TestSuite {
    let s = TestSuite("Phase2ProjectSettingsMutations")

    func freshSession() -> ProjectSession {
        let p = Project(title: "T")
        return ProjectSession(project: p, url: nil)
    }

    s.test("setMemory writes through to project.settings.memory") {
        let session = freshSession()
        session.setMemory("world rules: magic is rare")
        try expectEqual(session.project.settings.memory, "world rules: magic is rare")
    }

    s.test("setMemory marks the session dirty") {
        let session = freshSession()
        try expectFalse(session.isDirty)
        session.setMemory("anything")
        try expectTrue(session.isDirty)
    }

    s.test("setAuthorsNote writes through to project.settings.authorsNote") {
        let session = freshSession()
        session.setAuthorsNote("terse, vivid")
        try expectEqual(session.project.settings.authorsNote, "terse, vivid")
    }

    s.test("setAuthorsNote marks the session dirty") {
        let session = freshSession()
        session.setAuthorsNote("anything")
        try expectTrue(session.isDirty)
    }

    s.test("setAuthorsNoteDepthLines writes through and clamps negatives to zero") {
        let session = freshSession()
        session.setAuthorsNoteDepthLines(7)
        try expectEqual(session.project.settings.authorsNoteDepthLines, 7)
        session.setAuthorsNoteDepthLines(-3)
        try expectEqual(session.project.settings.authorsNoteDepthLines, 0, "negative depths should clamp to 0 — no special placement semantics defined below zero")
    }

    s.test("setContextBudgetTokens writes through to project.settings.contextBudgetTokens") {
        let session = freshSession()
        session.setContextBudgetTokens(16384)
        try expectEqual(session.project.settings.contextBudgetTokens, 16384)
        try expectTrue(session.isDirty)
    }

    s.test("setMaxOutputTokens writes through to generationDefaults.maxOutputTokens") {
        let session = freshSession()
        session.setMaxOutputTokens(2048)
        try expectEqual(session.project.settings.generationDefaults.maxOutputTokens, 2048)
        try expectTrue(session.isDirty)
    }

    return s
}

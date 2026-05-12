import Foundation
@testable import LoomCore

/// Phase 4 §14.1 follow-on (2026-05-13): rewrite-family system
/// prompts gain explicit scope-discipline language to address the
/// Gemma 4 31B over-contextualization failures pinned in §15.8 —
/// pulling in events from elsewhere in the same scene (Test 6),
/// pulling in characters/relationship histories from other scenes
/// (Test 7), extending narrative forward past source bounds
/// (Test 7).
///
/// The clause must appear in every selection-replacing rewrite
/// mode (`.rewrite`, `.rewriteVoice`, `.rewriteTense`,
/// `.rewriteLength`, `.rewritePOV`, `.showDontTell`) so the
/// contract is uniform across the picker's sub-modes.
///
/// Tests pin the *concept* (scope discipline + no time-axis
/// extension) rather than exact phrasing so the clause can be
/// rewritten without churning these tests, but a new mode without
/// any scope-discipline language at all will trip them.
func phase4RewriteFamilyScopeTests() -> TestSuite {
    let s = TestSuite("Phase4RewriteFamilyScope")

    func buildResult(mode: GenerationMode) -> AssembledPrompt {
        let scene = Scene.empty(id: UUID(), title: "Scene 1")
        var sceneCopy = scene
        sceneCopy.prose = "She walked into the room."
        var project = Project(title: "T")
        project.manuscript.orphanedSceneIds = [scene.id]
        let range = NSRange(location: 0, length: (sceneCopy.prose as NSString).length)
        let ctx = PromptContext(
            mode: mode,
            project: project,
            scenes: [scene.id: sceneCopy],
            currentSceneId: scene.id,
            cursorOffset: NSMaxRange(range),
            selectionRange: range,
            modelName: nil,
            contextBudgetTokens: project.settings.contextBudgetTokens,
            replyBudgetTokens: 1024,
            perCallInstruction: nil
        )
        return PromptBuilder.build(ctx)
    }

    let rewriteFamily: [GenerationMode] = [
        .rewrite,
        .rewriteVoice,
        .rewriteTense,
        .rewriteLength,
        .rewritePOV,
        .showDontTell,
    ]

    s.test("every rewrite-family system prompt commits to staying inside the selection") {
        for mode in rewriteFamily {
            let result = buildResult(mode: mode)
            let lower = result.systemBlock.lowercased()
            let mentionsScope =
                lower.contains("inside the selection") ||
                lower.contains("within the selection") ||
                lower.contains("inside the selection's bounds") ||
                lower.contains("strictly inside")
            try expectTrue(
                mentionsScope,
                "[\(mode.rawValue)] system prompt should commit to staying inside the selection's bounds — system block was: \(result.systemBlock)"
            )
        }
    }

    s.test("every rewrite-family system prompt forbids pulling in content from outside the selection") {
        for mode in rewriteFamily {
            let result = buildResult(mode: mode)
            let lower = result.systemBlock.lowercased()
            // Look for any of the "do not pull in / from outside / from other scenes" framings.
            let mentionsOutside =
                lower.contains("from outside the selection") ||
                lower.contains("from outside") ||
                lower.contains("other scenes") ||
                lower.contains("bible descriptions") ||
                lower.contains("not present in the selection") ||
                lower.contains("not in the selection")
            try expectTrue(
                mentionsOutside,
                "[\(mode.rawValue)] system prompt should explicitly forbid pulling in content from outside the selection — system block was: \(result.systemBlock)"
            )
        }
    }

    s.test("every rewrite-family system prompt forbids extending the narrative forward or backward in time") {
        for mode in rewriteFamily {
            let result = buildResult(mode: mode)
            let lower = result.systemBlock.lowercased()
            let mentionsTimeAxis =
                lower.contains("forward or backward in time") ||
                lower.contains("forward in time") ||
                lower.contains("backward in time") ||
                lower.contains("extend the narrative") ||
                lower.contains("narrative span")
            try expectTrue(
                mentionsTimeAxis,
                "[\(mode.rawValue)] system prompt should explicitly forbid time-axis extension past the selection — system block was: \(result.systemBlock)"
            )
        }
    }

    return s
}

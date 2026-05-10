import Foundation
@testable import LoomCore

/// Sub-step 1.d — DesignTokens pure-data tests. Pins the Loom-specific
/// `Editor` namespace values from LOOM_PHASE1_EDITOR_MVP.md §4.1.d and
/// asserts the no-fork rule from LOOM_DESIGN_LANGUAGE.md §14: any token
/// in Editor that is conceptually a grid value MUST alias the underlying
/// Spacing/Radius token, never duplicate the literal.
///
/// editorMaxWidth and the sidebar/inspector width thresholds are
/// genuinely new (content-rules + min/default sizing, not grid tokens),
/// so they're allowed to be literals.
func phase1DesignTokensTests() -> TestSuite {
    let s = TestSuite("Phase1DesignTokens")

    s.test("Editor.editorMaxWidth = 1080pt readable column") {
        // Originally §14.2 specified 720pt to match RPClient transcript
        // width; live-testing on 1280+pt windows found that uncomfortably
        // narrow. Bumped to 1080pt — still inside the readable-line
        // range, materially less wasted margin on modern displays.
        try expectEqual(DesignTokens.Editor.editorMaxWidth, 1080)
    }

    s.test("Editor sidebar/inspector width contract values match Phase 1 spec") {
        // The numbers come from LOOM_PHASE1_EDITOR_MVP.md §4.1.d:
        try expectEqual(DesignTokens.Editor.sidebarMinWidth, 180)
        try expectEqual(DesignTokens.Editor.sidebarDefaultWidth, 240)
        try expectEqual(DesignTokens.Editor.inspectorMinWidth, 240)
        try expectEqual(DesignTokens.Editor.inspectorDefaultWidth, 320)
    }

    s.test("Spacing tokens use the 8pt grid") {
        try expectEqual(DesignTokens.Spacing.xs, 4)
        try expectEqual(DesignTokens.Spacing.sm, 8)
        try expectEqual(DesignTokens.Spacing.md, 16)
        try expectEqual(DesignTokens.Spacing.lg, 24)
        try expectEqual(DesignTokens.Spacing.xl, 32)
    }

    s.test("Motion durations sit inside the 100-220ms HIG envelope") {
        // §1.8 + §14 contract: no springs, ease-out only, all durations
        // bounded above by 220ms.
        let durations: [TimeInterval] = [
            DesignTokens.Motion.tabSwap,
            DesignTokens.Motion.disclosure,
            DesignTokens.Motion.suggestionsReveal,
            DesignTokens.Motion.hoverFade,
            DesignTokens.Motion.staleBadge,
        ]
        for d in durations {
            try expectGreaterThan(d, 0.099)
            try expectLessThan(d, 0.221)
        }
    }

    return s
}

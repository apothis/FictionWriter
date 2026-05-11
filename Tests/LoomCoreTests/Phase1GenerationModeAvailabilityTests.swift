import Foundation
@testable import LoomCore

/// Sub-step 1.h — the pure rule that drives tray button enable state.
/// Per the contract: "given a (prose, selection) state, which modes
/// are enabled?"
///
/// Phase 1 modes:
///   - .continueProse: enabled when prose is non-empty.
///   - .expand: enabled when there's a non-empty selection.
///   - everything else (rewrite/brainstorm/critique/...): always
///     disabled (Phase 4 wires them).
func phase1GenerationModeAvailabilityTests() -> TestSuite {
    let s = TestSuite("Phase1GenerationModeAvailability")

    s.test("Continue enabled when prose is non-empty") {
        let state = EditorState(hasProse: true, hasSelection: false)
        try expectTrue(GenerationModeAvailability.isEnabled(.continueProse, in: state))
    }

    s.test("Continue disabled when prose is empty") {
        let state = EditorState(hasProse: false, hasSelection: false)
        try expectFalse(GenerationModeAvailability.isEnabled(.continueProse, in: state))
    }

    s.test("Continue still enabled if there happens to be a selection") {
        let state = EditorState(hasProse: true, hasSelection: true)
        try expectTrue(GenerationModeAvailability.isEnabled(.continueProse, in: state))
    }

    s.test("Expand enabled when selection is non-empty") {
        let state = EditorState(hasProse: true, hasSelection: true)
        try expectTrue(GenerationModeAvailability.isEnabled(.expand, in: state))
    }

    s.test("Expand disabled with no selection") {
        let state = EditorState(hasProse: true, hasSelection: false)
        try expectFalse(GenerationModeAvailability.isEnabled(.expand, in: state))
    }

    s.test("Rewrite enabled when selection is non-empty (Phase 1.5)") {
        let state = EditorState(hasProse: true, hasSelection: true)
        try expectTrue(GenerationModeAvailability.isEnabled(.rewrite, in: state))
    }

    s.test("Rewrite disabled with no selection (Phase 1.5)") {
        let state = EditorState(hasProse: true, hasSelection: false)
        try expectFalse(GenerationModeAvailability.isEnabled(.rewrite, in: state))
    }

    s.test("remaining Phase 4 modes stay disabled (post-rewriteVoice)") {
        // Phase 4 §14.1 #1 shipped .rewriteVoice; the rest of the sub-
        // modes (tense/POV/length, show-don't-tell, brainstorm, etc.)
        // remain disabled until their tickets land.
        let state = EditorState(hasProse: true, hasSelection: true)
        let enabledModes: Set<GenerationMode> = [.continueProse, .expand, .rewrite, .rewriteVoice]
        for mode in GenerationMode.allCases where !enabledModes.contains(mode) {
            try expectFalse(
                GenerationModeAvailability.isEnabled(mode, in: state),
                "\(mode.rawValue) should still be disabled"
            )
        }
    }

    s.test("empty editor (no prose, no selection) disables every mode") {
        let state = EditorState(hasProse: false, hasSelection: false)
        for mode in GenerationMode.allCases {
            try expectFalse(GenerationModeAvailability.isEnabled(mode, in: state))
        }
    }

    return s
}

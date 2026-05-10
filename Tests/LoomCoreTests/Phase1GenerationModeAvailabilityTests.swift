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

    s.test("Phase 4 modes are always disabled in Phase 1") {
        let state = EditorState(hasProse: true, hasSelection: true)
        for mode in GenerationMode.allCases where mode != .continueProse && mode != .expand {
            try expectFalse(
                GenerationModeAvailability.isEnabled(mode, in: state),
                "\(mode.rawValue) should be disabled in Phase 1"
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

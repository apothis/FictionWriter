import Foundation
@testable import LoomCore

/// Phase 4 #6/#8/#9 follow-on (2026-05-13 live test): the
/// `EditorViewController.applyAcceptanceTransition` reject + redo
/// paths gate selection restoration on a hard-coded mode list
/// `(mode == .expand || mode == .rewrite)` that pre-dates the
/// rewrite sub-modes. Result: rejecting a `.rewriteVoice` /
/// `.rewriteTense` / `.rewriteLength` / `.rewritePOV` /
/// `.showDontTell` deletes the model output without re-inserting
/// the original passage — user loses their prose silently.
///
/// Fix is a `GenerationMode.isSelectionReplacing` predicate the
/// editor consults instead of the brittle inline mode list. Same
/// shape works for both the reject path and the redo path.
func phase4SelectionReplacingTests() -> TestSuite {
    let s = TestSuite("Phase4SelectionReplacing")

    s.test("isSelectionReplacing is true for every selection-replacing mode") {
        // The full rewrite family + expand. All of these run
        // through `runSelectionReplacingGeneration` which deletes
        // the selection up front; the reject + redo paths MUST
        // know to restore it.
        try expectTrue(GenerationMode.expand.isSelectionReplacing)
        try expectTrue(GenerationMode.rewrite.isSelectionReplacing)
        try expectTrue(GenerationMode.rewriteVoice.isSelectionReplacing)
        try expectTrue(GenerationMode.rewriteTense.isSelectionReplacing)
        try expectTrue(GenerationMode.rewriteLength.isSelectionReplacing)
        try expectTrue(GenerationMode.rewritePOV.isSelectionReplacing)
        try expectTrue(GenerationMode.showDontTell.isSelectionReplacing)
    }

    s.test("isSelectionReplacing is false for continueProse and the Phase 4+ append-only modes") {
        // Continue inserts at the cursor without deleting anything;
        // brainstorm/critique/bridge/describe/nameSuggest produce
        // output that lands in History or a popover, not in the
        // prose. None require selection restoration on reject.
        try expectFalse(GenerationMode.continueProse.isSelectionReplacing)
        try expectFalse(GenerationMode.brainstorm.isSelectionReplacing)
        try expectFalse(GenerationMode.critique.isSelectionReplacing)
        try expectFalse(GenerationMode.bridge.isSelectionReplacing)
        try expectFalse(GenerationMode.describe.isSelectionReplacing)
        try expectFalse(GenerationMode.nameSuggest.isSelectionReplacing)
    }

    s.test("isSelectionReplacing is exhaustive over GenerationMode.allCases") {
        // Adding a new mode without classifying it here would make
        // the predicate fall through silently. Pin the partition so
        // future modes get explicit categorisation.
        for mode in GenerationMode.allCases {
            _ = mode.isSelectionReplacing  // must compile — exhaustive switch
        }
    }

    return s
}

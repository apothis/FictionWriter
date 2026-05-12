import Foundation

/// Behavior predicates on `GenerationMode`. Pure data, AppKit-free
/// so the contract stays unit-testable — the editor consults these
/// in `applyAcceptanceTransition` (reject + redo) to know whether
/// the original selection needs restoring after the model output
/// is removed.
extension GenerationMode {
    /// True when this mode deletes the user's selection up-front
    /// and replaces it with generated prose. The reject + redo
    /// paths use this to know they need to re-insert the saved
    /// `lastSelectionContext` text after removing the model
    /// output.
    ///
    /// The previous inline check `(mode == .expand || mode ==
    /// .rewrite)` in `applyAcceptanceTransition` pre-dated the
    /// Phase 4 §14.1 #6 / #8 / #9 rewrite sub-modes — rejecting
    /// any of those silently dropped the original prose into a
    /// hole. The 2026-05-13 live test surfaced it (rewriteTense
    /// rejection on Scene B).
    public var isSelectionReplacing: Bool {
        switch self {
        case .expand,
             .rewrite,
             .rewriteVoice,
             .rewriteTense,
             .rewriteLength,
             .rewritePOV,
             .showDontTell:
            return true
        case .continueProse,
             .brainstorm,
             .critique,
             .bridge,
             .describe,
             .nameSuggest:
            return false
        }
    }
}

import Foundation

/// Snapshot of the editor's content-and-selection state, fed to the
/// generation tray so it can enable/disable mode buttons. Pure data;
/// no AppKit references — testable.
public struct EditorState: Equatable {
    public var hasProse: Bool
    public var hasSelection: Bool

    public init(hasProse: Bool = false, hasSelection: Bool = false) {
        self.hasProse = hasProse
        self.hasSelection = hasSelection
    }
}

/// Per-mode enable rule. Phase 1 supports Continue + Expand; everything
/// else (rewrite/brainstorm/critique/...) is Phase 4+ and stays
/// disabled here so the tray buttons reflect that visually.
public enum GenerationModeAvailability {
    public static func isEnabled(_ mode: GenerationMode, in state: EditorState) -> Bool {
        switch mode {
        case .continueProse:
            return state.hasProse
        case .expand:
            return state.hasSelection
        case .rewrite, .rewriteVoice, .rewriteTense, .rewritePOV, .rewriteLength,
             .showDontTell, .brainstorm, .critique, .bridge, .describe, .nameSuggest:
            return false
        }
    }
}

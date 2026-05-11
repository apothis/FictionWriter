import Foundation

/// Activation mode for a Bible entity in the prompt-assembler.
///
/// - `.constant`: always injected (current Phase 1 behaviour).
/// - `.keyed`: injected only when the entity's name or any alias
///   appears in the recent-prose window. The NovelAI / KoboldAI /
///   SillyTavern "lorebook keyed" convention (LOOM_MEMORY.md §A2.4).
///
/// Phase 2 #7 ships this as the per-entity affordance; the
/// `.vectorised` mode (semantic-similarity injection) is Phase 5 R&D
/// and lives on `LorebookEntry.ActivationMode` rather than here, so
/// Bible entities themselves stay binary for now.
public enum InjectionMode: String, Codable, Equatable, CaseIterable {
    case constant
    case keyed
}

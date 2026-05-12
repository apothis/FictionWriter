import Foundation

/// One row in the Rewrite-sub-mode picker that pops up when the
/// tray's Rewrite button is clicked. Pure-data so the menu shape can
/// be pinned without an AppKit dependency; the tray glue converts
/// each choice into an `NSMenuItem` and stamps `representedObject`
/// with the `RewriteSubModeChoice` so the click handler can resolve
/// (mode, descriptor, tray-instruction-passthrough) unambiguously.
public struct RewriteSubModeChoice: Equatable {
    /// Human-readable label shown in the menu.
    public let title: String
    /// `GenerationMode` to fire on click.
    public let mode: GenerationMode
    /// Fixed `perCallInstruction` value when `usesTrayInstruction == false`.
    /// `nil` here means "no per-call instruction layer" (generic frame).
    public let descriptor: String?
    /// When true, the click handler ignores `descriptor` and pulls
    /// the user's typed text from the tray's instruction field
    /// instead (with empty-string mapping to nil). Used by Voice,
    /// whose target descriptor is freeform and authored at call time.
    public let usesTrayInstruction: Bool
    /// For rewritePOV entries: the target bible-character id. The
    /// controller resolves this at click time, calls
    /// `LedgerKnowledge.compute(...)` against the current scene,
    /// formats the result through `RewritePOVDescriptor.build(...)`,
    /// and fires with that structured descriptor. Other modes carry
    /// nil — the picker tests pin that default.
    public let povCharacterId: UUID?
    /// Phase 4 §15.9 — if non-nil, the AppKit glue renders this entry
    /// as disabled and shows the reason as a tooltip / subtitle. Used
    /// by the rewriteTense no-op-target guard: when the heuristic says
    /// the selection is already in past tense, the "Tense — past"
    /// entry's `disabledReason` is set to a short user-readable note
    /// so the picker doesn't even offer the no-op pick. The click
    /// handler also short-circuits defensively in case `disabledReason`
    /// is bypassed (autoenables, race against selection change, etc.).
    public let disabledReason: String?

    public init(
        title: String,
        mode: GenerationMode,
        descriptor: String?,
        usesTrayInstruction: Bool = false,
        povCharacterId: UUID? = nil,
        disabledReason: String? = nil
    ) {
        self.title = title
        self.mode = mode
        self.descriptor = descriptor
        self.usesTrayInstruction = usesTrayInstruction
        self.povCharacterId = povCharacterId
        self.disabledReason = disabledReason
    }
}

/// Static descriptor list for the Rewrite menu. Order is the menu's
/// visual order; AppKit glue inserts `NSMenuItem.separator()`
/// between distinct `mode` groups (Voice → Tense → Length → Generic).
///
/// All descriptors are stylistic — no content directives. The
/// LOOM_NSFW.md §3 content-neutrality directive holds: this menu
/// shapes the *form* of the rewrite, never gates the content.
public enum RewriteSubModeMenuBuilder {
    /// The Voice/Tense/Length cluster — same shape regardless of
    /// bible state. Separated out so the picker can slot dynamic
    /// POV entries between this group and the generic-rewrite
    /// suffix (Phase 4 §14.1 #8).
    private static let staticPrefix: [RewriteSubModeChoice] = [
        RewriteSubModeChoice(
            title: "Voice — use instruction field",
            mode: .rewriteVoice,
            descriptor: nil,
            usesTrayInstruction: true
        ),
        RewriteSubModeChoice(title: "Tense — past", mode: .rewriteTense, descriptor: "past"),
        RewriteSubModeChoice(title: "Tense — present", mode: .rewriteTense, descriptor: "present"),
        RewriteSubModeChoice(title: "Length — 50% (compressed)", mode: .rewriteLength, descriptor: "50%"),
        RewriteSubModeChoice(title: "Length — 80% (tightened)", mode: .rewriteLength, descriptor: "80%"),
        RewriteSubModeChoice(title: "Length — 120% (expanded)", mode: .rewriteLength, descriptor: "120%"),
        RewriteSubModeChoice(title: "Length — 150% (longer)", mode: .rewriteLength, descriptor: "150%"),
    ]

    /// Show-don't-tell + generic escape hatch — the static tail
    /// after any dynamic POV entries. SDT goes first so its
    /// dramatisation feels like a peer of the structural rewrites
    /// rather than an afterthought below Generic.
    private static let staticSuffix: [RewriteSubModeChoice] = [
        RewriteSubModeChoice(title: "Show, don't tell (~120% length)", mode: .showDontTell, descriptor: nil),
        RewriteSubModeChoice(title: "Generic rewrite", mode: .rewrite, descriptor: nil),
    ]

    /// Static choice list when no bible characters are available
    /// (or the caller doesn't need POV entries). Backwards-compatible
    /// with the pre-#8 API.
    public static let choices: [RewriteSubModeChoice] = staticPrefix + staticSuffix

    /// Phase 4 §14.1 #8 — full picker list including one
    /// `.rewritePOV` entry per bible character, slotted between the
    /// Length presets and the show-don't-tell + generic suffix.
    /// POV entries carry `povCharacterId` only; the descriptor (with
    /// KNOWLEDGE_LEDGER_HINT bullets) is computed at click time by
    /// the controller via `LedgerKnowledge.compute` +
    /// `RewritePOVDescriptor.build`.
    ///
    /// Phase 4 §15.9 — when `currentSelectionTense` is `.past` or
    /// `.present`, the matching `Tense — …` entry is stamped with a
    /// `disabledReason` so the AppKit glue can render it as a
    /// disabled menu item. `.unknown` (default) leaves both entries
    /// enabled and lets the click handler / model handle the call.
    public static func choices(
        povCharacters: [Character],
        currentSelectionTense: SelectionTense = .unknown
    ) -> [RewriteSubModeChoice] {
        let povEntries = povCharacters.map { character in
            RewriteSubModeChoice(
                // Phase 4 §15.10 — phrased as an action ("Rewrite
                // to X's POV") rather than a setter ("POV — X") to
                // disambiguate from the sidebar's "Set POV" submenu,
                // which assigns the scene's editorial POV and is a
                // distinct operation. See HANDOFF §15.8 entry.
                title: "Rewrite to \(character.name)'s POV",
                mode: .rewritePOV,
                descriptor: nil,
                usesTrayInstruction: false,
                povCharacterId: character.id
            )
        }
        let raw = staticPrefix + povEntries + staticSuffix
        return raw.map { applyTenseGuard($0, currentSelectionTense: currentSelectionTense) }
    }

    /// Stamps `disabledReason` on a tense entry whose descriptor
    /// matches the current selection's classified tense. Other
    /// entries pass through unchanged.
    private static func applyTenseGuard(
        _ choice: RewriteSubModeChoice,
        currentSelectionTense: SelectionTense
    ) -> RewriteSubModeChoice {
        guard choice.mode == .rewriteTense else { return choice }
        guard currentSelectionTense != .unknown else { return choice }
        guard let descriptor = choice.descriptor, descriptor == currentSelectionTense.rawValue else { return choice }
        return RewriteSubModeChoice(
            title: choice.title,
            mode: choice.mode,
            descriptor: choice.descriptor,
            usesTrayInstruction: choice.usesTrayInstruction,
            povCharacterId: choice.povCharacterId,
            disabledReason: "Selection is already in \(descriptor) tense."
        )
    }
}

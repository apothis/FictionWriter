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

    public init(title: String, mode: GenerationMode, descriptor: String?, usesTrayInstruction: Bool = false) {
        self.title = title
        self.mode = mode
        self.descriptor = descriptor
        self.usesTrayInstruction = usesTrayInstruction
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
    public static let choices: [RewriteSubModeChoice] = [
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
        RewriteSubModeChoice(title: "Generic rewrite", mode: .rewrite, descriptor: nil),
    ]
}

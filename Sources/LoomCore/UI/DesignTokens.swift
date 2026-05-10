import AppKit

/// In-code embodiment of [`LOOM_DESIGN_LANGUAGE.md`](../../../LOOM_DESIGN_LANGUAGE.md).
/// Every Loom surface imports these tokens; magic numbers in layout /
/// typography / color call sites are bugs.
///
/// Reference platform: macOS 26 Tahoe / Liquid Glass. §1–§13 are inherited
/// verbatim from RPClient; §14 introduces Loom-specific surfaces (editor,
/// binder, inspector). The `Editor` namespace below is the new-for-Loom
/// extension — it must alias `Spacing` / `Radius` tokens whenever the
/// concept is a grid value, never duplicate the literal.
public enum DesignTokens {

    /// 8pt baseline grid. Five tokens — anything else is wrong (§3).
    public enum Spacing {
        /// 4 — inside chips/pills, between an icon and its label.
        public static let xs: CGFloat = 4
        /// 8 — default control padding, tight-list row gap.
        public static let sm: CGFloat = 8
        /// 16 — relaxed form-row gap, section-heading-to-first-row.
        public static let md: CGFloat = 16
        /// 24 — between sections inside a tab, popover margins.
        public static let lg: CGFloat = 24
        /// 32 — tab-body outer padding.
        public static let xl: CGFloat = 32
    }

    /// Apple text-style scale. Use the named tokens; never raw point sizes
    /// (the system Dynamic Type setting drives the actual size). §2.
    public enum Typography {
        public static var largeTitle: NSFont { NSFont.preferredFont(forTextStyle: .largeTitle) }
        public static var title1: NSFont { NSFont.preferredFont(forTextStyle: .title1) }
        public static var title2: NSFont { NSFont.preferredFont(forTextStyle: .title2) }
        public static var title3: NSFont { NSFont.preferredFont(forTextStyle: .title3) }
        /// 13pt semibold — field labels, list-row primary text, table column
        /// headers. The semibold/regular contrast against `body` is the
        /// hierarchy contract; do not substitute color for it.
        public static var headline: NSFont { NSFont.preferredFont(forTextStyle: .headline) }
        public static var body: NSFont { NSFont.preferredFont(forTextStyle: .body) }
        public static var callout: NSFont { NSFont.preferredFont(forTextStyle: .callout) }
        /// Hint text below a field, secondary metadata.
        public static var subheadline: NSFont { NSFont.preferredFont(forTextStyle: .subheadline) }
        public static var footnote: NSFont { NSFont.preferredFont(forTextStyle: .footnote) }
        public static var caption1: NSFont { NSFont.preferredFont(forTextStyle: .caption1) }
        public static var caption2: NSFont { NSFont.preferredFont(forTextStyle: .caption2) }

        /// Monospaced face at the same size as the named text style. Used
        /// for technical / numeric content per §11 — token counts, dates,
        /// version numbers, word counts in the status strip.
        public static func mono(_ style: NSFont.TextStyle, weight: NSFont.Weight = .regular) -> NSFont {
            let size = NSFont.preferredFont(forTextStyle: style).pointSize
            return NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        }
    }

    /// Foreground (text + glyph) color tokens. Semantic NSColor only — they
    /// adapt to light/dark/high-contrast/accent automatically. §4.
    public enum Foreground {
        public static var primary: NSColor { .labelColor }
        public static var secondary: NSColor { .secondaryLabelColor }
        public static var tertiary: NSColor { .tertiaryLabelColor }
        public static var quaternary: NSColor { .quaternaryLabelColor }
        /// Use sparingly — primary action of a view, focused control,
        /// selected item. Three accents in one view = two are wrong (§1.4).
        public static var accent: NSColor { .controlAccentColor }
        public static var destructive: NSColor { .systemRed }
        public static var warning: NSColor { .systemYellow }
        public static var success: NSColor { .systemGreen }
    }

    /// Background color tokens. §4.
    public enum Background {
        public static var window: NSColor { .windowBackgroundColor }
        public static var textInput: NSColor { .textBackgroundColor }
        public static var group: NSColor { .controlBackgroundColor }
        public static var selectedRow: NSColor { .selectedContentBackgroundColor }
    }

    /// Animation durations. Restraint over expression — macOS isn't iOS
    /// (§8). All durations sit inside the 100-220ms HIG envelope; springs
    /// are forbidden, ease-out / ease-in-out only.
    public enum Motion {
        public static let tabSwap: TimeInterval = 0.180
        public static let disclosure: TimeInterval = 0.220
        public static let suggestionsReveal: TimeInterval = 0.160
        public static let hoverFade: TimeInterval = 0.120
        public static let staleBadge: TimeInterval = 0.100
    }

    /// Corner radii — concentricity (outer wraps inner). §1.2.
    public enum Radius {
        /// Window itself — macOS 26 standard.
        public static let window: CGFloat = 26
        /// Section / card surface inside content area.
        public static let section: CGFloat = 14
        /// Form control (button, text field, pill).
        public static let control: CGFloat = 8
        /// Chip / pill / token-field token.
        public static let chip: CGFloat = 4
    }

    /// Loom-specific editor surface tokens — §14 of the design language,
    /// per the LOOM_PHASE1_EDITOR_MVP.md §4.1.d contract.
    ///
    /// **No-fork rule.** Anything that can be expressed as an alias MUST
    /// alias the underlying Spacing/Radius token. `editorMaxWidth` and
    /// the per-pane width thresholds are genuinely new (content-rules,
    /// not grid tokens), so they sit as literals.
    public enum Editor {
        /// Content column max width — readable-line target. Original
        /// design language §14.2 specified 720pt (matching RPClient's
        /// transcript width); live testing 2026-05-10 found that 720
        /// leaves uncomfortably wide margins on a 1280+pt window.
        /// Bumped to 1080pt — still inside the readable-line range
        /// (~95-105 chars at 13pt body, vs the 60-75 char "perfect"
        /// target) but materially reduces the empty-margin feeling
        /// on modern displays. Per-project / global setting is a
        /// Phase 2 polish candidate.
        public static let editorMaxWidth: CGFloat = 1080

        /// Sidebar (Binder) bounds. Defaults sit inside the §14.2 range
        /// (220–360pt resizable, min 180pt); the Phase 1 contract pins
        /// the specific defaults below.
        public static let sidebarMinWidth: CGFloat = 180
        public static let sidebarDefaultWidth: CGFloat = 240

        /// Inspector bounds. §14.2 range is 280–420pt; the Phase 1
        /// contract opens the inspector at 320pt.
        public static let inspectorMinWidth: CGFloat = 240
        public static let inspectorDefaultWidth: CGFloat = 320
    }
}

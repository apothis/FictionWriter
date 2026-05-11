# Loom Design Language

**Status: living document, forked from RPClient V2 Design Language 2026-05-10.** §1–§13 below are inherited verbatim from `/Volumes/SSD1/Code/RPClient/V2_DESIGN_LANGUAGE.md` — that doc is the platform-truth source for system-level decisions (typography scale, spacing tokens, color, materials, motion, density posture, application contract). §14 onward is **Loom-specific**: long-form editor surface, Bible inspector, project tree, History chiclets, generation-mode buttons, empty-state.

References in §1–§13 to "RPClient" should be read as "the inherited application contract." References to specific RPClient surfaces (chat header, TurnView, Card Creator) are kept in place because they are the proving grounds where the contract was first applied — Loom's surfaces apply the same contract to a different domain. Where §1–§13 says "this app," substitute "Loom."

The reference platform is **macOS 26 Tahoe / "Liquid Glass"** (Apple's 2025 WWDC25 design language, shipped with macOS 26). Loom is unsandboxed AppKit; nothing here requires SwiftUI. WWDC25 session 310 ("Build an AppKit app with the new design") and the macOS HIG Materials / Typography / Designing-for-macOS pages are the source-of-truth references.

---

## 1. Principles

Five load-bearing rules. Every design decision in the app should fall out of one of these.

1. **Power-user dense, not consumer-airy.** RPClient is a deliberate scene-construction tool. We lean denser than Mail / Notes — but density doesn't mean cramming. It means **earning** every visible control. A control that's used <10% of sessions belongs behind a hover/focus reveal, not in the chrome. (V2_PLAN §8 calls out the existing chat header as an anti-pattern: Server + Attribution + Voice + speaker mute all permanently visible at 28pt. This is what we're correcting.)
2. **Concentricity.** Inner radii echo outer radii: a 26pt window houses 14pt sections containing 8pt fields containing 4pt chips. Spacing follows the same logic — 24pt section gaps, 16pt row gaps, 8pt control gaps, 4pt token gaps. A reader's eye finds rhythm without consciously parsing it.
3. **Material conveys depth, not ornament.** Glass and vibrancy are spatial cues — sidebar is *behind* content, popover is *above* content. Don't apply glass for visual interest; apply it where the depth metaphor is real. Translucency without spatial purpose is noise.
4. **One accent, used sparingly.** The system accent color is reserved for: the primary action of any view, the focused control, the selected item. Everything else is the system gray hierarchy (`labelColor` → `secondaryLabelColor` → `tertiaryLabelColor` → `quaternaryLabelColor`). If three things are accented in one view, two are wrong.
5. **Progressive disclosure for the non-essential.** Anything that's not required for the 80% case lives behind a reveal — disclosure triangle, hover-only chip, focus-only control, "Show advanced" sheet. The default view is the dense common path; the long tail is one click away. Always one click — never buried two layers deep.

A design choice that violates a principle should be corrected, not justified. Exceptions get loud comments in code so future readers know it's deliberate.

---

## 2. Typography

System font is **SF Pro** (the macOS default — `NSFont.systemFont(ofSize:)`). All sizes follow Apple's 2026 macOS scale; we never invent sizes.

| Token | pt | Weight | Use |
|---|---|---|---|
| `largeTitle` | 26 | Regular | Window-level page titles. Used sparingly — at most once per window. |
| `title1` | 22 | Regular | Major section headings. Tab body opening titles. |
| `title2` | 17 | Regular | Sub-section headings. |
| `title3` | 15 | Regular | Group headings inside a section. |
| `headline` | 13 | **Semibold** | Field labels, list-row primary text, table column headers. |
| `body` | 13 | Regular | Default body text. Field input. Multi-line content. |
| `callout` | 12 | Regular | Inline annotations next to body text. |
| `subheadline` | 11 | Regular | Field hint text below input (paired with `secondary` color, not `tertiary`), secondary metadata. |
| `footnote` | 10 | Regular | Tertiary text. Disabled-state captions. |
| `caption1` | 10 | Regular | Smallest visible text. Avatar captions, tag pills. |

**Rules.**

- Use the named `NSFont.preferredFont(forTextStyle:)` API where possible — it scales with the user's accessibility text-size preference. Fixed-point sizes only when the layout depends on a specific metric (rare).
- Field labels are `headline` (13pt semibold). Field input is `body` (13pt regular). The semibold/regular contrast is the visual hierarchy — don't substitute color for it.
- Multi-line content (description / personality / scenario / system_prompt) uses `body`. Don't shrink to fit; let the user scroll.
- Monospace (SF Mono, `NSFont.monospacedSystemFont(ofSize: 11)`) is reserved for code-shaped content: the `extensions` JSON viewer, debug logs, raw JSON previews. Never for prose.

Existing offenders to fix during the future overhaul: chat header uses 13pt for everything; should be `headline` for the chat title and `subheadline` for server / mode metadata.

---

## 3. Spacing

8pt baseline grid. Five named tokens — anything not in this list is wrong.

| Token | pt | Use |
|---|---|---|
| `xs` | 4 | Inside chips / pills / token-field tokens. Between an icon and its label. |
| `sm` | 8 | Default control padding. Between rows in a tight list. Default form-row vertical gap. |
| `md` | 16 | Between form rows in a relaxed layout. Between a section heading and its first row. |
| `lg` | 24 | Between sections inside a tab. Margin around a single section in a popover. |
| `xl` | 32 | Tab-body outer padding. Top of a window-content-area to first heading. |

Window-edge insets: `lg` (24pt) on every side of the content area (inside the window chrome / sidebar / inspector). Sections inside the content area get `xl` (32pt) top breathing room from the window edge.

Avoid: 12pt, 20pt, 28pt. They feel "almost right" because they're between grid stops, which is exactly why they look off.

---

## 4. Color

Use **system** semantic colors, never raw hex. The app should adapt automatically across light / dark / increase-contrast / accent-color preferences.

### Foreground

| Use | Token |
|---|---|
| Primary text (field input, body) | `NSColor.labelColor` |
| Field labels, secondary metadata, **hint text below a field** | `NSColor.secondaryLabelColor` |
| **Placeholder text *inside* an empty field**, low-priority captions | `NSColor.tertiaryLabelColor` |
| Disabled | `NSColor.quaternaryLabelColor` |

Hint text below a field is **explanatory copy the user reads**, not a temporary stand-in — `tertiaryLabelColor` is too dim at 11pt subheadline (especially in light mode). Reserve `tertiaryLabelColor` for the text *inside* an empty input field that disappears on first keystroke. This was a §5.3a smoke-test correction; the original draft conflated the two.
| Primary action (button title), focused field outline, selected list row | `NSColor.controlAccentColor` |
| Destructive action | `NSColor.systemRed` |
| Warning chip (refusal-detected, depth_prompt-not-routed) | `NSColor.systemYellow` |
| Success | `NSColor.systemGreen` |

### Background

| Use | Token |
|---|---|
| Window content | `NSColor.windowBackgroundColor` (auto-adapts to material) |
| Field input chrome | `NSColor.textBackgroundColor` |
| Selected row | `NSColor.alternatingContentBackgroundColors[1]` or `NSColor.selectedContentBackgroundColor` |
| Group / section background | `NSColor.controlBackgroundColor` |

### Speaker / cast color hashing

Phase 8's [`SpeakerColor`](Sources/RPClientCore/UI/SpeakerColor.swift) deterministic palette stays as the source of truth for per-speaker accents. Don't pick palettes ad-hoc in new surfaces.

---

## 5. Materials & layering

Liquid Glass is the macOS 26 default. Apply with intent.

### Window structure

- **Window** itself adopts the standard 26pt window corner radius automatically; don't override.
- **Sidebar** (chat list, library grid) uses `NSSplitViewController` with the sidebar split-item behavior. AppKit applies the floating glass material — **do not** put an `NSVisualEffectView` inside the sidebar; it will block the glass.
- **Inspector** (chat detail panes, future card-bound context) uses the inspector split-item behavior — edge-to-edge glass alongside content.
- **Content area** is opaque (`.windowBackgroundColor`). Material is only at the chrome boundaries.

### Custom glass surfaces

Use `NSGlassEffectView` for surfaces that genuinely sit "above" content — popovers, floating panels, hover cards. Set `contentView` so AppKit applies legibility treatments (vibrancy, contrast pulls) automatically. Don't compose glass yourself with stacked `NSVisualEffectView`s; the API does it correctly.

### Materials we don't use

- The deprecated `.sidebar` material (legacy NSVisualEffectView) — superseded by sidebar split-item behavior.
- Multi-layer glass stacking. One pane of glass, one depth stop. Stacking doesn't add depth; it adds noise.
- Translucent buttons or fields. Glass is for chrome, not content controls.

---

## 6. Controls

### Sizing

Apple's 2026 sizes. Pick by visual weight in context, not by personal preference.

| Size | Shape | Use |
|---|---|---|
| `mini` | Rounded rect | Inline sublabels (rare). |
| `small` | Rounded rect | Dense forms (creator-window-style field sets). |
| `regular` | Rounded rect | Default. Most controls. |
| `large` | Capsule | Primary action of a sheet / dialog. |
| `extraLarge` | Capsule | Hero buttons (rare; not used in RPClient today). |

Concentricity: the corner shape echoes the size. Mixing `small` rounded rect with `large` capsule in the same row reads as broken; pick one and commit.

### Buttons

- Primary action = `NSButton.bezelStyle = .rounded`, `.controlSize = .regular`, `keyEquivalent = "\r"` for the default action of a view.
- Secondary actions: same bezel, no key equivalent.
- Destructive: `.bezelStyle = .rounded` plus `.hasDestructiveAction = true` (renders red text in macOS 26).
- Icon-only buttons in chrome: `NSButton.bezelStyle = .toolbar` or borderless with a hover-state outline.
- Avoid the deprecated `.recessed` / `.regularSquare` styles for new code.

### Form fields

- Text input: `NSTextField.bezelStyle = .roundedBezel`, `controlSize` matching surrounding controls.
- Multi-line: `NSTextView` inside `NSScrollView` with `hasVerticalScroller = true`, `autohidesScrollers = true`. Min height 96pt, grows-to-fit up to 320pt before scrolling.
- Token field: `NSTokenField` with `tokenStyle = .rounded`. Autocomplete via `tokenField(_:completionsForSubstring:indexOfToken:indexOfSelectedItem:)`.
- Pop-up: `NSPopUpButton.bezelStyle = .rounded`. For long lists (>20 items), use a search-field-driven sheet instead.

### Focus + selection

- Focus ring: system default (`focusRingType = .default`). Don't suppress it; it's the keyboard-navigation contract.
- Hover: hover-only secondary controls fade in over 120ms. Use `NSTrackingArea` with `.mouseEnteredAndExited`.
- Selected-row indicator: 2pt accent rule on the leading edge for list rows, full `selectedContentBackgroundColor` fill for dense table rows.

---

## 7. Iconography

**SF Symbols 6** (the macOS 26-bundled set) for everything.

- Use `NSImage(systemSymbolName:accessibilityDescription:)`. Always pass an accessibility label.
- Symbol weight: `.regular` by default, `.semibold` to match `headline` text contexts.
- Symbol scale: `.medium` for inline, `.large` for primary toolbar actions.
- Variants: prefer the `.fill` variant for selected / active states, outline for default. Don't mix in the same row.
- Color: inherit from foreground (`tintColor` / `contentTintColor`). Don't hard-code symbol colors.

Custom glyphs are forbidden when an SF Symbol exists. The chat-view's `✦` placeholder for character-less assistant turns is one of two existing exceptions and should migrate to `person.crop.circle` during the future pass.

---

## 8. Motion

Subtle. macOS isn't iOS; motion shouldn't draw attention.

| Action | Duration | Easing |
|---|---|---|
| Tab swap inside a tabbed window | 180ms | `easeOut` |
| Disclosure expand / collapse | 220ms | `easeInOut` |
| Suggestions strip reveal (Phase 9 §4.1) | 160ms | `easeOut` |
| Hover-secondary control fade | 120ms | `linear` |
| Sheet present | system default (don't override) |
| Window appear | system default (don't override) |
| Stale-badge appearance | 100ms cross-fade |

Avoid: spring animations (consumer iOS feel), bounce, rotation. macOS motion is restrained translation + opacity. Anything else feels off-platform.

---

## 9. Density posture

RPClient's specific stance on the density-vs-air axis. This is where the app diverges from consumer-grade chat (ChatGPT, Claude.ai) and aligns with power-user tools (Linear, Xcode, Things 3 in pro mode).

- **Default to dense.** A pane that fits 12 rows in the viewport beats one that fits 8. Padding above the platform default is a smell.
- **Earn every visible control.** Header chrome should carry only what the user touches once per session minimum. Per-turn / per-card actions live in hover / context menus, not the chrome.
- **Reveal long-tail on focus or hover.** AI-assist suggestions strip is closed by default; depth-prompt advanced controls are behind a disclosure; the extensions JSON viewer is one tab away. The 80% path is never dragged through the 20% surface.
- **One unified scale.** The user's font-size preference (system Dynamic Type) drives every text size. RPClient's per-window or per-pane scale overrides — the existing `uiFontOffset` setting — are technical-debt to be removed during the overhaul, not extended.

---

## 10. Anti-patterns (existing app to fix later)

Known violations of this language in the current app. Catalogued so the future UI overhaul has a punch list.

- **Chat header density.** Server + Attribution + Voice + speaker mute all permanently visible. Should collapse: chat title visible, server/mode/voice in a hover-revealed metadata strip, mute as a hover icon over the avatar.
- **Inspector pane visual inconsistency.** Memory / World / Cast / Branches / Tree / Suggestions panes don't share a visual grammar — different padding, different label weights, different empty-state copy styles.
- **Voice library window separation.** A dedicated window for what should be a Settings tab. Rehome during the overhaul.
- **`uiFontOffset` setting.** Per-app font scaling override. Replaced by macOS Dynamic Type. Remove.
- **Custom glyph use.** `✦` for character-less assistant turns. Replace with `person.crop.circle` SF Symbol.
- **Settings → Servers row layout.** Profile rows mix bezel styles (rounded text field next to a borderless icon button). Pick one bezel family.

This list grows during the overhaul; don't fold corrections into Phase 9.

---

## 11. Beyond Apple HIG — modern UX patterns we adopt

Apple's HIG is the macOS platform contract. It's also conservative — designed to make any AppKit app feel "native" without committing to the design taste of any specific tool. The strongest modern productivity tools blend HIG correctness with web/design-system thinking: Linear, Things 3, Notion, Vercel/Geist, Figma, Stripe Dashboard, Raycast. RPClient pulls deliberately from each.

What we borrow, and from where:

- **Visual weight by importance (Linear).** Not every element of the interface carries equal visual weight. The parts central to the user's task stay in full color and weight; navigation, orientation, and chrome recede to `secondaryLabelColor` / regular weight. Creator window: field input is `labelColor` body; the field's hint text below it is `tertiaryLabelColor` `subheadline`; the tab strip at top is `secondaryLabelColor`. The eye knows what's the work and what's the wayfinding.
- **Multi-modal action surfacing (Linear).** Every action in the app should be reachable through *all* of: a visible button, a keyboard shortcut, a context-menu item, and (eventually) a command palette. Different users build different muscle memory; the interface stays consistent across modes. Creator window: Save / Cancel both have keyboard shortcuts (`⌘S` / `Esc`); Generate / Refresh on the suggestions strip have shortcuts; tab switching has shortcuts (`⌘1`-`⌘7`). Cmd-K palette is deferred to the overhaul but the design space is reserved (no shortcut conflicts).
- **Aggressive reduction (Vercel/Geist).** When in doubt, remove. The premium feel comes from consistency applied to a narrow palette, not from added decoration. RPClient already runs a narrow palette (system semantic colors only). Apply the same posture to controls: if a feature can be a single button instead of a button + helper-icon + tooltip, make it the single button.
- **Monospace for technical / numeric content (Vercel/Geist).** Numbers that the user reads precisely (token counts, depth values, dates, version numbers, byte counts in the extensions viewer) use `NSFont.monospacedSystemFont(ofSize:, weight:)`. Numbers in prose stay in the body font. Mixing matters: tabular numerics (`numericFeatures` in CTFont attributes) for vertical alignment in tables; proportional in inline contexts.
- **Hover-revealed drag handles (Notion).** List-row reorder UI appears on hover, not as a permanent column. The §3.2 alternateGreetings list editor uses a 16pt grip handle that fades in on row hover (120ms `linear`); the row itself is the click target for editing. Permanent grip columns clutter the row's leading edge for a feature used <5% of the time.
- **Slash / inline commands (Notion / Cursor) — flagged for future.** Inline AI-assist as ghost text (Cursor / Copilot pattern, predict-and-accept) is an alternative shape to the §4.1 Suggestions strip. Strip wins for Phase 9 because it's deliberate and the author's focus stays in the field. Ghost text is more invasive and faster — flagged as a future-direction power-user mode, not in §5.3.
- **Calm motion despite density (Linear).** Linear runs on the same restraint Apple HIG mandates — 100-220ms durations, ease-out, no springs. Confirms the §8 Motion budgets. Web tools that lean into Framer-style spring motion (Vercel marketing pages) feel wrong inside a productivity tool; the budget for character animation is the user's data, not the chrome.
- **System-as-tokens (Tailwind / shadcn / Geist).** A design system is a set of named tokens, not a set of pixel values. The §3 spacing tokens, §2 typography names, §4 color names, §6 control sizes are *the* contract; raw values are an escape hatch for the rare exception. This is what makes future-overhaul work tractable: search for `lg` and find every section gap in the app.
- **Power-user keyboard density (Raycast / Things).** Keyboard shortcuts cover everything reachable by mouse. The creator window's Identity / Persona / Greetings / Examples / System / Lorebook / Advanced tabs map to `⌘1` through `⌘7`. Save / Cancel / Generate / Refresh / new-greeting / remove-greeting all bound. Rule: if a button exists without a shortcut, the shortcut got forgotten — file it as a follow-up.
- **Inline-editable list items (Notion / Linear).** Multi-row content (alternateGreetings, source URLs, group_only_greetings) is edited *in place*, not via "click row → opens edit sheet". The row IS the edit surface; clicking-out commits. Eliminates the modal-sheet-per-row friction.

What we deliberately *don't* borrow:

- **Notion's slash command for everything.** Heavy slash syntax inside a roleplay character description would interfere with NSFW prose where authors legitimately type `/scene-break` or other markup. Slash is for app-shaped content (issues, docs); creator fields are author-shaped content.
- **Vercel-style pure-black / pure-white aggressive contrast.** Beautiful on web marketing; jarring on macOS where the system is gentler about extremes. Stick with `labelColor` / `tertiaryLabelColor` semantic grays.
- **Material 3 / Material You's adaptive theming pulled from a single seed color.** macOS users expect their accent color to behave the way every other macOS app behaves. Don't reinvent.
- **Spring physics, parallax, blur reveal motion (Framer / iOS marketing).** Off-platform. macOS motion is restrained translation + opacity.
- **Command palette as the primary navigation (Raycast).** RPClient is a chat client; the chat list and library are visual-spatial, not text-search-driven. Cmd-K complements but doesn't replace the sidebar.

## 12. Application contract for new surfaces

Any new view added to RPClient from this point on must:

- Use named text styles (no raw `NSFont.systemFont(ofSize: 15)` calls).
- Stick to the spacing tokens (no 12pt or 20pt gaps).
- Use semantic colors (no `NSColor(red:..., green:..., blue:...)` for foreground).
- Use SF Symbols (no custom glyphs).
- Earn every permanently-visible control (or relegate to hover / disclosure).
- Pick one control size family per view (mini-medium *or* large-xl, not mixed).
- Bind every visible button to a keyboard shortcut (multi-modal action surfacing, §11).
- Use monospace for technical / numeric content; body for prose (§11).

Reviewer expectation: the diff should be answerable in design-language-token terms. "Section gap is `lg`" beats "section gap is 24pt". If the answer requires a magic number, the magic number is wrong.

### 12.1 Posture toward existing app code

The current app's `Theme.swift` (the `uiFontOffset`-driven font helper) and the existing inspector panes are **not** the contract. They're catalogued in §10 as anti-patterns to be migrated during the future UI overhaul. New surfaces don't extend them.

In code: new views import `DesignTokens.swift` (Phase 9 §5.3a — the in-code embodiment of this doc), not `Theme.swift`. The two coexist during the migration window; the migration plan lives in V2_UI_OVERHAUL.md when that lands. Don't grow `Theme.swift`; let it shrink.

The creator window is the proving ground for this contract. If the design language can't make the creator window feel right, the contract is wrong — but the existing chat header / inspector panes / settings forms are not what we measure against.

---

## 13. References

**Apple — platform contract:**
- [Designing for macOS — HIG](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos).
- [macOS Materials — HIG](https://developer.apple.com/design/human-interface-guidelines/foundations/materials/).
- [Typography — HIG](https://developer.apple.com/design/human-interface-guidelines/foundations/typography/).
- [Adopting Liquid Glass — Apple Developer Documentation](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass).
- [WWDC25 Session 310 — Build an AppKit app with the new design](https://developer.apple.com/videos/play/wwdc2025/310/).
- [WWDC25 Session notes (community)](https://wwdcnotes.com/documentation/wwdcnotes/wwdc25-310-build-an-appkit-app-with-the-new-design/).

**Beyond Apple — modern UX references we draw from:**
- [Linear — UI redesign rationale (visual weight, density, calm motion)](https://linear.app/now/how-we-redesigned-the-linear-ui).
- [Linear — calmer interface for a product in motion](https://linear.app/now/behind-the-latest-design-refresh).
- [The Elegant Design of Linear.app — Tela Blog](https://telablog.com/the-elegant-design-of-linear-app/).
- [Geist — Vercel design system](https://vercel.com/geist/introduction).
- [Geist Font — monospace + sans-serif from one family](https://vercel.com/font).
- [Things 3 — typography hierarchy + dynamic type adoption](https://culturedcode.com/things/features/).
- Notion (slash commands, inline editing, hover-revealed drag handles) — UX precedent without canonical doc.
- Stripe Dashboard (numerical data styling, dense forms with disclosure) — UX precedent without canonical doc.
- Raycast (keyboard-everywhere posture) — UX precedent without canonical doc.

**Internal:**
- [`V2_PLAN.md`](/Volumes/SSD1/Code/RPClient/V2_PLAN.md) §8 — RPClient's deferred UI overhaul (this doc's progenitor).
- [`V2_PHASE9_CARD_CREATOR.md`](/Volumes/SSD1/Code/RPClient/V2_PHASE9_CARD_CREATOR.md) — the first surface that fully applied this language.

---

## 14. Loom-specific surfaces (extension)

Everything below is **new for Loom** — surfaces that don't exist in RPClient and require their own anatomy. The §1–§13 contract still holds; this section specifies *application*, not new tokens.

Citations to research findings reference [`LOOM_RESEARCH.md`](LOOM_RESEARCH.md) — bracketed identifiers like `[J1]`, `[A5]`, `[E1]` map to that document's source list. **Visual-pattern decisions in §14.4–§14.6 reference [`LOOM_UI_RESEARCH.md`](LOOM_UI_RESEARCH.md) for the live-captured prior art they derive from.**

### 14.1 Application contract for Loom surfaces

In addition to §12.0's contract:

- **Long-form prose is the protagonist.** Editor surface chrome must recede further than chat-pane chrome did in RPClient. The user is in a 2,000-word document; the AI affordances must be present-but-not-shouting.
- **No chat-shaped vocabulary.** "Turn" / "speaker" / "send" / "regenerate" are wrong words. Use "scene" / "POV" / "generate" / "redo." Audited per surface.
- **Generation context must be visible.** Sudowrite's History chiclets[A5] are the floor — every generation event surfaces *what was sent* one click away, not buried.
- **AI-generated prose is visually distinguishable from human-written prose** during a brief acceptance window (§14.6). After acceptance, it's just prose — no permanent badge.

### 14.2 Window anatomy

Single-window-per-project. Three vertical zones (top to bottom): **Toolbar · Workspace · Status strip** with horizontal split inside the workspace.

```
┌─ Toolbar (system; project title; mode pickers; ⓘ inspector toggle) ──────────┐
│                                                                              │
├─ Workspace (NSSplitView, three columns by default) ──────────────────────────┤
│ ┌─ Sidebar (Binder) ─┬─ Editor pane ──────────────────────┬─ Inspector ────┐ │
│ │ ▾ My Novel         │  Chapter 4 · Scene 12              │  Bible         │ │
│ │   ▾ Part I         │                                    │  History       │ │
│ │     ▾ Ch 1         │  She glances up from her book…     │  Notes         │ │
│ │       Scene 1      │                                    │                │ │
│ │       Scene 2      │  [content]                          │                │ │
│ │     ▾ Ch 2         │                                    │                │ │
│ │   ...              │                                    │                │ │
│ │ ▾ References       │  [generation tray bottom-pinned]   │                │ │
│ │ ▾ Trash            │                                    │                │ │
│ └────────────────────┴────────────────────────────────────┴────────────────┘ │
├─ Status strip (word counts; cursor scene; server status; token estimate) ────┤
└──────────────────────────────────────────────────────────────────────────────┘
```

**Width budgets:**

- Sidebar: 220–360pt (resizable, persisted per project). Min 180pt.
- Editor pane content: max 1080pt (matches RPClient transcript max-width §4.3 — same readable-line target). Below 1080pt window width, fills 100% with `lg` (24pt) horizontal padding.
- Inspector: 280–420pt (resizable, persisted). Min 240pt.

Below ~1100pt window width, the inspector collapses to a `ⓘ` toggle in the toolbar (RPClient §4.0.f pattern), reopens as an overlay.

### 14.3 Sidebar (Binder)

Hierarchical tree mirroring Scrivener's Binder[J1]. Outline-shape:

- **Project root** (one per window).
  - **Manuscript folder** — Parts → Chapters → Scenes (Phase 3+ adds Parts; Phase 1 is flat scene list under one implicit chapter).
  - **References** — uploaded reference texts (Phase 5+).
  - **Trash** — deleted scenes; survives close, emptied explicitly (per `<destructive_actions>` discipline).

Row anatomy: 22pt height, `headline` text (13pt semibold) for primary, `subheadline` (11pt secondary) for word-count or status. Selection: 2pt accent rule on leading edge for the primary tree (matches §6.4 list-row indicator).

Expand/collapse triangles use system disclosure conventions (NSOutlineView default). Drag-rearrange is **always-on**, not hover-revealed (Notion pattern §11 doesn't apply — reorder is a primary novelist activity, not a niche action).

**Per-row hover affordances** (§9 hover-reveal posture): `+ scene` button on chapter rows; `⋯` overflow with rename / duplicate / delete on every row.

**Sidebar empty state** (new project, no scenes): one button, `New scene`, centred, body text "An empty book is just kindling." — single sentence, italic, `secondaryLabelColor`. Click creates the first scene; cursor lands in the editor.

### 14.4 Editor pane

The single most important surface in Loom.

**Text view.** `NSTextView` inside `NSScrollView`, `usesFindBar = true`, `isAutomaticTextReplacementEnabled = false` (off by default; users may enable in Settings — fiction prose suffers from "smart" replacement). Line height 1.45× body font (research-grade readable density; matches Ulysses).

**Width.** Content max 1080pt centred (§14.2). Below that, fills width with `lg` margins.

**Typography.** Body font is `body` (13pt regular per §2). Italics `secondaryLabelColor` only when the user toggles "italic for narration" preference — **default is `labelColor` italic**, since fiction italics are first-class prose, not metadata. (Distinct from RPClient §4.7 italic-tint, which was RP-action-marker convention.)

**Cursor + selection.** System default; nothing customised.

**Markdown rendering.** **Off by default in the editor** — fiction prose is plain text. A "Preview" mode (`⌘⇧P`) renders markdown for export-shape preview; not the editing surface. Headers (`# Chapter Twelve`) display as plain text in the editor.

**Generation tray** (bottom-pinned, in the editor pane below the text view, not the window status strip). The bottom tray handles **cursor-driven** modes (Continue) — modes that work without a selection. Selection-driven modes use the floating selection toolbar (§14.4.1, new) instead.

```
┌─ Generation tray ─────────────────────────────────────────────────────────┐
│ [Continue ↪] [Brainstorm ✦] [Critique ◐] [⋯ more]                         │
│                                                                            │
│  ▸ History ⓘ                                          last gen: 1.2k tok  │
└────────────────────────────────────────────────────────────────────────────┘
```

- Mode buttons: `regular` rounded-rect, `headline` text, SF Symbol (medium), single accent only when **focus is in the editor and the mode would do something**. Selection-required modes (Rewrite / Expand / Describe) live in the floating selection toolbar instead, not here.
- The **History disclosure** below the buttons expands inline (180ms easeOut) to reveal the chiclets for the last generation: chips for "20k recent prose · 2 character bible entries · author's note · style sheet" — clickable per chip to open the source.[A5] This is the load-bearing transparency feature.
- **Token estimate** on the trailing edge: pre-computed estimate of what will be sent if the user clicks the highlighted mode. Updates on cursor change. Monospace per §11.

#### 14.4.1 Inline floating selection toolbar (NEW — live-captured Sudowrite + Novelcrafter pattern, [`LOOM_UI_RESEARCH.md`](LOOM_UI_RESEARCH.md) §B.1.1, §B.2.6, §D.2)

When prose is selected in the editor, a floating capsule toolbar fades in (120ms `linear`), anchored above the selection. It combines formatting and AI-generation controls — the convergent pattern from both Sudowrite and Novelcrafter.

```
┌─────────────────────────────────────────────────────────────────────┐
│ 12 words · B I U S H 〝 H¶ • | Rewrite ↻  Expand ⤢  Describe 👁  ⋯ │
└─────────────────────────────────────────────────────────────────────┘
```

- **Word-count chip** leading-most: `caption1` monospace (Novelcrafter pattern). Updates live.
- **Formatting cluster**: Bold / Italic / Underline / Strike / Highlight / Quote / Heading / List icons (matching `Markdown.swift` capabilities). Phase 1 ships these.
- **Visual separator** (`|` divider).
- **AI-mode cluster**: selection-driven modes only (Rewrite / Expand / Describe). Phase 4 ships when modes wire up.
- **Overflow** (`⋯`): rarely-used modes (Show-don't-tell, Bridge, future additions).

Capsule shape; `controlBackgroundColor` background with subtle shadow; positioned via `NSTextView`'s selection-rect with smart-flip-on-clip logic (anchor below selection if no room above).

Reveal: 120ms fade-in on selection-non-empty; 100ms fade-out on selection-empty. Suppressed during typing-into-selection (ghost-text path).

**Empty editor state** (new scene, no prose): one centred suggestion: "Start typing — or paste a sketch and click **Expand**." `secondaryLabelColor`, `body`. No placeholder ghost text inside the field (per §4 placeholder vs hint distinction).

### 14.5 Inspector pane (right side)

Tabbed (RPClient inspector pattern, §6 anti-pattern note). Tabs across the top: **Bible · History · Notes**.

#### 14.5.1 Bible tab — list-detail two-pane (UPDATED 2026-05-10 from live Novelcrafter capture)

**Original spec was a flat collapsible-disclosure stack. Updated spec adopts Novelcrafter's list-detail two-pane** — materially better for browsing entities at scale ([`LOOM_UI_RESEARCH.md`](LOOM_UI_RESEARCH.md) §B.2.1, §D.1).

Layout (within the Bible tab of the right inspector):

```
┌─ Bible inspector ─────────────────────────────────────────┐
│ [ All 16 · Characters 8 · Settings 4 · Objects 3 · ... ]  │  ← filter tab strip
├───────────────────────────────────────────────────────────┤
│ ╭──────────────────╮ ╭──────────────────────────────────╮ │
│ │ Characters     + │ │ [Avatar 32pt] Sherlock Holmes  ⋯ │ │
│ │  ▸ Sherlock H.   │ │               Protagonist        │ │
│ │  ▸ John Watson   │ │ ━━━─────━━━━━─────  18 mentions │ │  ← sparkline
│ │  ▸ Sigerson      │ │                                  │ │
│ │ Settings       + │ │ Description Knowledge Relations  │ │  ← per-entity tabs
│ │  ▸ 221B Baker St │ │ Mentions Notes                   │ │
│ │  ▸ Reichenbach   │ │ ─────────────────────────────────│ │
│ │ Objects        + │ │                                  │ │
│ │  ▸ Pipe          │ │ [tab content]                    │ │
│ │ ...              │ │                                  │ │
│ ╰──────────────────╯ ╰──────────────────────────────────╯ │
└───────────────────────────────────────────────────────────┘
```

- **Filter tab strip** at top: All · Characters · Settings · Objects · Factions · Lorebook · Timeline · Style · Suggestions. Counts in `caption1` after the label. Click filters the list.
- **Left list** (40% of inspector width, scrollable): category sections with `+` add-button; entities under each. Selected entity highlighted with 2pt accent rule.
- **Right detail** (60% of inspector width, scrollable): the selected entity.
  - **Header**: 32pt avatar (initial-circle if no portrait per [`SpeakerColor.swift`](Sources/RPClientCore/UI/SpeakerColor.swift)) · name (`title2` / 17pt) · role chip (`caption1` / 10pt secondary) · `⋯` overflow.
  - **Mention sparkline** (Phase 4+): thin horizontal bar with marker dots at each scene mentioning the entity; numeric label `N mentions` trailing. Click a marker → editor scrolls to that scene. Updates as the manuscript is edited (debounced).
  - **Per-entity sub-tabs**: `Description / Knowledge ledger / Relationships / Mentions / Notes`. Knowledge ledger is the [`LOOM_STORY_BIBLE.md`](LOOM_STORY_BIBLE.md) §3 schema, rendered inline.
  - **Tab content** edits in place (Notion pattern §11) — click to enter edit; click outside or `Esc` to commit.

**Adding entities.** `+` at any category section header creates a new entity in that category, lands selection on the right pane, cursor in the name field.

**Entity references in prose.** When the user types `@<name>` in the editor:

1. Autocomplete popover lists matching entities by name + alias.
2. Selecting one inserts the display name; the underlying markdown stores a link `[Mia](#entity/<uuid>)` — invisible link colour (uses `labelColor`, not the system blue) so fiction prose doesn't show hyperlinks.
3. **Hover preview popover** (Novelcrafter B.2.4 pattern, [`LOOM_UI_RESEARCH.md`](LOOM_UI_RESEARCH.md) §D.3): hovering an entity link in the editor shows a popover with the entity's avatar + name + role + first 200 chars of description + buttons `[Open] [← Open in left split] [→ Open in inspector]`.
4. On generation, links resolve to entity references in the prompt (their full bible content gets injected per [`LOOM_MEMORY.md`](LOOM_MEMORY.md) §4.1 BIBLE-keyed layer).

Phase 1 ships only minimal-character editing inline (no list-detail two-pane yet); Phase 2 ships the full inspector with the layout above.

#### 14.5.2 History tab

The full record of generation events for the current project. Per RPClient §4.7 collapse-disclosure pattern, each event is a row that expands to show:

- Mode + timestamp + model used.
- "What was sent" (full assembled prompt, viewable as raw text or formatted).
- "What came back" (raw output from model).
- Token counts (prompt / completion / total).
- Buttons: `Re-roll` (re-generate same prompt), `Insert again` (paste output back into editor at cursor).

This is the most generous transparency surface in any AI-fiction tool. Sudowrite's History chiclets[A5] are the closest precedent and they only show *labels* of what was sent. Loom shows the full text.

#### 14.5.3 Notes tab

A free-form notepad scoped to the project. Plain text, persists with project. For thoughts that don't belong in the manuscript or the Bible.

### 14.6 Generation modes — visual identity

When a generation finishes, the inserted prose is displayed with a **temporary acceptance state** (refined 2026-05-10 from live Sudowrite capture, [`LOOM_UI_RESEARCH.md`](LOOM_UI_RESEARCH.md) §B.1.2, §D.4):

- 6pt accent rule on the leading edge of the inserted block (matches RPClient §4.0.d variants pill — same accent system).
- **Subtle background tint** on the inserted block: `controlAccentColor` at ~6% alpha. Visible enough to clearly delineate AI prose during review; subtle enough not to dominate. Combined with the rule, the AI block is unmistakable during the review window.
- Three buttons floating just above the inserted block: **Accept (⏎)** · **Reject (⌫)** · **Keep & redo (⌘⇧R)**.
- **After acceptance**: the rule + tint fade out over 180ms easeOut, the buttons disappear, the prose is just prose. **No permanent badge** — this matches §1.5 (progressive disclosure for the non-essential).

If the user types into the inserted block before accepting, the acceptance state implicitly resolves to Accept (per Cursor / GitHub Copilot ghost-text convention).

Multi-output (when the model returns N candidates) is rendered as horizontally-paged variants with a `◀ 1/3 ▶` pill below the inserted block (matches RPClient §4.0.d variants pill verbatim — use the same `CapsulePill` primitive once Loom inherits it). [`LOOM_UI_RESEARCH.md`](LOOM_UI_RESEARCH.md) §C.9 confirms this is the convergent pattern (ChatGPT, Claude, RPClient).

**Visual differentiation at non-acceptance:** No permanent visual distinction between AI-written and human-written prose after acceptance. This is the §1.5 progressive-disclosure principle. The History tab ([§14.5.2](#1452-history-tab)) preserves the *record* of what came from AI; the editor doesn't display it.

### 14.7 Empty project state

New project, no scenes:

- Centred 96pt SF Symbol `book.closed.fill` in `tertiaryLabelColor`.
- Below: project title in `title2` (17pt regular).
- Below: one button `Create the first scene`, `large` capsule, `controlAccentColor` tint.
- That's it. No "tips" carousel, no onboarding tour. The user is here because they want to write.

### 14.8 Status strip (bottom of window)

Single 22pt strip across the window bottom, contents flush:

- **Leading**: project word count (current scene) / total — monospace per §11.
- **Centre**: cursor scene title (`secondaryLabelColor`, single click to open scene metadata popover).
- **Trailing**: server status indicator (single dot — green / yellow / red) + token-budget estimate — monospace.

`headline` weight, `caption1` size — small but readable.

### 14.9 Keyboard shortcuts (Loom-specific)

Multi-modal action surfacing per §11. Loom-specific shortcut budget (in addition to inherited RPClient shortcuts):

| Shortcut | Action |
|---|---|
| `⌘N` | New scene (in current chapter) |
| `⌘⇧N` | New chapter |
| `⌘1` … `⌘9` | Jump to scene 1…9 in current chapter |
| `⌘E` | Expand selection |
| `⌘⇧E` | Continue (from cursor) |
| `⌘R` | Rewrite selection |
| `⌘B` | Brainstorm (popover) |
| `⌘⇧K` | Critique scene |
| `⌘⇧B` | Bridge selection (transition between two passages) |
| `⏎` (in acceptance state) | Accept generated prose |
| `⌫` (in acceptance state) | Reject generated prose |
| `⌘⇧R` (in acceptance state) | Keep & redo (re-generate same prompt) |
| `⌘\|` | Toggle inspector |
| `⌘⌥\|` | Toggle sidebar |
| `⌘⇧F` | Project-wide search |
| `⌘⇧P` | Toggle markdown preview mode |

### 14.9.1 Project Settings pill-picker block (NEW from live Novelcrafter capture)

The Project Settings inspector area (Phase 2+) exposes the project's structural defaults as **horizontal pill pickers** ([`LOOM_UI_RESEARCH.md`](LOOM_UI_RESEARCH.md) §B.2.12, §D.6):

```
POV          [ 1st · 2nd · 3rd · 3rd-Limited · 3rd-Omniscient ]
Tense        [ Past · Present ]
Direction    [ Literary · Mainstream · Romance · Erotica · Porn ]   ← LOOM_NSFW.md §3.1
Vocabulary   [ Clinical · Literary · Earthy · Crude · Mixed ]
Explicitness [ Fade-to-Black · Suggestive · On-Screen · Graphic · Extreme ]
```

Each row: label (`headline` semibold, leading) + pill-segmented control (`controlAccentColor` highlight on selected). Per-scene override available via Scene metadata popover (Phase 3).

Phase 2 ships POV + Tense pickers; Direction + Vocabulary + Explicitness land alongside [`LOOM_NSFW.md`](LOOM_NSFW.md) §3 schema.

### 14.9.2 Focus Mode (NEW — confirmed across all surveyed tools)

Per [`LOOM_UI_RESEARCH.md`](LOOM_UI_RESEARCH.md) §D.7. Toggle: `⌘⇧F` (or `⌘.` to match Scrivener Composition Mode convention; user preference).

When active:
- Sidebar collapses (animation 220ms `easeInOut`).
- Inspector collapses (same).
- Toolbar fades to a thin auto-hiding strip (revealed on cursor-near-top hover, 100ms `linear`).
- Editor expands to fill available width (still capped at 1080pt content max).
- Optional preference: **current-paragraph emphasis** — paragraphs other than the one containing the cursor dim to `tertiaryLabelColor`. iA Writer pattern; off by default.

Re-toggle restores layout. Status strip remains visible at the bottom (word count is too useful to hide).

Phase 1 candidate (cheap to implement); Phase 2 floor.

### 14.9.3 Marker Timeline beside Binder (NEW — Phase 3+)

From Novelcrafter live capture ([`LOOM_UI_RESEARCH.md`](LOOM_UI_RESEARCH.md) §B.2.8, §D.8): a thin vertical color-coded strip beside the Binder showing scene lengths in proportion across the manuscript.

- Width: 16pt fixed.
- Each scene rendered as a colored block; height ∝ word count; color encodes status (`todo` / `draft` / `revised` / `final` per [`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md) §2 `SceneStatus`).
- Hover any block: tooltip with scene title + chapter + word count.
- Click a block: scrolls Binder + editor to that scene.
- Toggle in Settings: "Show length timeline beside Binder" (off by default; on for users who manage long projects).

Phase 3+. Off in Phase 1-2; the data model already carries the metadata.

### 14.10 Anti-patterns to avoid (Loom-specific)

- **Chat-shaped UI.** No "send button" framing. Generation buttons are imperative verbs (Continue, Expand) not "Send" or "Submit."
- **Permanent AI-generated badge** on text. Acceptance is the one-time signal; after that, prose is prose.
- **Modal sheets for entity editing.** Every Bible entry edits in-place per §11 inline-editable list pattern.
- **Hidden generation context.** Every chiclet expandable to full text. No "trust us, the right context was sent."
- **Auto-fill the Bible** without user consent. Sudowrite's Bible auto-generation[A2] is offered, never imposed.
- **AI-generated prose visually identical to human prose during the typing window.** The user must be able to tell what came from where, briefly, before deciding to keep it.

### 14.11 Open design questions for later phases

- Phase 3+: **Corkboard view** — does it replace the editor pane, or is it a tab beside it? Lean: tab beside (Scrivener has both; users switch). To be answered when Phase 3 lands.
- Phase 4: **Knowledge ledger surfacing** — where does "Mia knows X as of Scene 7" live? Likely in the Bible tab, expanded section per character. To be answered in [`LOOM_STORY_BIBLE.md`](LOOM_STORY_BIBLE.md).
- Phase 5: **Style ingestion UI** — drop-zone for a 200k-word reference + visible processing pipeline (chunk → embed → index → tag). To be answered when Phase 5 lands.
- **Variant scenes** (multiple drafts of the same scene). Snapshots? Tabs? Carousel? To be answered Phase 2+.

---

## 15. Loom application contract — additions

In addition to §12, any new Loom surface must:

- Use `[gen]`, `[bible]`, `[editor]`, `[project]`, `[rag]`, `[ledger]`, `[style]` `DebugLog` subsystem prefixes per surface domain (RPClient `feedback_diagnostic_logging` pattern).
- Treat generation context as data the user owns: every prompt assembled is logged to `<project>/generation-log/<timestamp>.json` and surfaced in the History inspector tab (§14.5.2).
- Never display "moderation" / "safety" copy. Refusal-detection (per RPClient `feedback_quirk_detectors`) surfaces as a yellow chip on the generation event in History, with no editorial language — just "Model declined to continue. [View what was sent ▸]."
- Use `Scene` / `Chapter` / `Project` / `Bible` / `Entity` as primary nouns. Never `Turn` / `Chat` / `Card` / `Cast` (those are RPClient nouns).


# Loom UI Research — long-form AI fiction tools

> **Status: research landed (2026-05-10).** This document captures the visual + interaction patterns of the gold-standard long-form AI fiction tools, so that [`LOOM_DESIGN_LANGUAGE.md`](LOOM_DESIGN_LANGUAGE.md) §14 can specify Loom's surfaces against concrete prior art rather than first principles. Mirrors the shape of `/Volumes/SSD1/Code/RPClient/V2_PHASE11_UI_RESEARCH.md` (which did the same thing for chat-shaped clients during RPClient's chat-pane redesign).
>
> **Scope.** Long-form AI fiction tools first; non-AI long-form editors second; chat-shaped roleplay tools (already covered for RPClient) only where they show fiction-specific patterns.
>
> **Methodology.** Live MCP capture (Chrome extension navigating + screenshotting actual web UIs) where the domain was permitted; parent-context WebFetch + general-knowledge research where MCP navigation was blocked at the allowlist. Capture date: 2026-05-10. Per-tool tagging makes it explicit which patterns came from a live capture vs documentation review.

---

## A. Scope, methodology, capture inventory

### A.1 Tier-1 references (deep capture)

| Tool | Capture method | Why |
|---|---|---|
| Sudowrite | **Live MCP** (sudowrite.com landing + docs) + prior WebFetch on docs.sudowrite.com | Closest commercial competitor for AI fiction. Web app; product UI surfaces in marketing screenshots and docs. |
| Novelcrafter | **Live MCP** (novelcrafter.com landing + features + Codex) + prior WebFetch | Deeper Codex / prompt-functions grammar than Sudowrite; also web-based. |
| NovelAI | Prior WebFetch + general knowledge (MCP allowlist denied novelai.net) | Story-mode-native; lorebook conventions are the local-model standard. |
| Scrivener | Prior WebFetch + general knowledge (MCP allowlist denied) | The structural gold standard; Binder/Corkboard/Inspector/Compile are canonical. |
| Plottr | Prior WebFetch (MCP allowlist denied) | The 2D Timeline × Plotline grid is the strongest visual outliner. |

### A.2 Tier-2 references (lighter)

| Tool | Capture | What for |
|---|---|---|
| AI Dungeon | Prior WebFetch | Mobile-shaped anti-pattern reference; Story Cards schema cleanly documented. |
| DreamGen | Prior WebFetch | Explicit-fiction-friendly cloud tool; reference for context-tier model. |
| Manuskript | Prior WebFetch + general knowledge | Snowflake-method open-source novel writer. |
| Longform (Obsidian plugin) | Prior WebFetch (README) | Scene-as-markdown-file architecture; Loom inherits. |
| iA Writer / Highland 2 | General knowledge | Composition / focus mode patterns. |

### A.3 What blocked

NovelAI and several other domains were blocked at the Chrome MCP allowlist. Live capture was therefore limited to Sudowrite + Novelcrafter; prior-round WebFetch fills the other tools. **Per-pattern tagging in §B explicitly notes "live capture" vs "prior research."**

---

## B. Per-tool patterns

For each tool: a list of named patterns, each with **what / where / why / verdict** in the V2 research format. Verdicts: `STEAL` (adopt directly), `ADAPT` (adopt with modification), `INVERSE` (do the opposite), `IGNORE` (not applicable).

### B.1 Sudowrite

**Capture: live MCP, 2026-05-10.** Marketing pages + docs. Did not sign in (per user instruction).

**Tier-1 chrome anatomy (from marketing screenshots embedded on sudowrite.com):**

- **Three-pane layout**. Left: Binder-style sidebar with chapter list + Story Bible sub-sections (Story Bible / Braindump / Genre / Style / Synopsis / Worldbuilding / Outline / Characters / Scenes & Draft). Centre: full-width prose editor. Right: contextual generation pane.
- **Top toolbar**: Back · Write · Rewrite · Describe · Brainstorm · (more) · Plug-ins. Generation modes are top-toolbar buttons, NOT a bottom tray.
- **Brand chrome**: warm cream background with subtle grain texture; serif typography for marketing; mostly opaque editor surfaces with rounded corners + shadow lifts.

**B.1.1 — Inline floating action bar on text selection.** **STEAL.** Live capture verified: when prose is selected, a floating capsule toolbar appears with `[Rewrite | Describe | Expand | Visualize]` icons + labels. Capsule sits anchored above the selection. This is the *contextual* generation surface — not always visible. Beats a bottom-tray-always-visible pattern for selection-driven modes (Rewrite/Expand are selection-required).

**B.1.2 — Pink/lavender tinted background for AI-generated prose.** **STEAL (adapted).** Live capture verified: AI output rendering on the right pane uses a distinct pink/lavender background tint, visually segregating AI output from human prose. The user sees what came from where at a glance. Loom's acceptance-state spec ([`LOOM_DESIGN_LANGUAGE.md`](LOOM_DESIGN_LANGUAGE.md) §14.6) should adopt this — *during acceptance only* — and fade to normal on accept (per existing spec).

**B.1.3 — HISTORY panel as a structured list of generation events.** **STEAL.** Live capture verified: a "HISTORY" header sits at top of the AI pane with a clock icon and a star/favorite icon. Each generation is a row showing the generated text, accessible later. Sudowrite's history shows label-level chiclets (what context was sent); Loom's spec already exceeds this by showing full prompt + full response (research §A.5).

**B.1.4 — Story Bible as left-sidebar disclosure.** **ADAPT.** Live capture: the Bible is a sub-section of the left sidebar (under chapters), expandable, with sub-items per category. **Adaptation for Loom**: Loom's Bible inspector is right-side ([`LOOM_DESIGN_LANGUAGE.md`](LOOM_DESIGN_LANGUAGE.md) §14.5.1), not embedded in the sidebar. Reason: chapters and bible serve different cognitive functions — chapter navigation is "where am I" wayfinding; bible is "what about this entity" reference. Right-side inspector keeps both visible without a tab switch. Sudowrite's choice to merge them in the sidebar saves chrome but forces tab switches.

**B.1.5 — Visualize mode: image generation from selection.** **IGNORE for v1.** Not in Loom's scope; image generation is a separate concern. Documented for reference; revisit if image-generation-for-fiction becomes a user request.

**B.1.6 — Generation modes as named buttons in top toolbar.** **INVERSE.** Sudowrite's top toolbar has Write/Rewrite/Describe/Brainstorm/Plug-ins as primary buttons. Loom's spec puts these in a bottom-pinned generation tray ([`LOOM_DESIGN_LANGUAGE.md`](LOOM_DESIGN_LANGUAGE.md) §14.4). Reason: the bottom tray is closer to the cursor (Fitts's Law) and integrates with the History disclosure. Selection-driven modes use the floating action bar (B.1.1); cursor-driven modes (Continue) use the bottom tray.

**B.1.7 — Marketing chrome warmth (cream + serif + grain).** **IGNORE.** Loom is a macOS-native app, not a web tool. Loom's chrome is RPClient-design-language Liquid Glass, not consumer-creative warmth. Warm/serif marketing on a website is fine; in-app, system-native is the right move on macOS.

### B.2 Novelcrafter

**Capture: live MCP, 2026-05-10.** Marketing + features + Codex feature page. Did not sign in.

**Tier-1 chrome anatomy:**

- **Two-pane Codex layout**: left = filter tabs (All / Book / Series with counts) + categorised entity list with avatars. Right = detail view with per-entry tabs (Details / Research / Relations / Mentions / Tracking).
- **Mention-frequency sparkline**: a small horizontal bar above the per-entity detail showing where in the manuscript the entity is mentioned. Data-rich, non-textual, glanceable. Has a numeric label ("18 mentions").
- **Brand chrome**: cleaner / more modern than Sudowrite — cream/white with serif headlines but more sans-serif body, less texture. Black primary buttons (CTA = Start Writing, pill-shape).

**B.2.1 — List-detail two-pane Codex layout.** **STEAL (adapt to right inspector).** Live capture verified. Loom's Bible inspector ([`LOOM_DESIGN_LANGUAGE.md`](LOOM_DESIGN_LANGUAGE.md) §14.5.1) should adopt the list-detail pattern — left half of the inspector shows the entity list with category sections; right half shows the selected entity's details with sub-tabs. This is materially better than a flat Sudowrite-style "all-fields-stacked" Bible page. ⚠️ **Updates the §14.5.1 spec**: the original spec had Bible as a single column with collapsible sections; the list-detail pattern is better. See LOOM_DESIGN_LANGUAGE update.

**B.2.2 — Per-entity tabs (Details / Research / Relations / Mentions / Tracking).** **STEAL with translation.** Live capture verified. Loom's per-entity sub-tabs: `Description / Knowledge ledger / Relationships / Mentions / Notes` (Loom's Knowledge Ledger replaces "Tracking" and "Research"; Mentions stays). **Updates §14.5.1**: previously vague on per-entity sub-structure; now concrete.

**B.2.3 — Mention-frequency sparkline.** **STEAL.** Live capture verified: a small horizontal bar shows where in the manuscript an entity is mentioned, with marker dots at scene/chapter mentions, plus a numeric count ("18 mentions"). **For Loom**: extend this — when the Bible's mention sparkline is hovered or clicked, the editor scrolls to the next/previous mention in the text. Phase 4+ (after mention extraction is wired).

**B.2.4 — Inline cross-entity links + hover-card preview.** **STEAL.** Live capture verified: the Description field uses inline links to other entities (the word "Reichenbach" links to the Reichenbach codex entry); hovering shows a popover preview ("Lore / Baritsu / A form of Japanese wrestling that Sherlock Holmes learned." with `Open / Left / Right` buttons to dock the link target). This is the right pattern for Loom's `@entity` mentions. Hover = preview popover; click-with-modifier = open in inspector; option-click = open in left split. Phase 2.

**B.2.5 — Aliases/Nicknames as comma-separated free-text + AI-assist sparkles.** **ADAPT.** Live capture: alias field rendered as comma-separated value (e.g., "Sherlock, Holmes, Sigerson") with help-tooltip + AI-assist icon. Loom's `Character.aliases: [String]` schema matches; the UI should be a token-field (NSTokenField) per [`LOOM_DESIGN_LANGUAGE.md`](LOOM_DESIGN_LANGUAGE.md) §6 Form fields, not a comma-separated text field. AI-assist sparkles (offer suggested aliases from the prose) is a Phase 4+ feature.

**B.2.6 — Inline floating *formatting* toolbar on selection.** **STEAL (adapted; complementary to AI floating bar).** Live capture: when prose is selected, a floating toolbar shows formatting options (Bold/Italic/Underline/Strikethrough/Highlight/Quote/Heading/List) plus a word-count chip. **For Loom**: combine — the floating selection toolbar shows BOTH formatting buttons AND AI-mode buttons (Sudowrite's pattern, but on the same bar). Visual order: `[Word count] · [Formatting] · | · [Rewrite | Expand | Describe | ...]`. Phase 1 ships formatting; AI buttons land Phase 4 when the modes ship.

**B.2.7 — Highlight markers preserved in prose.** **STEAL.** Live capture: yellow highlights on prose persist across the manuscript ("Used to have a place in Mayfair." highlighted yellow). **For Loom**: support highlighting as a non-AI-related tool — markdown with `==highlighted==` syntax (CommonMark MarkExt) or HTML `<mark>`. Phase 2-3.

**B.2.8 — Marker Timeline (vertical color-coded scene-length strip).** **ADAPT.** Live capture: a thin vertical color-coded bar shows scene lengths in proportion across the manuscript, with hover tooltip ("Chapter 1 - Scene 1 / One month earlier"). **For Loom**: this is a sidebar visualization that complements the Binder. Phase 3+ candidate; the Binder already shows scene names but doesn't visualize length.

**B.2.9 — Sections: in-manuscript alternative versions / notes.** **ADAPT.** Live capture: collapsible "Option 1 / Option 2 / Option 3" sub-blocks within the manuscript, with grip handles for reordering. **For Loom**: this is similar to Snapshots ([`LOOM_RESEARCH.md`](LOOM_RESEARCH.md) Scrivener J1) but inline. Loom's existing Snapshots pattern (Phase 5+ in current plan) keeps versions out-of-band, which is cleaner for long-form work. Don't adopt inline Sections; document as alternative.

**B.2.10 — Focus Mode button.** **STEAL.** Live capture: a single "Focus" button card; toggle goes distraction-free fullscreen. Already in Loom's open questions ([`LOOM_DESIGN_LANGUAGE.md`](LOOM_DESIGN_LANGUAGE.md) §14.11); confirmed worth shipping. Phase 1 candidate if cheap; Phase 2 floor.

**B.2.11 — Customizable Interface (font, line height, paragraph spacing, page width, dyslexia font).** **ADAPT.** Live capture: a granular settings panel for editor typography. **For Loom**: macOS-native uses Dynamic Type for size; Loom inherits this from RPClient (no per-app font scaling override). For paragraph spacing / page width / line height: yes, expose as Settings (Phase 6 polish).

**B.2.12 — Point of View pill picker + Tense toggle + Pen Names.** **STEAL.** Live capture: POV is a multi-pill button ("1st Person / 2nd Person / 3rd Person / 3rd Person Limited / 3rd Person Omniscient"); Tense is a two-pill toggle ("Past / Present"). Both are at project level with per-scene override. **For Loom**: exactly matches the planned POV/tense schema in [`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md) §2. Pill UI for these in Project Settings. Phase 2.

**B.2.13 — Revision History as timestamp list with author.** **STEAL.** Live capture: timestamps with relative names ("September 8th 7:54 PM / Jane Doe"); single-list pattern. Loom's `Snapshot` schema ([`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md) §2) supports this directly. Phase 2-3.

**B.2.14 — Pin panels (split-view).** **STEAL.** Live capture: a "Pin" affordance keeps a panel visible alongside the editor — e.g., chat pinned next to manuscript. **For Loom**: Loom's three-pane is already this pattern; "Pin a specific bible entry next to the editor" is a Phase 4+ enhancement (currently the inspector shows whatever the user last opened).

**B.2.15 — "Romance & NSFW Writing" as marketed genre guide.** **ADAPT.** Live capture: Novelcrafter explicitly markets "Romance & NSFW Writing" with phrases like "every heat level" — confirming that mainstream commercial tools openly target the explicit-fiction segment. **For Loom**: this validates [`LOOM_NSFW.md`](LOOM_NSFW.md) §1's framing — explicit fiction is mainstream, not fringe; tools that pretend otherwise are the outliers. Marketing isn't a Loom concern (no marketing site in v1) but the cultural confirmation is useful.

**B.2.16 — Plan view: card-grid manuscript planner with rich scene metadata (UPDATED 2026-05-10 from user-supplied screenshot).** **STEAL — Phase 3.** Novelcrafter's "Plan" tab (one of four top-level tabs: Plan / Write / Chat / Review) renders the manuscript as nested cards: Acts → Chapters → Scenes. Each scene card shows: title · word count · drag-handle · summary text · status pill ("Draft", "Edited") · subplot tag · Codex tags (entities mentioned: characters, locations, factions) · label. Filter strip at top (search scenes); view-mode toggle (Grid / Matrix / Outline). Chapters render in a horizontal row when ≥3 in an Act; scenes stack vertically inside each chapter card.

**Concrete properties of the layout** (from the screenshot):
- **Card density**: scene cards are ~280pt wide; one column per chapter; chapters tile horizontally inside an Act group.
- **Card chrome**: thin border, subtle background, 8pt corner radius; drag-handle dot-grid on the leading edge.
- **Metadata vocabulary**: each card surfaces the canonical metadata (status, subplot, entity tags) as inline pills — same density posture as the Bible inspector's per-entity sub-tabs (B.2.2).
- **View-mode toggle** at top: Grid (the screenshot's mode), Matrix (Plottr-shaped 2D timeline-style — see B.5.1), Outline (linear table of all scenes — see B.4.7).

**For Loom**: this is the **Phase 3 Corkboard** ([`LOOM_PLAN.md`](LOOM_PLAN.md) L3). Specifics from this capture not in the existing spec:
1. The Grid / Matrix / Outline toggle as a unified affordance (vs Loom's current implicit "Corkboard view as separate tab"). Three views, one toggle, one underlying data source. Borrow.
2. The richness of per-card metadata pills — Loom's `Scene` schema ([`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md) §2) already has all these fields (status, conflict/outcome, summary, POV/location); the card layout is the projection.
3. The "Plan" tab as a **distinct app mode** — Novelcrafter has Plan / Write / Chat / Review as **orthogonal modes**. Loom's three-pane workspace (sidebar + editor + inspector) is closer to a single-mode IDE. Loom's design-language §14.2 has the workspace; Phase 3 Corkboard adds a **second mode** the user toggles into. Decision deferred to Phase 3: tab vs separate window vs editor-pane-replace.

Implementation note (AppKit): NSCollectionView with custom `NSCollectionViewItem` cells for scene cards; NSStackView (orientation: horizontal) for chapter rows inside Act groups; native drag-rearrange via NSCollectionView pasteboard support. Same pattern Scrivener uses for its Corkboard — Phase 3 will reuse the binder data source.

### B.3 NovelAI

**Capture: prior-round WebFetch + general knowledge (MCP denied novelai.net).** Patterns from documentation read in Round 1-3.

**B.3.1 — VIP sidebar for Memory + Author's Note.** **STEAL.** Memory and Author's Note are pinned in the right sidebar, can't be deleted, always-active ([`LOOM_RESEARCH.md`](LOOM_RESEARCH.md) §C.2). **For Loom**: matches the planned History/Notes inspector tab pattern; Memory and A/N already specified as project-level fields ([`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md) §1).

**B.3.2 — Lorebook entry editor with placement controls.** **STEAL.** Per-entry: Activation Keys (regex-supporting), Search Range (≤10000 chars), Key-Relative Insertion (signed newline offset), Insertion Order (priority), Token Budget, Prefix/Suffix, Always On, Subcontext (per-category packing) ([`LOOM_RESEARCH.md`](LOOM_RESEARCH.md) §S.4). **For Loom**: schema specified; UI lands Phase 2 alongside the Bible inspector.

**B.3.3 — Context Viewer: color-coded reveal of assembled prompt.** **STEAL (already in Loom design).** ([`LOOM_RESEARCH.md`](LOOM_RESEARCH.md) §S.4 / §A2.8.) Loom's History inspector ([`LOOM_DESIGN_LANGUAGE.md`](LOOM_DESIGN_LANGUAGE.md) §14.5.2) already supersedes this — Loom shows the full prompt + full response per generation, not just labels.

**B.3.4 — ATTG system-prompt header.** **STEAL.** `[ Author; Title; Tags; Genre ][ S: 2-4 ]` format ([`LOOM_RESEARCH.md`](LOOM_RESEARCH.md) §S.2). Adopted in [`LOOM_FANFIC.md`](LOOM_FANFIC.md) §3.3.

### B.4 Scrivener

**Capture: prior-round WebFetch + general knowledge (MCP denied L&L domain).** Patterns canonical and stable.

**B.4.1 — Binder (left sidebar hierarchical project tree).** **STEAL.** Already in [`LOOM_DESIGN_LANGUAGE.md`](LOOM_DESIGN_LANGUAGE.md) §14.3.

**B.4.2 — Corkboard (drag-rearrangeable index cards).** **STEAL.** Phase 3+ candidate. Card density: Scrivener uses ~3-up grid at default zoom. Loom's Corkboard view (Phase 3 in [`LOOM_PLAN.md`](LOOM_PLAN.md)) should target the same density posture.

**B.4.3 — Inspector pane (synopsis / notes / keywords / metadata per document).** **STEAL.** Already in Loom's three-pane spec.

**B.4.4 — Snapshots (per-document version snapshots).** **STEAL.** Schema in [`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md) §2 already specifies this.

**B.4.5 — Composition / Focus Mode.** **STEAL.** Confirmed Phase 1-2.

**B.4.6 — Compile (custom export pipeline).** **ADAPT.** Phase 6 polish; Loom's Markdown-first export is simpler than Scrivener's Compile but should support multi-step workflows for Phase 6+ deliverables.

**B.4.7 — Outliner view (table of all documents with metadata columns).** **STEAL.** Phase 3-4 candidate. Sort by status / target word count / POV / location. Loom's `Scene` schema has the metadata; the table view exposes it.

### B.5 Plottr

**Capture: prior-round WebFetch (MCP denied plottr.com).**

**B.5.1 — 2D Timeline × Plotline grid.** **STEAL.** Each row is a plotline (color-coded); columns are chapters/scenes; cells are scene cards drag-rearrangeable. Loom Phase 4+ candidate per [`LOOM_PLAN.md`](LOOM_PLAN.md). This is unmatched in AI tools.

**B.5.2 — Outline view auto-generated from Timeline.** **STEAL.** When Phase 4+ ships the Timeline, an Outline projection that lists scenes in order, filterable by plotline, is the natural complement. Free given the data shape.

**B.5.3 — 40+ pre-built outline templates (Snowflake, Save the Cat, Hero's Journey, etc.).** **ADAPT.** Loom can ship a smaller bundled set (5-10 canonical templates) at Phase 3-4; user adds custom.

### B.6 AI Dungeon

**Capture: prior-round WebFetch (MCP denied aidungeon.com).** Mobile-first; mostly anti-pattern reference for desktop.

**B.6.1 — Story Cards (Type / Name / Entry / Triggers / Notes).** **STEAL.** Lorebook semantic; data shape already in [`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md) §3.6.

**B.6.2 — Memory Bank (auto-summary every N actions, embedded, retrieved by cosine).** **STEAL.** Per [`LOOM_MEMORY.md`](LOOM_MEMORY.md) §A2.1.

**B.6.3 — Bracketed `[Author's Note]` injection at end.** **STEAL.** Already in [`LOOM_NSFW.md`](LOOM_NSFW.md) §2.4.

**B.6.4 — Eviction priority published.** **STEAL.** Cut order (Story Summary first → AI Instructions → Plot Essentials → Author's Note last). [`LOOM_MEMORY.md`](LOOM_MEMORY.md) §A2.7 already adopts.

**B.6.5 — Mobile chat-bubble UI for fiction.** **INVERSE.** Loom is desktop, prose-shaped, no chat bubbles. AI Dungeon's mobile-first UX bleeds in awkward ways even on desktop (small typography, overstacked controls). Don't.

### B.7 DreamGen

**Capture: prior-round WebFetch.**

**B.7.1 — Story Writing + Role-Play as separate modes.** **ADAPT.** Loom's project kind is `originalFiction / fanfic` rather than story/role-play. The two-mode pattern is good UX (clear intent at project creation); Loom's project-kind picker on new-project flow already does this.

**B.7.2 — Story "Steering" (mid-generation direction).** **ADAPT.** Loom's Author's Note + per-generation override covers this. DreamGen's marketing emphasises it as a feature; Loom has it as the steering primitive.

**B.7.3 — Scenario Generator (auto-create scenarios from prompt).** **ADAPT.** Loom's Brainstorm mode covers this for original fiction; for fanfic, the Phase 5.c fandom-template scaffolding is the equivalent.

**B.7.4 — "We don't filter your stories" as marketed posture.** **STEAL (mirror).** [`LOOM_NSFW.md`](LOOM_NSFW.md) §1 already takes this posture.

### B.8 Longform (Obsidian plugin)

**Capture: prior-round WebFetch (README).**

**B.8.1 — `longform: true` frontmatter identifies projects.** **STEAL.** Loom's on-disk format ([`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md) §7.1) doesn't quite mirror this — Loom uses `project.json` instead of frontmatter on a per-vault notes search — but the *scene-as-markdown-file with YAML frontmatter* pattern is identical.

**B.8.2 — Index file with `scenes:` list defines order.** **ADAPT.** Loom's `manuscript.partIds` / `Part.chapterIds` / `Chapter.sceneIds` is the equivalent; doesn't live in YAML frontmatter (lives in `project.json`) but is the same idea.

**B.8.3 — Plugin never alters scene contents (only the index).** **STEAL.** Loom's round-trip safety guarantee matches this verbatim ([`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md) §7.1).

### B.9 Manuskript / yWriter / bibisco

**Capture: prior-round WebFetch + general knowledge.**

**B.9.1 — yWriter per-scene metadata (POV / time / location / conflict / outcome).** **STEAL.** Already in [`LOOM_DATA_MODEL.md`](LOOM_DATA_MODEL.md) §2 (`Scene.conflict`, `outcome`, etc.).

**B.9.2 — Manuskript Snowflake-method incremental expansion (1-paragraph → full novel).** **ADAPT.** Loom's approach is similar but inverted: Loom doesn't enforce a Snowflake structure; user chooses scaffold-first or sketch-and-grow per [`LOOM_RESEARCH.md`](LOOM_RESEARCH.md) §O.3. Manuskript's storyboard with chapter list + scene fields IS the corkboard pattern; nothing new beyond Scrivener.

**B.9.3 — bibisco character-lore prompts.** **ADAPT.** Loom's per-field AI-assist (Sudowrite Phase 9 §5.4 carry-over) covers this — when adding a character, offer prompted-question affordances ("How would they describe their childhood?") that generate prose for the field. Phase 4 candidate.

### B.10 iA Writer / Highland 2

**Capture: general knowledge.**

**B.10.1 — Focus mode (current paragraph emphasised; rest dimmed).** **STEAL.** Phase 1-2 candidate.

**B.10.2 — Syntax highlighting for parts of speech.** **IGNORE for v1.** Niche feature; iA Writer's specific colour-marking adjectives/nouns/verbs is a craft tool — not in scope for Loom v1, but could be a Phase 6+ polish.

**B.10.3 — Highland 2 Bin (drag-drop reorderable scene cards).** **STEAL via Corkboard.** Same pattern as Scrivener's Corkboard.

---

## C. Cross-app pattern table

The §3.3 RPClient research format: cross-app questions answered with cited evidence. Specific to AI fiction tools.

### C.1 — How are generation modes surfaced?

| Tool | Pattern |
|---|---|
| Sudowrite | Top toolbar buttons + selection floating bar |
| Novelcrafter | Right-pane chat; bracketed `[brackets]` instructions inline |
| NovelAI | Sidebar buttons + retry/swipe controls below text |
| AI Dungeon | Bottom action bar (mobile-first) |
| Loom (decided) | Bottom-pinned generation tray + selection floating bar |

**Synthesis**: top-toolbar (Sudowrite) loses Fitts's-Law to a bottom tray near the cursor; the selection floating bar is universally adopted; chat-shaped (Novelcrafter) breaks fiction posture. Loom's hybrid (bottom tray + floating selection bar) is the best of these.

### C.2 — How is AI-generated prose visually distinguished?

| Tool | Pattern |
|---|---|
| Sudowrite | **Pink/lavender tint** on the right-pane preview during review |
| Novelcrafter | (chat-shaped review → no inline distinction in editor) |
| NovelAI | (no in-line tint; differentiation via cursor position only) |
| AI Dungeon | (blue tint historically for AI text) |
| Loom (decided) | Accent rule + Accept/Reject overlay during acceptance state; **no permanent distinction** after accept |

**Synthesis**: the *temporary* distinction is the right pattern; permanent badges are noise. Sudowrite's tint is more subtle than AI Dungeon's blue background but still visible. Loom's accent-rule-during-acceptance approach is restrained.

### C.3 — How is the Bible / Codex / Memory laid out?

| Tool | Pattern |
|---|---|
| Sudowrite | Left-sidebar disclosure with sub-sections (under chapter list) |
| Novelcrafter | Dedicated Codex page with **list-detail two-pane** + per-entry tabs |
| NovelAI | Right-sidebar VIP slots (Memory / A/N) + Lorebook in modal |
| Scrivener | Inspector pane (right side); one document at a time |
| Loom (decided) | **Right-side inspector** with Bible tab; **list-detail two-pane internally** within the Bible tab (per Novelcrafter B.2.1) |

**Synthesis**: the list-detail two-pane (Novelcrafter) is materially better than flat-stacked-fields (Sudowrite) for exploring a complex bible. Right-side inspector (Loom + Scrivener) keeps both manuscript and bible visible simultaneously, vs left-sidebar Bible (Sudowrite) which forces tab switching.

### C.4 — How are entity references made and previewed?

| Tool | Pattern |
|---|---|
| Sudowrite | Saliency engine auto-detects names; opaque |
| Novelcrafter | **Inline links + hover-card preview** in description fields; explicit per-entry "Always Include" toggle |
| NovelAI | Activation keys (regex/substring); in-prose entity mentions don't link visibly |
| Scrivener | (no AI; manual cross-references via document links) |
| Loom (decided) | `@entity` typed by user → inline link, hover preview popover, click-with-modifier opens in inspector. Auto-detection at bibles' `aliases` field. |

**Synthesis**: Novelcrafter's hover-card is the cleanest UX. Loom adopts.

### C.5 — How is the project tree / navigation structured?

| Tool | Pattern |
|---|---|
| Sudowrite | Flat chapter list with Story Bible underneath |
| Novelcrafter | Plan view (chapters/scenes hierarchy) separate from Codex |
| NovelAI | Single-document storefront with tab system for stories |
| Scrivener | **Binder** — full hierarchical tree (Manuscript / Research / Trash + folders + documents) |
| Plottr | 2D Timeline × Plotline grid + auto-generated Outline |
| Loom (decided) | Scrivener Binder pattern: hierarchical tree (Manuscript / References / Trash + Parts → Chapters → Scenes) per [`LOOM_DESIGN_LANGUAGE.md`](LOOM_DESIGN_LANGUAGE.md) §14.3 |

**Synthesis**: Scrivener Binder is the canonical pattern; everyone else is a degraded version. Loom adopts. Plottr's 2D grid is *complementary* (different cognitive task — see plotline structure vs navigate manuscript) and lands Phase 4+ as a dedicated view.

### C.6 — How is generation-context transparency surfaced?

| Tool | Pattern |
|---|---|
| Sudowrite | "History chiclets" (labels of what context was sent; not full content) |
| Novelcrafter | Full template visible to user (user *writes* the template); transparent by design |
| NovelAI | **Context Viewer** (color-coded reveal of assembled prompt) |
| AI Dungeon | "What goes into the Context" docs page; not in-product |
| DreamGen | (limited; not surfaced as feature) |
| Loom (decided) | History inspector tab shows **full prompt + full response** per generation; chiclets break down sources; full text expandable. |

**Synthesis**: NovelAI Context Viewer is closest existing pattern; Loom exceeds it by showing full text. This is a meaningful differentiator.

### C.7 — How is structural metadata (POV, tense, status) captured per scene?

| Tool | Pattern |
|---|---|
| Sudowrite | Project-level POV/tense in Style; not per-scene |
| Novelcrafter | **Project-level POV/tense pill picker; per-scene override; status colored** |
| NovelAI | (story-mode is monolithic; no per-scene metadata) |
| Scrivener | Per-document Status / Label / Custom Metadata fields |
| yWriter | Per-scene POV / Conflict / Outcome / Time / Location |
| Loom (decided) | yWriter per-scene metadata + Novelcrafter pill picker for project-level defaults; per-scene override |

### C.8 — How is "Focus mode" / distraction-free implemented?

| Tool | Pattern |
|---|---|
| Sudowrite | (no mode; just fullscreen the browser) |
| Novelcrafter | Single "Focus" button → fullscreen distraction-free |
| iA Writer | Current-paragraph emphasised; rest dimmed |
| Scrivener | Composition mode with custom background |
| Loom (decided) | Focus mode toggle (`⌘⇧F` or similar): hide sidebar + inspector; current-paragraph emphasis (iA Writer pattern) optional |

### C.9 — How is multi-output / candidate display rendered?

| Tool | Pattern |
|---|---|
| Sudowrite | Generates 2-3 options in the right-pane History; user picks |
| Novelcrafter | Single output per beat; user re-rolls if dissatisfied |
| NovelAI | Single output; "retry" button regenerates |
| ChatGPT/Claude | `◀ 1/3 ▶` pager on the response |
| Loom (decided) | `◀ 1/3 ▶` pager pill below inserted block (matches RPClient §4.0.d variants pill) when multi-output is present; capsule pill always-visible when count > 1 |

### C.10 — How is the empty-state of a brand-new project rendered?

| Tool | Pattern |
|---|---|
| Sudowrite | Fresh project → Story Bible Braindump page (forces structure) |
| Novelcrafter | Fresh project → Plan view with "Add chapter" |
| NovelAI | Blank text editor |
| Scrivener | Default "Untitled" document in Binder |
| Loom (decided) | Per [`LOOM_DESIGN_LANGUAGE.md`](LOOM_DESIGN_LANGUAGE.md) §14.7: 96pt book icon + project title + "Create the first scene" button. Fanfic-mode adds a one-shot "Pick fandom" step before first scene per [`LOOM_FANFIC.md`](LOOM_FANFIC.md) §8. |

---

## D. Synthesis — directional recommendations for Loom

Bound to specific updates of [`LOOM_DESIGN_LANGUAGE.md`](LOOM_DESIGN_LANGUAGE.md) §14, opinionated calls.

### D.1 Bible inspector layout (§14.5.1)

**Current spec**: collapsible disclosure sections (Characters / Settings / Objects / etc.) — flat list within each.

**Updated spec from B.2.1 + B.2.2 (Novelcrafter)**:

- **List-detail two-pane** within the Bible tab. Top half (or left, depending on aspect) = entity list with category sections + filter tabs (All / Characters / Settings / Objects / Factions). Bottom half (or right) = selected entity detail with sub-tabs.
- **Per-entity sub-tabs**: `Description / Knowledge ledger / Relationships / Mentions / Notes`.
- **Mention-frequency sparkline** above the entity name in the detail pane: small horizontal bar marking where in the manuscript the entity is mentioned, with `N mentions` label. Click a marker → editor jumps to that scene.

### D.2 Inline floating selection toolbar (§14.4 + new)

**Current spec**: bottom-pinned generation tray.

**Updated spec**:

- **Bottom-pinned tray remains** for cursor-driven modes (Continue) — visible always, position-stable.
- **Inline floating selection toolbar** (NEW) appears when prose is selected, anchored above the selection. Contains:
  - Word-count chip (`12 words`, like Novelcrafter B.2.6).
  - Formatting buttons (Bold/Italic/Underline/Strikethrough/Highlight/Quote/Heading/List).
  - Separator.
  - Selection-driven AI modes: `Rewrite | Expand | Describe | (more)`.
- 120ms fade-in on selection; fade-out on selection clear.

This is a **Phase 1 Sudowrite-pattern adoption** for the formatting half; AI half lands when the modes ship (Phase 4).

### D.3 Inline cross-entity links + hover preview (new)

**New spec from B.2.4 (Novelcrafter)**:

When the user types `@<entity>` in prose:

1. Autocomplete popover suggests matching entities by name + alias.
2. On selection → text inserts the entity's display name, with an invisible link to the entity ID stored in the markdown as `[Display Name](#entity/<uuid>)` (HTML-friendly, round-trippable).
3. Hover over a linked entity in the editor → popover preview shows the entity's name + role + first 200 chars of description + `Open / Open in inspector / Open in left split` buttons.

Phase 2 (after Bible inspector is wired).

### D.4 Acceptance state — refined visual

**Current spec ([`LOOM_DESIGN_LANGUAGE.md`](LOOM_DESIGN_LANGUAGE.md) §14.6)**: 6pt accent rule on leading edge during acceptance.

**Refinement from B.1.2 (Sudowrite)**:

- During acceptance, the inserted block's *background* gets a very subtle accent tint (`controlAccentColor` at ~6% alpha) in addition to the leading rule. Fades to none on Accept.
- The combination (rule + tint) makes AI prose unmistakable during the review window without being permanent.

### D.5 Bible per-entity detail header — sparkline + tabs (new)

For each entity opened in the Bible inspector:

```
┌────────────────────────────────────────────────────────────┐
│ [Avatar 32pt]  Sherlock Holmes                ⋯ overflow  │
│                Protagonist                                  │
│                ━━━─────━━━━━─━━━━━━━━━━─────  18 mentions │
│                                                             │
│  Description · Knowledge · Relationships · Mentions · Notes│
│                                                             │
│  [active tab content]                                       │
│                                                             │
└────────────────────────────────────────────────────────────┘
```

- 32pt avatar (default initial-circle if no portrait).
- Name (`title2` / 17pt regular).
- Role chip (`caption1` / 10pt secondary).
- Mention sparkline below role: thin horizontal bar with marker dots; numeric count to the right.
- Sub-tab strip below sparkline.

### D.6 Project-level pill pickers (POV, Tense, Direction)

From B.2.12 (Novelcrafter) + Loom's existing `WritingDirection` schema:

In the Project Settings inspector area:

```
POV: [ 1st · 2nd · 3rd · 3rd-Limited · 3rd-Omniscient ]
Tense: [ Past · Present ]
Direction: [ Literary · Mainstream · Romance · Erotica · Porn ]
Vocabulary register: [ Clinical · Literary · Earthy · Crude · Mixed ]
Explicitness: [ Fade-to-Black · Suggestive · On-Screen · Graphic · Extreme ]
```

Pill segments. Selected pill highlighted with `controlAccentColor`. Per [`LOOM_NSFW.md`](LOOM_NSFW.md) §3.1 schema.

### D.7 Focus mode confirmed Phase 1-2

From B.2.10 (Novelcrafter) + B.4.5 (Scrivener) + B.10.1 (iA Writer): every serious tool has this; Loom should ship.

Implementation: a single `⌘⇧F` keybind toggles a mode where:
- Sidebar collapses
- Inspector collapses
- Toolbar fades to a thin auto-hiding strip
- Editor expands to fill available width (still capped at 720pt)
- Optional: current-paragraph emphasis (others dim to `tertiaryLabelColor`) — preference-controlled

### D.8 Marker timeline as Binder enhancement (Phase 3+)

From B.2.8 (Novelcrafter): a thin vertical strip beside the Binder showing scene-length proportions, color-coded by some metadata (POV character? status?). Hover reveals scene title.

Loom's Binder ([`LOOM_DESIGN_LANGUAGE.md`](LOOM_DESIGN_LANGUAGE.md) §14.3) doesn't have this; add as a Phase 3+ option (toggle in Settings: "Show length timeline beside Binder").

### D.9 What Loom does that nobody else does (already in plan)

Cross-checked against the captures: Loom's **History tab showing full prompt + full response** still has no equivalent in the surveyed tools — Sudowrite's chiclets show labels; NovelAI's Context Viewer shows assembled text but not the response side. Loom's transparency contract is the strongest in the space.

Loom's **knowledge-ledger-per-scene-per-character** ([`LOOM_STORY_BIBLE.md`](LOOM_STORY_BIBLE.md) §3) has no UI prior art — every tool tracks character *attributes* but not *what the character knows by scene N*. Loom is original here.

Loom's **Writing Direction primitive** ([`LOOM_NSFW.md`](LOOM_NSFW.md) §3.1) has no UI prior art — Novelcrafter's "every heat level" marketing is direction-as-a-tag at most; Loom's structured kind/register/explicitnessLevel/themes/pacing/FTBPolicy is novel.

---

## E. Open questions

1. **NovelAI Context Viewer exact layout** — couldn't capture live (MCP allowlist denied). Concept absorbed; specific layout details (tab structure, color scheme, hover affordances) need a future capture if a refinement pass is wanted.
2. **Plottr Timeline interaction details** — drag-snap behaviour, zoom levels, plotline width, scene-card density. Couldn't capture; reuse general visual-outliner knowledge for Phase 4+ design.
3. **Scrivener Composition Mode background customisation** — not adopted by Loom (Loom uses the system-native Liquid Glass posture); flagged here in case a future Settings-tab adds custom backgrounds.
4. **Sudowrite Canvas exact UX** — visual outline / character-relationship cards-and-boxes. Captured at a high level (cards + drag-drop); detailed interaction patterns for Phase 4+ design need either a paid-trial capture or the user demonstrating it.
5. **Inline `==highlight==` round-trip safety** through markdown export. Phase 2-3 implementation question.

---

## F. Citations

Live-captured sources (Chrome MCP, 2026-05-10):

- Sudowrite landing — `https://sudowrite.com/`
- Sudowrite docs Story Bible — `https://docs.sudowrite.com/using-sudowrite/1ow1qkGqof9rtcyGnrWUBS/what-is-story-bible/jmWepHcQdJetNrE991fjJC`
- Novelcrafter landing — `https://www.novelcrafter.com/`
- Novelcrafter Features — `https://www.novelcrafter.com/features`
- Novelcrafter Codex feature — `https://www.novelcrafter.com/features/codex`

Prior-research-derived sources (cited under their `[*]` IDs in [`LOOM_RESEARCH.md`](LOOM_RESEARCH.md)):

- NovelAI: §C, §S.2, §S.4
- Scrivener: §J.1, §J.2
- Plottr: §E
- AI Dungeon: §F, §S.3, §S.7
- DreamGen: §S.12
- Longform: §S.13
- yWriter / Manuskript / bibisco: §S.14
- iA Writer / Highland 2: §J.3

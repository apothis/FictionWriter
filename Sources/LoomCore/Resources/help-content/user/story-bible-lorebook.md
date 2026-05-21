# Story Bible — Lorebook entries

The Lorebook is your bible's free-form layer — snippets of text that get threaded into the prompt under conditions you control. Characters, Settings, and Objects (covered in the previous section) handle named, structured entities; Lorebook entries are for the things that don't fit that shape: worldbuilding rules, magic-system mechanics, faction histories, named events, ongoing power dynamics, language quirks, anything that's "context the model should have when X is in play."

The convention is borrowed verbatim from NovelAI / KoboldAI / SillyTavern — if you've used any of those tools' lorebook (or "World Info") feature, Loom's shape will feel familiar. Edit in the **Bible Workspace** (**⌘⇧B**), Lorebook tab.

## The minimum viable entry

To put a lorebook entry to work, you need:

- A **name** — for your own organisation. Not sent to the model.
- A **content** body — the actual text that gets injected. Write it as something the model can read straight: "The Vellanic priesthood forbids speaking the names of the dead aloud, even in private…"
- An **activation mode** + the trigger that goes with it.

That's it. Everything else has a sensible default.

## Activation modes

Each entry activates one of three ways:

| Mode | When it injects |
|---|---|
| **Constant** | Every generation, always (subject to the **enabled** toggle). Use for: foundational worldbuilding the model should always know — the setting's physics, the protagonist's curse, the central conflict's stakes. |
| **Keyed** | Only when one of the entry's **keys** appears in your recent prose. Use for: everything else. The lorebook gets large fast; keyed entries keep token usage honest. |
| **Vectorised** | Reserved for a future semantic-similarity activator. **Not active today** — entries marked vectorised behave as if disabled. Stick with constant or keyed. |

Most lorebook entries should be keyed. Constant gets expensive in long projects.

## How keys work

A keyed entry's **keys** field is a list of trigger terms. The activator scans your recent prose (by default the last ~3 scenes) for **whole-word** matches against each term, case-insensitively. Hit any one → entry activates.

Examples:

- An entry about the Vellanic priesthood with keys `Vellanic`, `priesthood`, `priest`, `temple` will activate whenever the prose mentions any of those words.
- A character-specific entry can include nicknames in keys so it triggers regardless of which name the prose uses.

**Whole-word means whole-word.** A key of `temple` matches "temple" but not "contemplate." That's deliberate — substring matching produced too many false-positive triggers in the lorebook lineage Loom borrows from.

### Secondary keys

For more precise triggering, an entry can also carry **secondary keys**. When secondary keys are set, the entry activates only if **both** at least one primary key **and** at least one secondary key appear in the recent prose.

Use this when a generic key would over-trigger. An entry about "what happens at the village festival" might use primary key `festival` and secondary keys `Vellanic`, `village` — only firing when the prose is specifically in the village's festival, not any random festival the protagonist's mind wanders to.

If secondary keys are empty, the primary keys alone suffice.

## Power-user fields

Once you have the basics, the Bible Workspace's lorebook editor exposes the rest of the NovelAI / SillyTavern field set:

| Field | What it does |
|---|---|
| **Enabled** | Master on/off. Disabled entries never activate, regardless of keys. Useful for parking an entry you don't want to delete. |
| **Priority** | An integer; higher-priority entries are kept first when the token budget squeezes. Default 0. |
| **Position mode** | Where the entry lands in the prompt: **Top** (above-cache, near the project memory) / **Bottom** (with the recent-prose tail, strongest steering) / **Depth-N** (a configurable number of lines from the cursor, the Author's-Note slot). |
| **Depth** | How many lines back from the cursor (only relevant when position mode is Depth-N). |
| **Max recent scenes scanned** | How many scenes' worth of prose the activator inspects for key matches. Default 3 — a recent-history window, not the whole manuscript. |
| **Activate from / until scene** | Optional scene-range gates. "Activate from chapter 4 onward" lets you write reveal-lore that can't leak into earlier scenes. |
| **Group + weight + sticky** | Used by Roll Outcome. See below. |

Most users will never touch most of these. They're here for the cases where they're needed.

## Groups, weights, and Roll Outcome

The **group** / **weight** / **sticky** fields turn entries into a weighted-random outcome bucket — the Sphiratrioth pattern from the heavy-NSFW SillyTavern community, re-implemented in Loom.

The pattern:

1. Author several lorebook entries that share a **group** label (e.g. `confrontation_outcome`). Each entry describes one possible outcome of a recurring narrative beat.
2. Assign each a **weight** (1–100). Higher weight = more likely to be rolled.
3. At a decision point in your writing, choose **Bible → Roll Outcome…** Loom shows the available groups; pick one. Loom rolls weighted-random and seeds the rolled entry's content into the tray's **per-call instruction** field for your next Continue.
4. You fire Continue. The rolled outcome biases the generation toward that direction without locking the model rigidly.

A **sticky** entry continues to apply across scene-shifts once chosen — useful when you want a rolled mood / dynamic / scenario to persist for several generations rather than getting one beat and resetting.

The Sphiratrioth lorebook pack (**Bible → Install Sphiratrioth Lorebook Pack**) drops in a curated set of these for heavy-NSFW projects — anti-positive-bias instructions, weighted outcome buckets, sticky-scenario entries. See **Sphiratrioth pack + power-user resources** in the Reference half.

## Where in the prompt entries land

For a given generation, the lorebook activator runs against the recent prose. Active entries are split across two prompt layers:

- **lorebookEntry** — explicitly-pinned entries (currently entries whose `positionMode = .top` cluster up above-cache; others land in the per-mode position).
- **bibleKeyed** — re-uses the same layer that carries keyed Character / Setting / Object entities.

The actual rendered contents of each layer for any past generation are inspectable in the **▸ History** disclosure of the editor tray.

For the assembled-prompt architecture (full layer ordering, eviction rules), see **Generation pipeline** in the Technical Reference book.

## When to use Lorebook vs Character/Setting/Object

Use a **Character / Setting / Object entity** when the thing has an identity — it's a person, a place, an artefact, and your prose will name it. The structured fields (description, voice, sensoryNotes, significance) are tuned for those shapes.

Use a **Lorebook entry** when the thing is a *rule, fact, or shared context* without an obvious entity owner — a magic-system constraint, a faction's history, a cultural taboo, an in-world named event. Or when you want activation behaviour that's more flexible than the binary constant/keyed on entities (groups + weights + scene-range gating live only on lorebook entries).

There's no rule against using both — sometimes a place is both a Setting (because the prose names it) and the trigger for a Lorebook entry that describes the politics of who controls it.

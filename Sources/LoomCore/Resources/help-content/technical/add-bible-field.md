# How to add: a new Bible entity field

A new field on a Bible entity (Character / Setting / Object / Lorebook / Dynamic) crosses the AppKit↔WKWebView boundary, so it touches more layers than a pure-Swift change. This is the worked path, using **a new field on `Character`** as the example. Read **UI architecture** first for the snapshot/intent bridge.

There's **no codegen** — the Swift Codable shapes and their TypeScript mirrors are maintained by hand. The discipline is: change every layer in the chain, and lean on the forward-load + partial-patch conventions so nothing breaks.

## The chain

A character field flows through six layers:

```
Character (model + persistence)
  → CharacterPatch (JS→Swift mutation)        ← apply() reducer
  → SnapshotCharacter (Swift→JS projection)
  → types.ts / bridge.ts (TS mirrors)
  → React editor (form control + patch emit)
  → PromptBuilder.formatBibleEntries (if injected)
```

## 1. The model + persistence

`Models/Character.swift` — add the stored property, the `init` parameter (with a default), **and the `decodeIfPresent` line** in `init(from:)`:

```swift
public var motivationNote: String          // new field

// in init(...):  motivationNote: String = "",
// in init(from:):
self.motivationNote = try c.decodeIfPresent(String.self, forKey: .motivationNote) ?? ""
```

The `decodeIfPresent` + default is non-negotiable — it's what lets an existing `project.json` (written before the field existed) load cleanly. **Pin a forward-load test** (old JSON decodes → field is the default) before moving on.

## 2. The patch (JS → Swift mutation)

`Models/CharacterPatch.swift`. Patches are **partial** — every field is `Optional`, and absent means "no change." Add the optional field and its line in `apply(to:)`:

```swift
public var motivationNote: String?          // optional — absent = unchanged

// in apply(to:):
if let v = motivationNote { c.motivationNote = v }
```

`apply(to:)` is the reducer: it takes the live `Character`, overlays only the patch's present fields, returns the updated character. The React side sends a `CharacterPatch` with *just the changed field* set; everything else is nil and left alone.

## 3. The snapshot projection (Swift → JS)

`Models/BibleWorkspaceSnapshot.swift` → `SnapshotCharacter`. This is a **projection** — what the webview needs, in a JS-friendly shape (e.g. `knownFactsBySceneId` is re-keyed from `[UUID: …]` to string-keyed for JSON-object form). Add the field + map it in `init(from character:)`:

```swift
public var motivationNote: String

// in init(from character:):
self.motivationNote = character.motivationNote
```

The snapshot is **not** the source of truth — it's a read-only view the React side renders. The source of truth is the `Character` model.

## 4. The TypeScript mirrors

`web/bible-workspace/src/types.ts` (the snapshot projection) and `bridge.ts` (the patch shape) — add the field to both, matching the JSON key names exactly. There's no codegen; a mismatch here is a silent "field doesn't show up / doesn't save." This is the step most likely to be forgotten.

## 5. The React editor

The character editor view (under `web/bible-workspace/src/views/`) — add the form control bound to the snapshot field. On change, emit a `CharacterPatch` with **only this field set**, debounced, via the bridge (`webkit.messageHandlers.loom.postMessage({ kind: "patchCharacter", … })`). Follow an existing field's wiring — the controlled-input + debounce pattern is established (e.g. the `NumericField` helper for numeric fields).

## 6. Prompt injection (if the model should see it)

If the field should reach the writer, `Generation/PromptBuilder.swift` → `formatBibleEntries` renders the entity block — add the field to the rendered text. If it's conditional (like `intimateAnatomy`, which only injects when the scene is depicted + the character is undressed), gate it the way `AnatomyGate` does rather than always emitting.

If the field is author-metadata only (a note for the user, not the model), skip this step — not every field is injected.

## 7. Tests (first, per TDD)

The pure-data layers all have direct coverage:

- **Forward-load** — old `Character` JSON without the field decodes, field is the default. (The load-bearing one.)
- **Patch round-trip** — `CharacterPatch` Codable encode/decode; `apply(to:)` sets only the present field, leaves others.
- **Snapshot projection** — `SnapshotCharacter(from:)` carries the field.
- **Prompt injection** (if step 6) — `formatBibleEntries` includes the field in the entity block.

The TS side has no Swift-side test; verify it live (rebuild, open the Bible Workspace, edit the field, confirm it persists + round-trips through a close/reopen).

## The two conventions that make this safe

- **Forward-load (`decodeIfPresent` + default)** — adding a field never breaks an existing project file. Every field-addition test pins this.
- **Partial patch (`Optional` + `apply` reducer)** — the React side sends only what changed; the reducer overlays it. No full-object replacement, no last-write-wins clobber across concurrent edits to different fields.

## Other entities

Same shape for `Setting` / `BibleObject` / `LorebookEntry` / `DynamicSheet` — each has its own `…Patch` + `Snapshot…` + TS mirror + editor view. `LorebookEntry` and `DynamicSheet` patches (`LorebookEntryPatch`, `DynamicSheetPatch`) follow the identical optional-field + `apply` pattern.

## See also

- **UI architecture** — the snapshot/intent bridge this rides on.
- **Data model** — the entity shapes + the snapshot/patch projection note.
- **Conventions + dead ends** — forward-load + change-both-sides conventions.

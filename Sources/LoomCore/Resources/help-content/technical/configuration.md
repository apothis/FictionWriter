# Configuration

Where Loom's settings live, how the two layers compose, how server roles resolve, and how sampler families override defaults. The Codable shapes themselves are catalogued in **T.3 — Data model**; this page is the *system* — how config is read, resolved, and applied.

## Two config layers + one cross-project file

| File | Shape | Scope |
|---|---|---|
| `~/Library/Application Support/Loom/settings.json` | `AppSettings` | App-wide — server profiles, role assignments, recents |
| `<project>.loom/project.json` (the `settings` object) | `ProjectSettings` | Per-project — memory, author's note, writing direction, budgets |
| `~/Library/Application Support/Loom/styles.json` | `StyleLibrary` | Cross-project — named style entries |

Read/written through `Storage/AppSettingsStore.swift` + `Storage/StyleLibraryStore.swift` (app-wide) and `Storage/ProjectStorage.swift` (per-project, inside `project.json`). All use the shared `JSONEncoder.loom` / `JSONDecoder.loom`. Forward-load posture is `decodeIfPresent`-everywhere — see **T.3**.

## Server profiles + role resolution

`AppSettings` holds `servers: [ServerProfile]` plus two role pointers:

- `defaultServerId` → the **writer** (Continue/Expand/Rewrite). Resolved by `AppSettings.writerServer()`.
- `extractorServerId` → the **extractor** (ledger/discovery/continuity Ollama side-tasks). Resolved by `AppSettings.extractorServer()`.

Resolution rules (`Models/AppSettings.swift`):

- `addServer` auto-promotes the **first** profile to default (so a fresh setup with one server needs no explicit role click).
- `removeServer` falls the default to the first remaining server; clears the extractor entirely if it was the removed one (no implicit fallback — a missing extractor is a valid state, and running extraction against the heavy writer model is exactly the failure the role split avoids).
- `extractorServer()` returns nil when unset; callers **skip** the side-call rather than falling back to the writer.

A `ServerProfile` carries `kind` (`.kobold` / `.ollama`) — the wire-protocol discriminator the network layer reads to pick `/api/v1/generate` (Kobold) vs `/api/chat` (Ollama) — plus cached `capabilities` (model name, true max context, version) populated by `ServerProbe` / `OllamaProbe`.

## Sampler configuration

Two shapes, deliberately decoupled:

- **`GenerationDefaults`** (`Models/Project.swift`) — the Loom-side, user-facing shape on `ProjectSettings.generationDefaults`. Per-mode word targets + the sampler values as the user thinks of them.
- **`SamplerParams`** (`Networking/SamplerParams.swift`) — a flat struct mapping **1:1 to KoboldCpp's `/api/v1/generate` body keys**. Keeps `KoboldClient` a thin HTTP wrapper, not a domain model.

Defaults (both shapes agree): temperature 1.0, minP 0.05, topK 0, DRY (0.8 / 1.75 / 2), XTC (0.10 / 0.50), repPen 1.07, repPenRange 1024. The KoboldCpp `samplerOrder` default is `[6, 0, 1, 3, 4, 2, 5]`.

`bannedStrings` (the anti-slop list) lives on `SamplerParams`, not `GenerateRequest` — so every generation path that passes sampler params (editor, template-gen, planned-beat drafting) carries it uniformly.

### Sampler family overrides

`SamplerParams.familyOverride(forModelName:)` applies model-family-specific sampler tweaks at request-construction time, layered over the project's `GenerationDefaults`. Today there's one family:

- **Mistral-Small-3.x finetunes** — detected by name substring (`goetia`, `cydonia`, `magidonia`, `harbinger`, `hearthfire`, `skyfall`). Override: **temperature 0.8, minP 0.025, repPen 1.05** — the community-recommended samplers for that finetune family (MuXodious/Drummer card discussions).

Everything else returns nil (project defaults are already correct). The override is three values (`SamplerFamilyOverride`: temperature / minP / repPen); the rest stay at the project basis. To add a family: extend the `familyOverride` substring chain.

This is the sampler analogue of the instruct-template detection (**T.4**) — both key off the probed model name, both default to a sensible fallback, both are a substring-match chain you extend when a new model family lands.

## Project Memory presets

`Models/ProjectMemoryPresets.swift` — three seed templates for `ProjectSettings.memory`:

- **`loomDefault`** — the anti-refusal default. **Seeded onto every new project** by `ProjectStorage.createNewProject`.
- **`marinaraStyle`** — the heavier community-canonical NSFW posture ("Anything goes…").
- **`minimal`** — a stripped-down prompt.

`ProjectMemoryPresets.all` is the pickable list. The user can also paste arbitrary text; presets are starting points, not an enum the field is constrained to.

## What's configured where — quick map

| To change… | Edit | Surface |
|---|---|---|
| Which model writes | `defaultServerId` | Settings → Servers → Set as Default |
| Which model extracts | `extractorServerId` | Settings → Servers → Set as Extractor |
| System prompt | `ProjectSettings.memory` | Settings → Project → Project Memory |
| Writing posture | `ProjectSettings.writingDirection` | Settings → Project (kind/register/explicitness) |
| Context budget | `ProjectSettings.contextBudgetTokens` | Settings → Project → Token Budgets |
| Anti-slop list | `ProjectSettings.antiSlopPhrases` | Bible → Edit Anti-slop List… |
| Samplers | `GenerationDefaults` / `SamplerParams` | **Not in-app** — defaults in code + family override; tune further in KoboldCpp |
| Instruct template | `ProjectSettings.instructTemplate` | `.auto` (name detection); not surfaced as a control |

## Seeding a new project

`ProjectStorage.createNewProject` seeds two things onto `ProjectSettings` at creation so a new project ships sane:

- `settings.memory = ProjectMemoryPresets.loomDefault.text`
- `settings.antiSlopPhrases = AntiSlopDefaults.phrases`

Everything else takes the `ProjectSettings.defaults` values.

## See also

- **Data model** — the Codable shapes (`AppSettings`, `ProjectSettings`, `GenerationDefaults`, `ServerProfile`).
- **Generation pipeline** — instruct-template detection (the sibling of sampler-family detection).
- **Settings — app-level + per-project** (User Help) — the user-facing settings map.
- **NSFW / dark-fiction posture** (User Help) — sampler defaults + memory presets from the writer's side.

# Conventions + dead ends

The house rules that aren't obvious from any single file, and the catalogue of paths already tried and abandoned. **Read the dead-ends table before spiking anything** — several of these cost real time to disprove.

## Conventions

### Code wins over design docs

The `LOOM_*.md` docs are plan + research + session ledgers. They go stale. When a doc and the code disagree, **the code is authoritative** — and this help book is written from code, citing docs only for design intent. If you're about to trust a doc claim, verify it against the relevant `.swift` first. (This very rule has paid off repeatedly: the data model predated half the current schema; a "20-layer" prompt model that doesn't match `buildLayers`; five generation-mode enum cases the doc lists as shipped that aren't wired.)

### TDD, always

Every code change starts with a failing test (red → green → commit). No exceptions. The harness is TestKit (`swift run LoomCoreTests`, not XCTest — see **Build / test / run**). **Every schema change pins an "old-JSON-decodes" forward-load case** so a future field addition can't silently break existing project files.

### Forward-load persistence

Schema migration is lazy + forward-load-tolerant: every additive field is `decodeIfPresent` with a recovering default; no migration framework. `Scene` / `ReferenceText` / `TemplateScene` carry an `extraFrontmatter: [String: String]` sink so a file written by a newer Loom round-trips through an older one without data loss. Writes are atomic (temp + rename); `project.json` gets a verified `.bak` before each save.

### No `async/await`

Production code is callback-completion + `DispatchQueue`, not `async/await` (a toolchain-floor decision; not yet revisited). Each pipeline owns its own serial queue; results bounce to main before touching UI. Don't introduce `async/await` in new code without a deliberate, whole-subsystem migration.

### Defer-and-flush in callback test stubs

When stubbing a callback-async API in a test, **defer the completion and flush it**, never call `completion(...)` synchronously inside the stub. A synchronous completion hides `[weak self]` lifetime + ordering bugs that only surface under real async dispatch — the stub passes, production crashes.

### Async iteration → loops, not recursion

A completion-passing function walking a collection uses nested `while` loops, not recursion + a trampoline tuned to a guessed stack budget. Tuning a recursion-depth constant to fit specific test data is a smell that the structure is wrong. (`RagChunker` is the reference shape.)

### Pure types stay pure

`PromptBuilder`, the filter pipelines, the activators, the parsers — pure data, no logging, no I/O, callable from any thread, exhaustively unit-tested. The **coordinator that calls them** does the logging (`[gen]`, `[ledger]`) + the network. Don't add a `DebugLog.write` inside a pure-data type.

### Fail-soft pipelines

Extraction, retrieval, ingest — every background pipeline degrades rather than crashes. A transport error, parse failure, or filter exception logs to its subsystem and lets the user keep writing. Enhancement, never gate. (The continuity audit's "typing stage failed — keeping stage-1 types" is the pattern.)

### Positive prompt constraints, never blacklists

Prompt-side, state what the prose *should* do, never enumerate forbidden phrases — models paraphrase around a blacklist. The one phrase-list Loom uses (anti-slop) is a **sampler-level** `banned_strings` backtracking constraint enforced in KoboldCpp, not a prompt instruction. See **Generation pipeline** + the User Help **Anti-slop** section.

### New UI as a webview

New feature UI lands as a WKWebView panel using the snapshot/intent bridge (**T.8**), not a new AppKit form. The AppKit editor surface is stable and rarely grows.

### Probe with the production stage's actual outputs

A capability probe on clean fixture/gold data answers a *different question* than the production pipeline asks. Before scoping a feature around a probe result, make the probe consume what the production stage actually feeds the model (e.g. extracted-claim paraphrases, not gold strings). A green probe on idealised inputs does not predict the production measurement.

### Verify before designing around a gap

Before scoping a spike around "no widely-adopted X exists" or "the literature is silent on Y", run a focused search pass first — and check the **local** toolchain (`xcode-select -p`, disk space, installed tools), not just published library state. The MLX port was implemented and then reverted because Xcode wasn't installed on the build machine — caught post-implementation, not before.

## Dead ends — do NOT re-spike

Tried, measured, abandoned. Don't burn time re-disproving these without genuinely new information.

| Topic | Verdict | Reference |
|---|---|---|
| **Ollama `format` JSON-schema on small gemma** | Avoid — ~50% degenerate-empty flake. Use unconstrained + pinned fields + JSONL + tolerant parse, or GBNF on Kobold | LOOM_CONTINUITY_AUDIT §3.1, HANDOFF §15.19 |
| **Prefill-continue on instruct models** | Doesn't work — Qwen/Gemma treat the assistant prefill as a completed turn, emit 0 tokens. Keep prose in the user block | LOOM_GENERATION_MODES §2.3 |
| **StyleDistance embedder** | Rejected — underperformed even the topical baseline; **Wegmann** chosen (+0.285 vs +0.086 separation) | LOOM_SCENE_EXEMPLAR §6.1 |
| **Python embedding subprocess** | Replaced — native CoreML drops ~3 GB of deps + the cold-start. `PythonEmbeddingClient` survives as fallback only | LOOM_PLAN L8 |
| **MLX port of the embedder** | Reverted — needed a local toolchain (Xcode/Metal) not installed; surfaced post-implementation | LOOM_MLX_PORT_SPIKE §12 |
| **Whole-document LLM contradiction judging** | Rejected — ~54% precision (ContraDoc). The audit decomposes to pairwise adjudication instead | LOOM_CONTINUITY_AUDIT §2, §13 |
| **DeBERTa-v3 NLI proposition gate (continuity Part A)** | Built, measured no win, ripped out — extracted-claim paraphrases come back `neutral` under strict NLI even when contradicting | LOOM_CONTINUITY_AUDIT §25–26 |
| **Same-fact LLM ledger (continuity Part B)** | Built two shapes, both net-negative on Goetia vs the legacy path, reverted | LOOM_CONTINUITY_AUDIT §27–28 |
| **Classic IE (OpenIE / SRL / REBEL / AMR / spaCy SVO) for fiction claim extraction** | Rejected — trained on news/encyclopedic text, collapse on dialogue + interiority, emit untyped non-source-attributed relations | LOOM_CONTINUITY_AUDIT §15 |
| **GLiREL (relationship-extraction lib)** | Dead — do not re-spike | HANDOFF §15.25 |
| **Relationship-discovery precision levers** | Exhausted — every lever tried; vote-aggregation is the best available | HANDOFF §15.26–27 |
| **TTS / voice, multi-user collab, cloud sync, mobile** | Deferred indefinitely | LOOM_PLAN §1 |

## The registry is the source of truth

`LOOM_TECH_STACK.md` is the living solved-problem + dead-end registry, keyed by *problem → what solves it → where it lives*. **Check it before spiking** — it's indexed by the problem you're facing, not by subsystem. When a new pipeline lands or a spike reaches a verdict, update it. This help section is the narrative companion; the registry is the lookup table.

## See also

- [`LOOM_TECH_STACK.md`](LOOM_TECH_STACK.md) — the registry. Check before spiking anything.
- **Embeddings** — the StyleDistance/MLX/Python-subprocess dead ends in context.
- **Extraction pipelines** — the `format`-schema-avoid + tolerant-parse conventions in context.
- **Build / test / run** — the TDD + defer-and-flush conventions operationally.

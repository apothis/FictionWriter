# How to add: a new extraction pipeline

Adding a "extract structured data from prose" pass — a new sibling to the knowledge ledger, entity discovery, etc. The **knowledge-ledger pipeline is the reference exemplar**; copy its shape. Read **Extraction pipelines** (T.6) first for the shared patterns this assembles, and **don't re-derive the transport decisions** — they're settled (GBNF on Kobold, unconstrained + tolerant-parse on Ollama; never the Ollama `format` schema).

## The components (ledger as the template)

A complete pipeline is ~6 pieces. The knowledge ledger's files, which you'll mirror:

| Piece | Ledger file | Role |
|---|---|---|
| **Types + parser** | `Generation/LedgerExtraction.swift` | The extracted shape, the prompt builder, the GBNF grammar (Kobold) or pinned-field prompt (Ollama), the tolerant parser |
| **Extractor** | `Generation/OllamaLedgerExtractor.swift` | The model call: scene-aware budget + retry-on-empty |
| **Trigger** | `Generation/LedgerExtractionTrigger.swift` | Pure-data word-delta threshold |
| **Coordinator** | `Generation/LedgerExtractionCoordinator.swift` | Debounced dispatch + in-flight guard + completion callback |
| **Filters** | `Generation/LedgerFilters.swift` + `LedgerFilterPipeline.swift` | Cosine dedup + evidence validation + leakage, fail-soft |
| **Store + surface** | `Storage/…Store.swift` + Bible Workspace queue | Persist proposals; review UI |

## 1. Types + prompt + tolerant parser

A `YourExtraction` enum (namespace) with:

- The extracted shape (`Codable` struct).
- `buildExtractionPrompt(...)` — **pin the field names in the prompt body**; prefer JSONL. (Don't rely on the Ollama `format` schema.)
- `parseYourThings(_ raw:) throws -> [...]` — tolerant: locate the payload inside chatty preamble/postamble, accept JSONL or array, recover per-object, throw `noJSONObjectFound` / `noJSONArrayFound` only when nothing's parseable.
- A `gbnfGrammar(...)` if (and only if) the extraction runs on the KoboldCpp writer.

Reuse `LedgerExtraction.cosineSimilarity` etc. rather than re-implementing.

## 2. The extractor

`OllamaYourExtractor` mirroring `OllamaLedgerExtractor`:

- `budgetForSceneWords(_:)` — scene-aware `num_predict` (the ledger's is `min(8192, max(2048, words*8))`; tune the multiplier to your output density).
- `callWithRetry` — on empty `message.content`, retry once with `num_predict` doubled (covers both transient-degenerate and budget-cut-output causes).
- For NSFW-prose robustness, also retry on `noJSONObjectFound` / `noJSONArrayFound` (~30% transient parse-fail rate).
- Completion-callback signature (`Result<[...], Error>`), not `async`.

## 3. The trigger

`YourExtractionTrigger` — pure data, copy `LedgerExtractionTrigger` verbatim and pick a threshold:

```swift
public static func shouldFire(currentWordCount: Int, baselineWordCount: Int?, threshold: Int) -> Bool {
    abs(currentWordCount - (baselineWordCount ?? 0)) >= threshold
}
```

Use absolute delta (heavy deletion is also a re-extraction signal). Threshold tradeoff: lower = more responsive, more wall-clock cost. Ledger uses 200; entity discovery 500 (it's slower).

## 4. The coordinator

`YourExtractionCoordinator` mirroring `LedgerExtractionCoordinator`:

- An **injectable scheduler** (`protocol …Scheduler { schedule(after:action:); cancel() }`, `TimerScheduler` in prod) so tests drive the debounce deterministically.
- `evaluate(...)` → trigger check → schedule a debounced fire (`debounceSeconds = 2.0`); subsequent calls during the window cancel + reschedule.
- An **`inFlightSceneIds` guard** so a still-running extraction isn't re-fired.
- Off-main dispatch; results bounce to main.
- An `onExtractionComplete` callback the downstream (filters → diff → store) hangs off.
- **Fail-soft**: transport error / parse failure logs to your `[yourtag]` subsystem and no-ops; never crashes or blocks the editor.

You can **piggyback on an existing trigger** — entity discovery rides `LedgerExtractionCoordinator.onExtractionComplete` rather than running its own post-scene hook. Consider this if your pipeline should fire on the same cadence as an existing one.

## 5. Filters + diff (optional but usual)

Raw extractor output is noisy. Mirror `LedgerFilterPipeline`:

- **Cosine dedup** — drop paraphrase-duplicate items (text embedder, ~0.85 threshold).
- **Evidence-quote validation** — confirm a claimed evidence quote is grounded in the prose (not hallucinated).
- **Diff vs existing** — drop items already in the bible/store.
- Run async, **fail-soft** (a filter erroring degrades to pass-through, never drops the batch).

## 6. Store + review surface

- A sidecar store mirroring `ProposedEntitiesStore`: `directoryName` + `fileName` statics, `directoryURL(in:)` / `fileURL(in:)`, atomic write, forward-load decode. Lands at `<project>/your-thing/your-thing.json`.
- A review surface in the Bible Workspace — a snapshot field carrying the queue + accept/reject intents (see **How to add a Bible entity field** for the snapshot/intent mechanics). Accept promotes to the real bible; reject drops + remembers the refusal.

## 7. Debug subsystem + tests

- **Add a `[yourtag]` DebugLog subsystem** and narrate decisions (firing / skipping-no-extractor / extracted-N / queued-N-dropped-M / transport-failed) — the ledger's `[ledger]` lines are the model. Skips + degradations log explicitly (see **T.13**).
- **Tests, first.** The pure-data layers all unit-test directly:
  - Parser tolerance (preamble/postamble/JSONL-vs-array/one-bad-object/empty).
  - Trigger threshold (above/below/deletion/nil-baseline).
  - Coordinator debounce + in-flight guard — **using the injected scheduler stub, with deferred completions** (defer + flush; never fire the completion synchronously inside the stub — it hides `[weak self]` lifetime bugs).
  - Filter behaviour, store round-trip + forward-load.

## Don't reinvent

Per the registry (**T.12** / `LOOM_TECH_STACK.md`), these are settled — reuse, don't re-spike:

- Transport: GBNF (Kobold) or unconstrained+JSONL+tolerant-parse (Ollama). The `format` schema is a known ~50% flake.
- Retry-on-empty with doubled budget.
- The injectable-scheduler debounce + in-flight guard.
- Cosine dedup + evidence validation as the filter shape.
- Sidecar-store + accept/reject-queue as the persistence + surface shape.

If your new pass needs something genuinely outside these, that's worth a spike + a registry entry — but check the registry first.

## See also

- **Extraction pipelines** (T.6) — the shared patterns + the five existing pipelines.
- **How to add a Bible entity field** (T.15) — the snapshot/intent mechanics for the review surface.
- **Debug log subsystems** (T.13) — the narration conventions for your `[yourtag]`.
- **Conventions + dead ends** (T.12) — the transport decisions you're inheriting.
- `Generation/Ledger*.swift` — the reference exemplar to copy.

# Debug log subsystems + signal reference

Loom writes an append-only diagnostic log. It's the first place to look when something misbehaves — most subsystems narrate their decisions, so a `grep` usually tells you what happened and why.

## The log

```
$TMPDIR/loom-debug.log
```

Written by `DebugLog.shared` (`Sources/LoomCore/DebugLog.swift`) — a single shared instance, append-only, recreated on each launch (a `=== launched <date> ===` banner marks the start). Line shape:

```
[HH:MM:SS.mmm] [subsystem] event: data
```

Tail it live while reproducing:

```
tail -f $TMPDIR/loom-debug.log
# scope to a subsystem or two:
tail -f $TMPDIR/loom-debug.log | grep -E '\[gen\]|\[ledger\]'
```

`DebugLog.write` dispatches to a private serial queue, so logging is non-blocking and ordered. `DebugLog.shared.path` exposes the file path programmatically.

## Subsystem tags

The full set (`grep -rho '\[[a-z-]*\]'` over `Sources/LoomCore` for the current list):

| Tag | Subsystem |
|---|---|
| `[loom]` | App lifecycle — launch, project create/open/close, window restore |
| `[project]` | Project resolution + lifecycle |
| `[storage]` | File reads/writes — bytes, scene ids, errors |
| `[manuscript]` | Manuscript-tree mutations |
| `[scene]` | Scene-level operations |
| `[editor]` | Editor surface — shortcuts, selection, acceptance state |
| `[inspector]` | Inspector tab state |
| `[gen]` | Generation pipeline — tray clicks, mode dispatch, finish/error, log-write |
| `[ollama]` | Ollama HTTP — request timing, status, transport errors |
| `[ledger]` | Knowledge-ledger extraction + filtering + accept/reject |
| `[proposals]` | Entity discovery — GLiNER candidates, gate, promotion |
| `[relationships]` | Relationship discovery |
| `[continuity]` / `[continuity-audit]` | Continuity audit — extraction, typing, adjudication |
| `[retrieval]` | Style retrieval — match counts, paths active |
| `[ingest]` / `[reference]` / `[scene-exemplar]` | Reference + exemplar ingest |
| `[coreml-embed]` / `[embed-factory]` | CoreML embedder load + the embedder client factory |
| `[template]` / `[template-gen]` | Scene-template extraction + per-beat generation |
| `[outline-draft]` / `[planned]` | Planned Project outline + draft |
| `[bible]` / `[workspace]` | Bible Workspace operations |
| `[snapshot]` | Snapshot capture |
| `[servers]` / `[settings]` | Server probes + settings persistence |
| `[help]` | This help panel |
| `[tools]` | Spike-runner / tool output |

## Signal reference — what good + bad look like

### `[gen]` — generation

```
[gen] tray: continue clicked
[gen] tray: rewritePOV target=Eleanor knows=12 unknowns=3
[gen] finish: ok elapsed=4213ms inserted=287
[gen] finish: error=... elapsed=901ms inserted=0
[gen] rolled-outcome: group=action_outcome entry=[sph] Outcome — partial success instruction-chars=142
[gen] log-written: 20260522-141233-891-<uuid>.json
```

`finish: ok … inserted=N` with N>0 is a healthy generation. `inserted=0` + an `error=` is a failed call — check the adjacent `[ollama]` or writer-server logs.

### `[ledger]` — knowledge-ledger extraction

The most narrated subsystem. A healthy run:

```
[ledger] firing side-call: scene=<id> words=812 characters=4
[ledger] extraction ok: scene=<id> facts=9
[ledger] queued 5 suggestions for scene=<id> breakdown={Eleanor:3,Tom:2} diff-dropped=2 filter-dropped=2/9 {dedup:1,evidence:1}
```

Common "why no suggestions" answers, all logged explicitly:

```
[ledger] skipping side-call: no extractor profile configured   ← set an extractor
[ledger] skipping side-call: scene <id> not found
[ledger] skipping side-call: extraction already in flight for scene=<id>
[ledger] all candidates filtered out for scene=<id> extracted=4 diff-dropped=4 ...   ← all dupes of existing facts
[ledger] empty extraction response — retrying with num_predict=4096   ← the retry-on-empty firing
[ledger] ollama transport failed: ...   ← Ollama unreachable
```

The `breakdown` + `diff-dropped` + `filter-dropped` fields tell you exactly where facts went: extracted N → diff dropped the already-known → filters dropped dupes/hallucinated-quotes → queued the rest.

### `[ollama]` — extractor transport

```
[ollama] dataTask ok in 18.42s
[ollama] dataTask http 404 after 0.03s     ← wrong URL / model not pulled
[ollama] dataTask err after 30.00s ...      ← timeout / server down
[ollama] dataTask no body after 2.10s       ← degenerate empty response
```

### `[retrieval]` — style retrieval

```
[retrieval] installed service for project=MyNovel.loom model=AnnaWegmann/Style-Embedding (CoreML)
[retrieval] released previous service
```

Match counts + active paths per query log here too — the place to confirm a reference actually got retrieved.

### `[proposals]` / `[continuity]` — discovery + audit

```
[proposals] GLiNER detected 7 candidates: ["Sable Point", "Tom", ...]
[continuity] degenerate extraction — re-roll num_predict=8192
[continuity] extraction transport failed: ...
[continuity] typing stage failed: ... — keeping stage-1 types   ← graceful degrade, not a crash
```

## Conventions

- **Tags are grep-stable from the moment a feature ships.** `[gen]` never appears before generation is wired, `[ledger]` not before Phase 4, etc. — so the presence/absence of a tag is itself signal.
- **Skips + degradations are logged, not silent.** "skipping side-call: no extractor" / "typing stage failed — keeping stage-1 types" — the fail-soft paths announce themselves, which is why the log is enough to diagnose most "why didn't X happen" questions without a debugger.
- **Errors carry context, not just the error.** `scene=<id> err=<e>`, `elapsed=Nms inserted=N` — enough to reproduce.
- **Logging is the caller's concern, not the pure types'.** `PromptBuilder`, the filter pipelines, etc. stay pure + testable; the coordinator that calls them emits the `[gen]` / `[ledger]` lines. Don't add logging inside a pure-data type.

## When filing a report

Copy `$TMPDIR/loom-debug.log` somewhere before restarting Loom (it's recreated on launch). The log for the period a bug occurred, plus the relevant `generation-log/<ts>.json`, is usually enough to reproduce. See **R.18 Troubleshooting** (User Help) for the bug-report checklist.

## See also

- **Extraction pipelines** — what the `[ledger]` / `[proposals]` / `[continuity]` lines are narrating.
- **Generation pipeline** — the `[gen]` flow.
- **Troubleshooting** (User Help) — the symptom-first version of this, for users.
- `Sources/LoomCore/DebugLog.swift` — the writer itself.

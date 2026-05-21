# Troubleshooting

Things will go wrong. This page is the catch-all for when they do — symptom → likely cause → what to do, plus how to read Loom's debug log so you can diagnose deeper.

If you're hitting one of these specific cases, the right page is in Getting Started:

- **Won't build, won't launch, macOS won't open it** → **Install + first launch**.
- **Model server unreachable, "no writer configured", LAN flakiness** → **Configure your model servers**.
- **Model refused, model went off-vibe, model writes summary instead of scene** → **When generation refuses or feels off**.

R.18 is for the rest.

## The debug log

Loom writes an append-only debug log to:

```
$TMPDIR/loom-debug.log
```

(`$TMPDIR` on macOS is a private per-user temp directory under `/var/folders/`. Echo `$TMPDIR` in Terminal to see the actual path.)

Tail it live while you reproduce a problem:

```
tail -f $TMPDIR/loom-debug.log
```

Each line is:

```
[HH:MM:SS.mmm] [subsystem] event: data
```

Subsystem tags are grep-able. The most useful for narrowing scope:

| Tag | What you'll see |
|---|---|
| `[loom]` | App lifecycle — launches, project create/open/close. |
| `[storage]` | File reads + writes. Bytes written, scene id, errors. |
| `[project]` | Project lifecycle and resolution paths. |
| `[editor]` | Editor surface — keystroke shortcuts, selection, acceptance state. |
| `[gen]` | Generation pipeline — mode dispatched, prompt assembly, layer eviction. |
| `[ollama]` | Ollama extractor calls + responses. |
| `[ledger]` | Knowledge-ledger extraction + acceptance. |
| `[proposals]` / `[relationships]` | Entity discovery + relationship discovery pipelines. |
| `[retrieval]` | Style retrieval (references) — match counts, vectors used. |
| `[ingest]` / `[reference]` / `[scene-exemplar]` | Reference / exemplar ingest pipelines. |
| `[continuity]` / `[continuity-audit]` | Continuity-audit engine. |
| `[bible]` / `[workspace]` | Bible Workspace operations. |
| `[snapshot]` | Snapshot creation / restore. |
| `[settings]` / `[servers]` | Settings persistence + server probes. |
| `[help]` | This help panel. |

A typical "why didn't this generation use my reference" investigation:

```
tail -f $TMPDIR/loom-debug.log | grep -E '\[gen\]|\[retrieval\]'
```

Now reproduce the problem in the app and watch the lines stream.

## Common problems

### Generation just sits there

- **Spinner spins, no prose ever streams in.** Most often: writer server timed out or never connected. Check `[gen]` lines for `error` or `timeout`. Confirm the writer URL still works in your browser. If KoboldCpp died or restarted, re-probe via Settings → Servers (re-add isn't needed; the auto-probe runs whenever you open the Settings tab).
- **Spinner spins for 30s+ on a small model.** If you're running on a Mac with very little spare RAM, the system may be swapping. Check Activity Monitor — KoboldCpp's memory + swap usage.
- **Click Continue, nothing happens, no spinner.** Likely a state-machine wedge — the previous generation didn't fully clear. Click somewhere in the editor, press Esc, try again. If persistent, restart Loom.

### Generations are tonally wrong / off-voice / model writes nothing like your style

The toolkit is in **When generation refuses or feels off** in Getting Started. In short: tighten Project Memory, raise samplers, change instruct template, switch model. For style specifically, also confirm:

- You have References ingested (Bible Workspace → References tab; each entry should show its chunk count, not a bare "Ingest" button).
- The references' voice actually matches what you want to write. Retrieval scores against your *current cursor's* prose; a reference whose voice diverges from your manuscript at that point won't rank well.

### Entity-discovery / knowledge-ledger / continuity-audit not running

- **No suggestions appearing** even though you've written several long scenes. First check: do you have an **extractor** server set? Settings → Servers — there should be a row with `(extractor)` next to it. If not, the Ollama side-tasks don't run.
- **Extractor is set, still no suggestions.** Confirm Ollama is up: `curl http://localhost:11434` should return `Ollama is running`. Then check the debug log for `[ollama]` lines — failures show as `error` or `timeout`.
- **Wrong model loaded.** Loom's extractor pipelines are calibrated for `gemma4_2b`. Other small instruction-tuned models work but parse tolerances may shift. `ollama list` shows what you have pulled; `ollama pull gemma4_2b` if needed.
- **Scene under the threshold.** Knowledge-ledger extraction needs a 200-word delta since last run; entity discovery needs 500. A scene with only 100 words won't trigger anything automatic. Use **Bible → Discover Entities in Current Scene** to force-run discovery, or just keep writing.

### Bible Workspace won't open / is blank

- **Window opens but the content area is white.** Almost always a side-bundle build problem — the webview is loading but the assets aren't there. Rebuild Loom (`./build.sh`); the bun step is loud about bundle failures. If the build succeeds and the panel still blanks, restart Loom.
- **Window opens but no projects appear.** No project is open. Open or create one from File menu, then re-open Bible Workspace.

### Snapshots not appearing

- **Made changes via AI rewrite; no snapshot to revert to.** Loom takes snapshots before generation-mode rewrites (the Rewrite sub-modes, not Continue / Expand). Check the `[snapshot]` debug-log lines — if you don't see a write event around the time of the rewrite, the snapshot path didn't fire.
- **Snapshots directory exists but is empty.** Same — `[snapshot]` is the diagnostic. Snapshots aren't written for non-mutating operations.

### "I edited the file outside Loom and lost my changes"

Loom owns project files while a project is open. The save loop will overwrite hand-edits. Workflow if you want to hand-edit:

1. Quit Loom (or close the project).
2. Edit the file in your text editor of choice.
3. Re-open the project in Loom.

For per-session safety, the **`project.json.bak`** file (covered in **Where your work lives on disk**) holds the previous good copy and the recovery path is automatic on next open.

### Tray buttons greyed out

- **Continue greyed out.** Editor has no prose. Type something.
- **Expand / Rewrite / Show-don't-tell greyed out.** No text selected. They're selection-replace modes.
- **Brainstorm / Critique always greyed out.** Yes — they're not wired today (covered in **Generation modes**). They light up when the work lands.

### Reference / Scene Exemplar ingest fails

- **Ingest button does nothing or errors out.** Most often a Wegmann CoreML init failure on first use. Watch `[coreml-embed]` and `[embed-factory]` lines. The first ingest after a fresh install compiles the model; that takes a few seconds. If it errors instead of stalling, the model bundle didn't ship — rebuild Loom.
- **"Extracted 0 beats" on a scene that's clearly multi-beat.** The Pass-A skeleton extractor's Ollama call returned empty / malformed JSON. Check `[ollama]` and `[scene-exemplar]` lines. The pipeline retries internally; if every retry fails, the model is having a bad day or the prose has confused it. Try with a shorter, structurally simpler scene first.

### App slows down over time

Long sessions with many generations can accumulate a large in-memory history. Restarting Loom is a reliable reset — your work is on disk, so nothing is lost.

If a particular operation became slow:

- **Generation latency growing per call.** Likely the prompt is growing — bible additions, more references, growing manuscript. Check the History inspector to see actual token counts. If the prompt is approaching your context budget, evictions kick in (look for `evicted:` in the gen log entry).
- **Slow file opens.** A `references/` or `templates/` directory with many large entries takes longer to enumerate on open. There's no fix here other than triaging the directory; performance is roughly linear in entry count.

### When you want to file a useful bug report

Loom is local-only; there's no telemetry. If you're filing a bug (to yourself, to a collaborator, to the project), the most useful artefacts are:

1. **The debug log** for the period the bug occurred. Copy `$TMPDIR/loom-debug.log` somewhere safe before you restart Loom (the file is recreated on launch).
2. **The relevant generation-log entry**, if it's a generation issue. Under `<project>.loom/generation-log/<timestamp>.json`. Each entry has the full assembled prompt, the response, sampler state, mode — everything needed to reproduce.
3. **The project file** (or a minimal reduction of it) — if you can't share the whole thing, deleting all but the relevant scene + bible state often reproduces.
4. **What you expected vs what happened.** Two sentences.

A bug report with those four things is dramatically easier to triage than "the model didn't do the thing."

## A note on what's NOT broken

Some things look wrong but aren't:

- **The model writes for a few sentences and then stops on a sentence fragment.** Not a bug — Continue's word target is a hint, and the model is encouraged to end at natural pauses (paragraph break, scene beat). A short generation isn't a failure; it's a beat. Click Continue again to keep going.
- **The acceptance row doesn't disappear when you start typing into the inserted span.** It does — but only on the next idle moment. Cosmetic; functionality is correct.
- **The Anti-slop list seems to be ignored on rare phrases.** Anti-slop is a backtracking sampler in KoboldCpp; it can backtrack a few tokens at a time but can't undo a phrase already crossed several tokens back. Phrases that drift in after a long sequence of high-probability tokens occasionally slip through. If a phrase recurs persistently, adding it to the list still helps — the backtracking has a bigger effect on the next 95% of attempts than the 5% it misses.

## See also

- **Where your work lives on disk** — for understanding what lives where and what's recoverable.
- **Generation pipeline** (Technical Reference) — for the deeper "how generations are assembled" when a History entry doesn't tell you everything you need.
- **Configure your model servers** — when the issue traces back to the model server, not Loom.

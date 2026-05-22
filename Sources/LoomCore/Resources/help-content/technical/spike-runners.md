# Spike runners (Tools/*)

The `Tools/*` directory holds on-demand eval + probe executables — each a separate `executableTarget` compiled against `LoomCore` but excluded from the shipping app and the test suite. They hit live local-LLM servers, score against hand-graded fixtures, and emit markdown reports for tuning. Run with `swift run <Name>`.

They are **not** part of `swift run LoomCoreTests` — they're network-y, slow, and non-deterministic by design. You run them deliberately when tuning a pipeline or validating a model change.

## Index

| Tool | What it does | Run |
|---|---|---|
| **LedgerSpike** | Knowledge-ledger extraction eval. Loads a hand-graded fixture, runs the §3.3 extraction prompt per scene, scores vs the gold ledger, emits a markdown report. | `swift run LedgerSpike` |
| **EntityDiscoverySpike** | Entity-discovery precision/recall. Drives Stage A2 (candidate gen) + promotion gate + Stage D (normalisation) per scene, scores proposed entities vs gold. | `swift run EntityDiscoverySpike` |
| **EntityDetectionProbe** | GLiNER span debugger. Runs the detector at a low threshold on one scene, prints every candidate span + sigmoid score + label — so a missed entity can be checked against the production 0.5 threshold. | `swift run EntityDetectionProbe <scene.md>` |
| **RelationshipDiscoveryProbe** | Relationship-classifier precision. Runs the two-stage pairwise classifier ± the binary evidence gate on co-occurring pairs; measures whether the gate cuts gemma's stable edge mis-classification. | `swift run RelationshipDiscoveryProbe` |
| **ContinuityAuditSpike** | Continuity-audit feasibility. Drives the fixture through extraction + pairwise adjudication, scores each end against the hand-graded gold set. | `swift run ContinuityAuditSpike` |
| **RagSpike** | Style-retrieval (RAG) eval. Talks to Kobold + Ollama directly; evaluates Paths D/E retrieval against a fixture. `--smoke` for a fast backend check. | `swift run RagSpike --smoke` |
| **SceneExemplarSpike** | Embedder-discrimination spike (Phase 8.a §6.1). The four-candidate embedder probe (StyleDistance / Wegmann / LUAR / mxbai) that locked D4 to Wegmann. | `swift run SceneExemplarSpike` |
| **SceneTemplateSpike** | Pass-A beat-extraction probe. Runs beat extraction on a fixture (or all), writes a markdown report to `Tools/SceneTemplateSpike/last-run/<fixture>.md` for hand-grading. | `swift run SceneTemplateSpike` |
| **OutlineGenerationProbe** | Planned-Project outline generation. Runs `OutlineGenerator` against a live model, prints the manuscript outline, for tuning the beats + scenes prompts. | `swift run OutlineGenerationProbe` |
| **OutlineDraftProbe** | Planned-Project per-beat drafting. Runs `OutlineDraftCoordinator` (beat-plan + per-beat writer calls), prints the drafted scene prose. | `swift run OutlineDraftProbe` |
| **CoreMLProbe** | Builds + smoke-tests the Wegmann CoreML bundle. `build_mlpackage.py` produces the `.mlpackage`; the Swift driver verifies cosine-equivalence to the Python reference. | (see `Tools/CoreMLProbe/`) |
| **GLiNERProbe** | Exports GLiNER to ONNX (`export_gliner_onnx.py`) + smoke-tests the runtime path. One-off — the ONNX bundle ships in-repo. | (see `Tools/GLiNERProbe/`) |

## Configuration

Each runner reads its endpoints from environment variables, with defaults pointing at the canonical dev servers:

| Env var | Default | Used by |
|---|---|---|
| `LOOM_SPIKE_OLLAMA_URL` | `http://localhost:11434/` | the extraction/discovery spikes |
| `LOOM_SPIKE_OLLAMA_MODEL` | `gemma4_2b:latest` | same |
| `LOOM_PROBE_KOBOLD_URL` | `http://192.168.1.201:5001` | the outline/writer probes |
| `LOOM_PROBE_BACKEND` | `kobold` (or `ollama`) | OutlineGenerationProbe |
| `LOOM_PROBE_THRESHOLD` | `0.01` (production 0.5) | EntityDetectionProbe |

Check the top-of-file doc comment in each `Tools/<Name>/main.swift` for its exact flags + env contract — they're documented inline.

## Patterns these share

- **Fixture-driven.** Most load a hand-graded fixture (gold ledger / gold entities / gold conflicts) and score against it — precision / recall / F1. Fixtures live next to the runner or under `Tests/LoomCoreTests/Fixtures`.
- **Markdown report to stdout** (some also to a `last-run/` dir) for hand-grading + commit-to-history.
- **They drive the *production* code paths**, not reimplementations — `LedgerSpike` runs the real `OllamaLedgerExtractor`, `ContinuityAuditSpike` the real `ContinuityAuditEngine`, etc. That's the point: they measure what ships.
- **`--smoke`** where present is a fast reachability check (a few seconds per backend) vs the full eval run.

## When to reach for one

- **Tuning a prompt** — run the relevant spike before and after; compare the scored report.
- **Validating a model swap** — re-run the spikes whose pipeline that model serves (writer swap → outline probes + continuity; extractor swap → ledger + entity + relationship spikes).
- **Debugging a missed extraction** — `EntityDetectionProbe` for GLiNER spans; the full spikes for end-to-end.
- **Regenerating a model** — `CoreMLProbe` (Wegmann) / `GLiNERProbe` (ONNX export).

The de-risk lesson worth repeating (it cost real time): **a probe on clean fixture data answers a different question than the production pipeline asks.** A capability probe that passes on gold strings doesn't guarantee the production stage — which feeds the model *extracted-claim paraphrases*, not gold strings — will pass. Probe with the production stage's actual outputs, not idealised inputs.

## See also

- **Build / test / run** — the standard build + the `swift run LoomCoreTests` suite (distinct from these).
- **Extraction pipelines** — the production pipelines these spikes exercise.
- **Embeddings** — the embedder probe (`SceneExemplarSpike`) + the model-build probes.
- **Repo layout** — the `Tools/` directory in the tree.

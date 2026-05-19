# NLIProbe — NLI cross-encoder model tooling

Build-time tooling for Loom's Continuity Audit NLI proposition gate
(`LOOM_CONTINUITY_AUDIT.md` §25, Part A).

## Why an NLI cross-encoder

The audit pairs claims by embedding cosine, then has an LLM adjudicate.
§24 measured that embedding cosine — a **bi-encoder** — scores *topic*,
not *proposition*: a topical look-alike out-scored a real contradiction.

A **cross-encoder** scores the two claims jointly. An NLI cross-encoder
labels the pair `contradiction` / `entailment` / `neutral`. The A0 probe
(§25) confirmed `contradiction` cleanly flags real world-fact
contradictions — 34/36 of the eval-fixture golds — while genuinely
unrelated pairs come back `neutral`. So the gate sits after embedding
retrieval and drops `neutral` pairs before the LLM ever sees them.

Scope: the gate is for the **world-fact classes** (attribute / timeline
/ spatial). NLI is weaker on the knowledge class (strict entailment is
narrower than "same proposition") — that class is handled separately
(§25 Part B).

## Runtime: ONNX Runtime, FP32

The model is `MoritzLaurer/DeBERTa-v3-large-mnli-fever-anli-ling-wanli`.
It runs via ONNX Runtime — the same runtime already linked for GLiNER —
with zero runtime Python.

It ships **FP32 (~1.7 GB)**, not INT8-quantized. Dynamic INT8 was tried
and verified to break it: DeBERTa-v3's disentangled attention is
quantization-sensitive, and the INT8 model flipped verdicts (a clear
`contradiction` at logit 4.96 collapsed to `neutral`). A 3-way argmax
with tight margins has no tolerance for INT8 logit mush — unlike GLiNER,
whose per-span sigmoid NER quantizes cleanly. The bundle is gitignored
and regenerated locally, so the size is a local-disk cost only.

## Scripts

- `export_nli_onnx.py` — exports the model to FP32 ONNX →
  `Sources/LoomCore/Resources/NLI/` (gitignored). Run once on a dev
  machine; see the script docstring for the venv prerequisites.
- `verify_nli_onnx.py` — loads the exported bundle via ONNX Runtime and
  checks a handful of world-fact pairs decode correctly.

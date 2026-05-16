# GLiNERProbe — native entity-detection model tooling

Build-time tooling for Loom's GLiNER-based entity detector.

## Why GLiNER

Entity discovery originally asked a generative LLM (gemma4_2b via
Ollama) to read a scene and emit entities. On dense, sexually-explicit
fiction prose that model is unreliable — it derails, soft-refuses, or
returns empty (~20–80% per call, scene-dependent). No amount of
prompt/format/streaming work fixes the floor, because the failure is
the generative model itself.

GLiNER is a small **bidirectional NER encoder** (~50 M params). It
scores candidate spans against a label set in one forward pass. It is:

- **deterministic** — same input, same output;
- **refusal-proof** — a tagger has no "reader" persona to moralize with;
- **fast** — ~40 ms inference (verified), versus ~30–50 s of LLM
  generation;
- **scale-friendly** — cheap enough to run per-chunk over long text.

It detects entity *spans*; the LLM is still used for the *structuring*
step (canonical name, one-line) and for relationships.

## Runtime: ONNX Runtime, not CoreML

The project's other native model (Wegmann embeddings) ships as CoreML.
GLiNER does **not** follow that path: its DeBERTa-v3 backbone has
dynamic control flow in the disentangled-attention relative-position
code that `coremltools` cannot trace (two conversion attempts failed at
the trace stage). ONNX export, by contrast, is clean and verified.

So GLiNER runs via **ONNX Runtime** linked into the Swift package as a
binary dependency. This is still **zero runtime Python** — Python is
used only here, offline, to produce the ONNX bundle.

## Files

- `export_gliner_onnx.py` — exports `urchade/gliner_small-v2.1` to a
  quantized INT8 ONNX bundle (model + tokenizer + GLiNER head config).
- `verify_gliner_onnx.py` — loads the exported bundle through GLiNER's
  ONNX path and confirms it tags a test sentence correctly.

## Regenerating the bundle

The ONNX bundle (~184 MB) is gitignored — regenerate it locally before
a build, the same posture as the Wegmann CoreML bundle.

```sh
python3 -m venv /tmp/gliner-export
. /tmp/gliner-export/bin/activate
pip install gliner onnx onnxruntime
python Tools/GLiNERProbe/export_gliner_onnx.py
python Tools/GLiNERProbe/verify_gliner_onnx.py
```

Output lands in `Sources/LoomCore/Resources/GLiNER/`.

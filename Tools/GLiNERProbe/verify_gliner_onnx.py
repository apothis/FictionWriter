#!/usr/bin/env python3
"""Verify an exported GLiNER ONNX bundle produces correct NER.

Loads the bundle through GLiNER's ONNX inference path and runs the
detector on a deliberately explicit-flavoured sentence (the use case is
adult fiction — the tagger must not refuse or degrade on such input).

Build-time tool. Run after export_gliner_onnx.py.

Usage:
    python verify_gliner_onnx.py [bundle_dir]
"""
import sys
import time
import traceback
from pathlib import Path

# Mixed entity kinds + explicit-adjacent content: characters, a place,
# a named object. GLiNER, being an encoder/tagger, has no refusal
# behaviour — this just confirms the exported graph still tags well.
TEXT = (
    "Marek pressed the obsidian dagger against the cold wall of the "
    "cathedral while Yelena watched from the balcony, her robe undone."
)
LABELS = ["character", "place", "object"]


def main() -> int:
    repo_root = Path(__file__).resolve().parents[2]
    bundle = (
        Path(sys.argv[1]).resolve()
        if len(sys.argv) > 1
        else repo_root / "Sources/LoomCore/Resources/GLiNER"
    )
    if not (bundle / "model_quantized.onnx").exists():
        print(f"error: no model_quantized.onnx in {bundle} — run export_gliner_onnx.py first.")
        return 1

    try:
        from gliner import GLiNER
    except ImportError:
        print("error: `gliner` not installed — see export_gliner_onnx.py's docstring.")
        return 1

    print(f"loading ONNX bundle from {bundle} …", flush=True)
    try:
        t0 = time.time()
        model = GLiNER.from_pretrained(
            str(bundle),
            load_onnx_model=True,
            load_tokenizer=True,
            onnx_model_file="model_quantized.onnx",
        )
        print(f"  loaded in {time.time() - t0:.1f}s")
    except Exception as exc:  # noqa: BLE001
        traceback.print_exc()
        print(f"ONNX LOAD FAILED: {exc}")
        return 1

    try:
        t0 = time.time()
        ents = model.predict_entities(TEXT, LABELS, threshold=0.4)
        print(f"inference {time.time() - t0:.3f}s")
    except Exception as exc:  # noqa: BLE001
        traceback.print_exc()
        print(f"ONNX INFERENCE FAILED: {exc}")
        return 1

    for e in ents:
        print(f"  {e['label']:10s} {e['text']!r}  score={e['score']:.3f}")

    # Sanity floor: the three obvious proper-noun entities must surface.
    found = {e["text"] for e in ents}
    expected = {"Marek", "Yelena"}
    missing = expected - found
    if missing:
        print(f"\nFAIL: expected entities not detected: {sorted(missing)}")
        return 1
    print("\nverification OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())

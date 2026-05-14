#!/usr/bin/env python3
"""
Cosine-equivalence probe for Wegmann Python ↔ CoreML conversion.

Goal: confirm a coremltools-converted .mlpackage of AnnaWegmann/Style-
Embedding produces vectors that are within ~1e-4 cosine of the
canonical sentence-transformers path on the same input. If cosines
match cleanly across a handful of test strings, the native Swift
path is viable; if they drift, the mean-pooling / tokenizer flow
needs fixing before any production swap.

Pipeline:
  1. Load AnnaWegmann/Style-Embedding via sentence-transformers
     (the production path); compute the reference vector for each
     test string.
  2. Wrap the underlying transformer in a torch.nn.Module that does
     mean-pooling + L2 normalization (matching sentence-transformers'
     `normalize_embeddings=True` default that the Phase 5 + 8 code
     uses).
  3. Trace + convert via coremltools to a .mlpackage.
  4. Load the .mlpackage via coremltools' Python MLModel wrapper
     (which uses the same Apple CoreML framework Swift would).
  5. Tokenize each test string via HF transformers AutoTokenizer
     (this is the same tokenizer Swift's `swift-transformers`
     library would emit byte-equivalent output for, assuming the
     BPE path is wired correctly).
  6. Run MLModel.predict and compute cosine vs the reference.
  7. Print per-string cosines + summary verdict.
"""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path
from typing import List

import numpy as np
import torch


def main() -> int:
    print("[probe] loading sentence-transformers reference model...", file=sys.stderr)
    from sentence_transformers import SentenceTransformer

    MODEL_ID = "AnnaWegmann/Style-Embedding"
    MAX_LEN = 128

    st_model = SentenceTransformer(MODEL_ID)

    test_strings = [
        "She walked the road. The road was long.",
        "The corridors stretched away in shadow, and the wax of the candles ran slow upon the floor.",
        "She gets on top of him without saying anything. He puts his hands on her hips.",
        "Inspection of structure 4710-A conducted 09:30. Soffit concrete in fair condition.",
        '"Stop," she said. "I will not."',
    ]

    # ---- Reference: sentence-transformers + normalize_embeddings=True ----
    print("[probe] computing reference vectors via sentence-transformers...", file=sys.stderr)
    refs = st_model.encode(test_strings, normalize_embeddings=True, show_progress_bar=False)
    print(f"[probe] reference dim={refs.shape[1]}", file=sys.stderr)

    # ---- Build the torch module to convert ----
    # sentence-transformers SentenceTransformer is an nn.Sequential of
    # Transformer + Pooling + Normalize. The trace path benefits from
    # an explicit single-output module, so we hand-roll mean-pool +
    # L2-norm against AutoModel hidden_states.
    print("[probe] building traceable wrapper module...", file=sys.stderr)
    from transformers import AutoTokenizer, AutoModel

    tokenizer = AutoTokenizer.from_pretrained(MODEL_ID)
    base = AutoModel.from_pretrained(MODEL_ID)
    base.eval()

    class WegmannWrapper(torch.nn.Module):
        def __init__(self, transformer: torch.nn.Module):
            super().__init__()
            self.transformer = transformer

        def forward(self, input_ids: torch.Tensor, attention_mask: torch.Tensor) -> torch.Tensor:
            out = self.transformer(
                input_ids=input_ids,
                attention_mask=attention_mask,
            )
            # last_hidden_state: [B, T, H]; attention_mask: [B, T]
            hidden = out.last_hidden_state
            mask = attention_mask.unsqueeze(-1).to(hidden.dtype)
            summed = (hidden * mask).sum(dim=1)
            counts = mask.sum(dim=1).clamp(min=1e-9)
            mean = summed / counts
            normed = torch.nn.functional.normalize(mean, p=2, dim=1)
            return normed

    wrapper = WegmannWrapper(base)
    wrapper.eval()

    # Cross-check the wrapper against sentence-transformers on the
    # same inputs BEFORE converting. If torch-side drift exists, no
    # amount of CoreML fiddling will fix it.
    print("[probe] verifying torch wrapper matches sentence-transformers...", file=sys.stderr)
    with torch.no_grad():
        for i, s in enumerate(test_strings):
            tok = tokenizer(
                s, padding="max_length", truncation=True,
                max_length=MAX_LEN, return_tensors="pt",
            )
            v = wrapper(tok["input_ids"], tok["attention_mask"]).numpy()[0]
            ref = refs[i]
            cos = float(np.dot(v, ref) / (np.linalg.norm(v) * np.linalg.norm(ref)))
            print(f"  torch-wrapper vs sentence-transformers [{i}]: cosine={cos:.6f}", file=sys.stderr)

    # ---- Trace + convert ----
    print("[probe] tracing wrapper...", file=sys.stderr)
    example_ids = torch.zeros(1, MAX_LEN, dtype=torch.int32)
    example_mask = torch.ones(1, MAX_LEN, dtype=torch.int32)
    traced = torch.jit.trace(wrapper, (example_ids, example_mask), strict=False)

    print("[probe] converting to CoreML (.mlpackage)...", file=sys.stderr)
    import coremltools as ct

    mlmodel = ct.convert(
        traced,
        convert_to="mlprogram",
        compute_units=ct.ComputeUnit.ALL,
        minimum_deployment_target=ct.target.macOS14,
        inputs=[
            ct.TensorType(name="input_ids", shape=(1, MAX_LEN), dtype=np.int32),
            ct.TensorType(name="attention_mask", shape=(1, MAX_LEN), dtype=np.int32),
        ],
        outputs=[ct.TensorType(name="embedding")],
    )

    tmpdir = Path(tempfile.mkdtemp(prefix="wegmann-coreml-"))
    pkg_path = tmpdir / "StyleEmbedding.mlpackage"
    mlmodel.save(str(pkg_path))
    print(f"[probe] saved {pkg_path}", file=sys.stderr)

    # ---- Round-trip: load + predict ----
    print("[probe] loading mlpackage + computing CoreML vectors...", file=sys.stderr)
    ml_loaded = ct.models.MLModel(str(pkg_path))

    cosines: List[float] = []
    for i, s in enumerate(test_strings):
        tok = tokenizer(
            s, padding="max_length", truncation=True,
            max_length=MAX_LEN, return_tensors="np",
        )
        out = ml_loaded.predict({
            "input_ids": tok["input_ids"].astype(np.int32),
            "attention_mask": tok["attention_mask"].astype(np.int32),
        })
        # Output name comes back as whatever coremltools assigned; pull
        # the first tensor.
        v = list(out.values())[0].squeeze()
        ref = refs[i]
        cos = float(np.dot(v, ref) / (np.linalg.norm(v) * np.linalg.norm(ref)))
        cosines.append(cos)
        print(f"  CoreML vs sentence-transformers [{i}]: cosine={cos:.6f}  '{s[:60]}'")

    print("\n[probe] summary:")
    print(f"  min cosine:  {min(cosines):.6f}")
    print(f"  max cosine:  {max(cosines):.6f}")
    print(f"  mean cosine: {sum(cosines)/len(cosines):.6f}")
    print(f"  mlpackage:   {pkg_path}")
    print(f"  mlpackage size: {sum(p.stat().st_size for p in pkg_path.rglob('*') if p.is_file()) / 1e6:.1f} MB")

    if all(c >= 0.9999 for c in cosines):
        print("\nVERDICT: ✅ within 1e-4 — CoreML conversion is byte-equivalent for production.")
        return 0
    elif all(c >= 0.999 for c in cosines):
        print("\nVERDICT: ⚠ within 1e-3 — usable but slight drift; investigate FP16 vs FP32 if not already FP32.")
        return 0
    else:
        print("\nVERDICT: ❌ cosines drift > 1e-3 — investigate before swapping production.")
        return 1


if __name__ == "__main__":
    sys.exit(main())

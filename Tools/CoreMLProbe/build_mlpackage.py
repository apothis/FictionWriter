#!/usr/bin/env python3
"""
Production build script — converts AnnaWegmann/Style-Embedding to
a CoreML .mlpackage + bundles the HuggingFace tokenizer files
alongside it, ready to load from Swift's swift-transformers +
Apple's MLModel at runtime.

Outputs to:
    Sources/LoomCore/Resources/StyleEmbedding/
        StyleEmbedding.mlpackage/   (FP16, mlprogram, macOS14+, ANE-eligible)
        tokenizer.json              (fast-tokenizer; required by AutoTokenizer.from)
        tokenizer_config.json       (RobertaTokenizer class + pad/bos/eos)
        config.json                 (RoBERTa model config; optional but bundled)
        README.txt                  (provenance note)

Bundling layout chosen so Swift can do:
    let folder = Bundle.module.url(forResource: "StyleEmbedding",
                                   withExtension: nil)!
    let tokenizer = try await AutoTokenizer.from(modelFolder: folder)
    let model = try MLModel(contentsOf: folder
        .appendingPathComponent("StyleEmbedding.mlpackage"))

Cosine equivalence against the sentence-transformers reference was
de-risked by Tools/CoreMLProbe/probe_wegmann_coreml.py (min 0.999993,
max 0.999998).
"""

from __future__ import annotations

import sys
import shutil
from pathlib import Path

import numpy as np
import torch


MODEL_ID = "AnnaWegmann/Style-Embedding"
MAX_LEN = 128


def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent.parent
    out_dir = repo_root / "Sources" / "LoomCore" / "Resources" / "StyleEmbedding"

    if out_dir.exists():
        print(f"[build] clearing existing {out_dir}", file=sys.stderr)
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    # ---- Bundle tokenizer files ----
    print(f"[build] loading + saving tokenizer for {MODEL_ID}...", file=sys.stderr)
    from transformers import AutoTokenizer, AutoModel

    tokenizer = AutoTokenizer.from_pretrained(MODEL_ID)
    # save_pretrained writes the fast-tokenizer artefacts (tokenizer.json,
    # tokenizer_config.json, special_tokens_map.json, vocab.json, merges.txt).
    # swift-transformers reads tokenizer.json + tokenizer_config.json; the
    # rest are kept for parity with the HF disk layout.
    tokenizer.save_pretrained(out_dir)
    print(f"[build] tokenizer files: {sorted(p.name for p in out_dir.iterdir())}", file=sys.stderr)

    # ---- Build + trace the wrapper module ----
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
            hidden = out.last_hidden_state
            mask = attention_mask.unsqueeze(-1).to(hidden.dtype)
            summed = (hidden * mask).sum(dim=1)
            counts = mask.sum(dim=1).clamp(min=1e-9)
            mean = summed / counts
            normed = torch.nn.functional.normalize(mean, p=2, dim=1)
            return normed

    wrapper = WegmannWrapper(base)
    wrapper.eval()

    example_ids = torch.zeros(1, MAX_LEN, dtype=torch.int32)
    example_mask = torch.ones(1, MAX_LEN, dtype=torch.int32)
    print("[build] tracing wrapper...", file=sys.stderr)
    traced = torch.jit.trace(wrapper, (example_ids, example_mask), strict=False)

    # ---- Convert ----
    print("[build] converting to CoreML (.mlpackage)...", file=sys.stderr)
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

    pkg_path = out_dir / "StyleEmbedding.mlpackage"
    mlmodel.save(str(pkg_path))

    # ---- Provenance note ----
    note = out_dir / "README.txt"
    note.write_text(
        "StyleEmbedding CoreML bundle\n"
        "============================\n"
        f"Source: {MODEL_ID} (HuggingFace)\n"
        "Conversion: Tools/CoreMLProbe/build_mlpackage.py\n"
        "Cosine equivalence vs sentence-transformers: ~0.999996 mean\n"
        "  (probe: Tools/CoreMLProbe/probe_wegmann_coreml.py)\n"
        "Inputs: input_ids[1,128] int32, attention_mask[1,128] int32\n"
        "Output: embedding[1,768] float32 (mean-pooled, L2-normalised)\n"
        "Max sequence length: 128 tokens (longer inputs are truncated\n"
        "  by the Swift client before predict).\n"
    )

    # ---- Size report ----
    total_bytes = sum(p.stat().st_size for p in out_dir.rglob("*") if p.is_file())
    print(f"[build] wrote {out_dir}", file=sys.stderr)
    print(f"[build] total bundle size: {total_bytes / 1e6:.1f} MB", file=sys.stderr)
    for p in sorted(out_dir.iterdir()):
        if p.is_file():
            print(f"  {p.name}: {p.stat().st_size / 1e6:.1f} MB", file=sys.stderr)
        elif p.is_dir():
            sub_bytes = sum(q.stat().st_size for q in p.rglob("*") if q.is_file())
            print(f"  {p.name}/: {sub_bytes / 1e6:.1f} MB", file=sys.stderr)

    return 0


if __name__ == "__main__":
    sys.exit(main())

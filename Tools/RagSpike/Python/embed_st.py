#!/usr/bin/env python3
"""
Parameterized sentence-transformers embed subprocess.

Loads any HuggingFace sentence-transformers-compatible model named via
`--model`, then serves embed requests via stdin/stdout JSON lines.

Production: Phase 5 retrieval embeds References with Wegmann
(`AnnaWegmann/Style-Embedding`), locked by the Phase 8.a §6.1 spike
(see LOOM_SCENE_EXEMPLAR_SPIKE.md §1 — Wegmann beats StyleDistance by
~3× on SFW prose and is the only candidate in the 4-embedder set that
clears the topical baseline cleanly). The SceneExemplarSpike runner
also uses this script to probe alternative embedders.

Spawned by Swift's `PythonEmbeddingClient` with arguments like:

    --model AnnaWegmann/Style-Embedding
    --model StyleDistance/styledistance --trust-remote-code
    --model gabrielloiseau/LUAR-MUD-sentence-transformers

Protocol:

    stdin:  {"text": "She walked into the kitchen."}
    stdout: {"dim": 768, "vec": [0.123, -0.456, ...]}
    or:     {"error": "..."}

Ready signal (emitted once after model load):

    {"ready": true}

For manual sanity:

    echo '{"text":"test"}' | Tools/RagSpike/Python/.venv/bin/python3 \\
        Tools/RagSpike/Python/embed_st.py \\
        --model AnnaWegmann/Style-Embedding
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from typing import Any


READY_LINE = '{"ready": true}'


def _log(msg: str) -> None:
    print(msg, file=sys.stderr, flush=True)


def _emit_error(msg: str) -> None:
    print(json.dumps({"error": msg}), flush=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", required=True, help="HF model id")
    parser.add_argument(
        "--trust-remote-code",
        action="store_true",
        help="Pass trust_remote_code=True to SentenceTransformer (needed for StyleDistance)",
    )
    args = parser.parse_args()

    os.environ.setdefault("TRANSFORMERS_VERBOSITY", "error")
    os.environ.setdefault("HF_HUB_DISABLE_PROGRESS_BARS", "1")
    os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")

    try:
        from sentence_transformers import SentenceTransformer  # noqa: WPS433
    except ImportError as e:
        _emit_error(f"sentence-transformers import failed: {e}")
        return 1

    _log(f"[embed_st] loading {args.model}...")
    try:
        model = SentenceTransformer(
            args.model, trust_remote_code=args.trust_remote_code
        )
    except Exception as e:  # noqa: BLE001
        _emit_error(f"model load failed: {e}")
        return 1

    print(READY_LINE, flush=True)
    _log(f"[embed_st] ready ({args.model})")

    for raw in sys.stdin:
        line = raw.strip()
        if not line:
            continue
        try:
            request = json.loads(line)
        except json.JSONDecodeError as e:
            _emit_error(f"bad JSON on stdin: {e}")
            continue

        text = request.get("text")
        if not isinstance(text, str):
            _emit_error("request missing 'text' field")
            continue

        try:
            vec = model.encode(
                text, normalize_embeddings=True, show_progress_bar=False
            )
            response: dict[str, Any] = {
                "dim": int(vec.shape[0]),
                "vec": [float(x) for x in vec.tolist()],
            }
            print(json.dumps(response), flush=True)
        except Exception as e:  # noqa: BLE001
            _emit_error(f"embed failed: {e}")

    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""
Long-lived StyleDistance embedding subprocess.

Spawned by the Swift `PythonStyleDistanceClient`. Loads the model
once at startup, then serves embed requests via stdin/stdout JSON
line protocol until stdin closes (parent process dies).

Protocol — each line on stdin is a request:

    {"text": "She walked into the kitchen."}

Each line on stdout is a response:

    {"dim": 768, "vec": [0.123, -0.456, ...]}

or, on failure:

    {"error": "model load failed: ..."}

Phase 5 production scope-lock #1 second-take per
[`LOOM_MLX_PORT_SPIKE.md`](../../../LOOM_MLX_PORT_SPIKE.md) §12 —
pivoted from in-Swift MLX to bundled-venv Python subprocess after
discovering the user's machine has CLT only (no `metal` compiler).
This script uses the same `sentence-transformers` path as the
original spike, which already validated against PyTorch baseline at
cosine 1.000000 (§8).

Run by the Swift client; no direct CLI use intended. For manual
sanity testing:

    echo '{"text":"test"}' | Tools/RagSpike/Python/.venv/bin/python3 \\
        Tools/RagSpike/Python/embed_subprocess.py
"""

from __future__ import annotations

import json
import os
import sys
from typing import Any


READY_LINE = '{"ready": true}'


def _log(msg: str) -> None:
    """Write a status line to stderr — not consumed by the Swift
    client's stdout reader, so safe for unstructured diagnostics."""
    print(msg, file=sys.stderr, flush=True)


def main() -> int:
    # Suppress sentence-transformers + huggingface_hub progress logs
    # so they don't pollute stderr.
    os.environ.setdefault("TRANSFORMERS_VERBOSITY", "error")
    os.environ.setdefault("HF_HUB_DISABLE_PROGRESS_BARS", "1")

    try:
        from sentence_transformers import SentenceTransformer  # noqa: WPS433
    except ImportError as e:
        _emit_error(f"sentence-transformers import failed: {e}")
        return 1

    _log("[embed-subprocess] loading StyleDistance/styledistance...")
    try:
        model = SentenceTransformer(
            "StyleDistance/styledistance", trust_remote_code=True
        )
    except Exception as e:  # noqa: BLE001
        _emit_error(f"model load failed: {e}")
        return 1

    # Signal to the parent that the model is loaded + we're ready to
    # accept requests. The Swift client reads this line and unblocks
    # its `embed()` callers.
    print(READY_LINE, flush=True)
    _log("[embed-subprocess] ready")

    # Per-line request loop until stdin closes.
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


def _emit_error(msg: str) -> None:
    print(json.dumps({"error": msg}), flush=True)


if __name__ == "__main__":
    sys.exit(main())

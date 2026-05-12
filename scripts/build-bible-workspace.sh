#!/usr/bin/env bash
# Builds the Bible Workspace WKWebView bundle (Phase 4.5).
#
# Output: web/bible-workspace/dist/ — bundled by SPM as a LoomCore
# resource (see Package.swift). build.sh calls this as a pre-step
# before `swift build`.
#
# Dependencies: bun (install via `brew install oven-sh/bun/bun` or
# `curl -fsSL https://bun.sh/install | bash`). The script bails
# loud if bun is missing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUNDLE_DIR="$REPO_ROOT/web/bible-workspace"

if ! command -v bun >/dev/null 2>&1; then
  echo "ERROR: bun is not installed. Install via:"
  echo "  brew install oven-sh/bun/bun"
  echo "or:"
  echo "  curl -fsSL https://bun.sh/install | bash"
  echo ""
  echo "See LOOM_BIBLE_WORKSPACE.md §5.5 for context."
  exit 1
fi

cd "$BUNDLE_DIR"

# Install only when node_modules is missing or lockfile has changed.
# This keeps the common case (rebuild after a TS edit) fast — ~0.5s
# build vs ~5s+ if `bun install` runs unnecessarily.
if [ ! -d node_modules ] || [ "bun.lockb" -nt "node_modules" ]; then
  echo "[bible-workspace] installing deps (bun install)..."
  bun install --frozen-lockfile
fi

echo "[bible-workspace] building..."
bun run build

# Post-build HTML transform — strip attributes that break WebKit
# under file:// loading:
#   - `crossorigin`: CORS enforced even on file:// URLs, marked
#     scripts silently fail to execute → blank page.
#   - `type="module"`: ES modules don't reliably execute under
#     file:// (no error event, just silent no-op). The Vite config
#     emits IIFE-format JS so the module attribute is wrong anyway.
#
# Belt-and-braces — these stripping passes guarantee the output
# loads in WKWebView regardless of future Vite/Rollup default
# changes.
DIST_HTML="$BUNDLE_DIR/dist/index.html"
if [ -f "$DIST_HTML" ]; then
  # Strip crossorigin + type="module"; add `defer` so the classic
  # script (now in <head>) waits for the body to parse before
  # executing — otherwise main.tsx's `document.getElementById("root")`
  # runs before `<div id="root">` exists. Module scripts had defer
  # semantics implicitly; classic scripts don't.
  sed -i '' \
    -e 's/ crossorigin//g' \
    -e 's/ type="module"//g' \
    -e 's|<script src="\./assets/index.js"></script>|<script src="./assets/index.js" defer></script>|' \
    "$DIST_HTML"
fi

# Sync dist/ into Sources/LoomCore/Resources/BibleWorkspace/ where
# SPM picks it up as a target resource. SPM requires resources to
# live within the target's source tree; web/bible-workspace/dist/
# is outside that tree, so we copy. The copy is gitignored (see
# Sources/LoomCore/.gitignore-resources via the top-level .gitignore).
RESOURCES_DIR="$REPO_ROOT/Sources/LoomCore/Resources/BibleWorkspace"
echo "[bible-workspace] syncing dist/ -> Sources/LoomCore/Resources/BibleWorkspace/"
rm -rf "$RESOURCES_DIR"
mkdir -p "$RESOURCES_DIR"
cp -R "$BUNDLE_DIR/dist/." "$RESOURCES_DIR/"

echo "[bible-workspace] ready"

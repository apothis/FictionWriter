#!/usr/bin/env bash
# Builds Loom's two WKWebView bundles (Phase 4.5 + Planned Project):
#   - the Bible Workspace        -> Sources/LoomCore/Resources/BibleWorkspace/
#   - the Planned Project wizard -> Sources/LoomCore/Resources/PlannedProject/
#
# Both are bundled by SPM as LoomCore resources (see Package.swift).
# build.sh calls this as a pre-step before `swift build`.
#
# IIFE output can't code-split across multiple inputs, so each bundle
# is a separate `vite build` invocation selected by the LOOM_BUNDLE
# env var (see vite.config.ts).
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
if [ ! -d node_modules ] || [ "bun.lockb" -nt "node_modules" ]; then
  echo "[bible-workspace] installing deps (bun install)..."
  bun install --frozen-lockfile
fi

# Post-build HTML transform — strip attributes that break WebKit
# under file:// loading:
#   - `crossorigin`: CORS enforced even on file:// URLs, marked
#     scripts silently fail to execute -> blank page.
#   - `type="module"`: ES modules don't reliably execute under
#     file:// (no error event, just silent no-op). The Vite config
#     emits IIFE-format JS so the module attribute is wrong anyway.
# Adds `defer` so the classic script waits for the body to parse
# (module scripts had defer semantics implicitly; classic don't).
# Args: <html-path> <js-name>
postprocess_html() {
  local html="$1" js="$2"
  if [ -f "$html" ]; then
    sed -i '' \
      -e 's/ crossorigin//g' \
      -e 's/ type="module"//g' \
      -e "s|<script src=\"\./assets/${js}.js\"></script>|<script src=\"./assets/${js}.js\" defer></script>|" \
      "$html"
  fi
}

# Sync a built dist/ into the SPM resource tree. SPM requires
# resources to live within the target's source tree; the dist dirs
# are outside it, so we copy. The copies are gitignored.
# Args: <dist-dir> <resource-subdir>
sync_resources() {
  local dist="$1" subdir="$2"
  local dest="$REPO_ROOT/Sources/LoomCore/Resources/$subdir"
  echo "[bible-workspace] syncing $dist -> Sources/LoomCore/Resources/$subdir/"
  rm -rf "$dest"
  mkdir -p "$dest"
  cp -R "$BUNDLE_DIR/$dist/." "$dest/"
}

# --- Bible Workspace bundle ---
echo "[bible-workspace] building Bible Workspace..."
bun run build
postprocess_html "$BUNDLE_DIR/dist/index.html" "index"
sync_resources "dist" "BibleWorkspace"

# --- Planned Project wizard bundle ---
echo "[bible-workspace] building Planned Project wizard..."
LOOM_BUNDLE=plannedProject bun run build
postprocess_html "$BUNDLE_DIR/dist-planned/plannedProject.html" "plannedProject"
sync_resources "dist-planned" "PlannedProject"

# --- Project-tools bundle (scene framing + anti-slop) ---
echo "[bible-workspace] building Project-tools bundle..."
LOOM_BUNDLE=projectTools bun run build
postprocess_html "$BUNDLE_DIR/dist-tools/projectTools.html" "projectTools"
sync_resources "dist-tools" "ProjectTools"

# --- In-app Help bundle (User Help + Technical Reference books) ---
echo "[bible-workspace] building Help bundle..."
LOOM_BUNDLE=help bun run build
postprocess_html "$BUNDLE_DIR/dist-help/help.html" "help"
sync_resources "dist-help" "Help"

echo "[bible-workspace] ready"

#!/bin/bash
set -e

APP_NAME="Loom"
APP_DIR="$APP_NAME.app"

# Phase 4.5 — build the Bible Workspace WKWebView bundle before the
# Swift compile. SPM bundles its dist/ output as a LoomCore resource
# (see Package.swift). If bun is missing or the build fails, this
# bails loud rather than letting Swift produce an incomplete app.
"$(dirname "$0")/scripts/build-bible-workspace.sh"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

swift build -c release --product "$APP_NAME"

BIN_DIR=$(swift build -c release --product "$APP_NAME" --show-bin-path)
cp "$BIN_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp Info.plist "$APP_DIR/Contents/Info.plist"

# SwiftPM emits per-target resource bundles (e.g. Loom_LoomCore.bundle) next
# to the binary when targets declare resources. Copy them adjacent to the
# binary in Contents/Resources so Bundle.module finds them when launching
# Loom.app from Finder. Phase 1 has no bundled resources yet; this loop is
# a no-op until LoomCore declares one.
shopt -s nullglob
for bundle in "$BIN_DIR"/*.bundle; do
    cp -R "$bundle" "$APP_DIR/Contents/Resources/"
done
shopt -u nullglob

# Prefer a stable self-signed identity over ad-hoc so macOS TCC grants
# (Local Network, etc.) survive rebuilds — ad-hoc keys TCC off the
# CDHash, which churns every build. See scripts/create-signing-identity.sh
# to provision the identity once.
SIGN_IDENTITY="Loom Local"
# No `-v` — self-signed certs are reported "untrusted" by find-identity
# but codesign still accepts them. Listing without -v matches our cert.
if security find-identity -p codesigning 2>/dev/null \
        | grep -q "\"$SIGN_IDENTITY\""; then
    codesign --force --sign "$SIGN_IDENTITY" "$APP_DIR"
else
    codesign --force --sign - "$APP_DIR"
    echo "NOTE: signed ad-hoc. Run scripts/create-signing-identity.sh"
    echo "      once to provision a stable identity — otherwise the"
    echo "      Local Network grant will be revoked on every rebuild."
fi

echo "Built $APP_DIR"

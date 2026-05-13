#!/bin/bash
#
# Create a stable self-signed code-signing identity for local Loom
# builds. macOS TCC (Local Network, Camera, etc.) keys its grants off
# the app's designated code requirement, which for an ad-hoc signed app
# is derived from the CDHash — so every rebuild revokes the grant.
# Signing with a stable cert identity keeps the designated requirement
# stable across rebuilds, so the Local Network permission you granted
# once stays granted.
#
# Idempotent — re-running is a no-op if the identity already exists.
# Adds the identity to the login keychain.

set -e

IDENTITY="Loom Local"
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# NB: no `-v` here — a self-signed cert has no trust chain so it's
# reported "untrusted" by find-identity -v, but codesign still accepts
# it for local signing. Match on the policy-listed identities instead.
if security find-identity -p codesigning "$LOGIN_KEYCHAIN" 2>/dev/null \
        | grep -q "\"$IDENTITY\""; then
    echo "Code-signing identity '$IDENTITY' already exists. Nothing to do."
    exit 0
fi

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

# OpenSSL config asking for a self-signed cert with codeSigning EKU.
# The basicConstraints CA:false + critical keyUsage + critical
# extendedKeyUsage = codeSigning are the bits codesign actually
# requires to accept the cert.
cat > "$TMP/cert.conf" <<EOF
[req]
distinguished_name = req_dn
prompt             = no
x509_extensions    = v3_ext

[req_dn]
CN = $IDENTITY

[v3_ext]
basicConstraints       = critical, CA:false
keyUsage               = critical, digitalSignature
extendedKeyUsage       = critical, codeSigning
subjectKeyIdentifier   = hash
EOF

openssl genrsa -out "$TMP/key.pem" 2048 2>/dev/null
openssl req -new -x509 \
    -key "$TMP/key.pem" \
    -out "$TMP/cert.pem" \
    -days 3650 \
    -config "$TMP/cert.conf" 2>/dev/null

# -legacy forces the older PBE-SHA1 + 3DES that macOS's PKCS12 parser
# accepts. OpenSSL 3.x defaults to AES-256 / PBE2 / SHA-256, which
# `security import` rejects with "MAC verification failed".
PKCS12_PW="loom"
openssl pkcs12 -export \
    -legacy \
    -inkey "$TMP/key.pem" \
    -in    "$TMP/cert.pem" \
    -name  "$IDENTITY" \
    -out   "$TMP/identity.p12" \
    -password "pass:$PKCS12_PW" 2>/dev/null

# -T /usr/bin/codesign explicitly grants codesign access to the private
# key without an interactive prompt on first use; we'd otherwise hit
# the "codesign wants to use a key" dialog every build.
security import "$TMP/identity.p12" \
    -k "$LOGIN_KEYCHAIN" \
    -P "$PKCS12_PW" \
    -T /usr/bin/codesign \
    -T /usr/bin/security

# Without this, codesign still prompts on first use even with -T above
# (Sierra+ behaviour — partition lists). Best-effort: skip silently if
# we can't unlock without a password.
if security unlock-keychain -p "" "$LOGIN_KEYCHAIN" >/dev/null 2>&1; then
    security set-key-partition-list \
        -S "apple-tool:,apple:,codesign:" \
        -s -k "" "$LOGIN_KEYCHAIN" >/dev/null 2>&1 || true
fi

echo "Created code-signing identity '$IDENTITY' in login keychain."
echo "Next build will sign with this identity; Local Network grant will"
echo "now survive rebuilds."

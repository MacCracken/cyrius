#!/bin/sh
# ci.sh — install Cyrius from latest release for CI pipelines
# Usage: sh scripts/ci.sh [version]
# Pulls the release tarball, extracts to ~/.cyrius, adds to PATH.

set -e

VERSION="${1:-$(curl -sf https://api.github.com/repos/MacCracken/cyrius/releases/latest | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": "//;s/".*//')}"

if [ -z "$VERSION" ]; then
    echo "error: could not determine version"
    exit 1
fi

CYRIUS_HOME="${CYRIUS_HOME:-$HOME/.cyrius}"
TARBALL="cyrius-${VERSION}-x86_64-linux.tar.gz"
URL="https://github.com/MacCracken/cyrius/releases/download/${VERSION}/${TARBALL}"

echo "=== Cyrius CI Setup ==="
echo "  version: $VERSION"
echo "  target:  $CYRIUS_HOME"

mkdir -p "$CYRIUS_HOME/bin"

echo "  fetching $TARBALL..."
curl -sfL "$URL" -o "/tmp/$TARBALL" || {
    echo "error: failed to download $URL"
    exit 1
}

# CVE-21 (v6.2.30): verify the published .sha256 sidecar fail-closed before
# extracting. Pre-fix, ci.sh curl'd + untarred with NO integrity check at all —
# a CI pipeline installing an unverified toolchain is the supply-chain hole the
# sovereignty stance exists to remove. macOS runners ship `shasum`, not
# `sha256sum`, so try both.
echo "  verifying checksum..."
curl -sfL "${URL}.sha256" -o "/tmp/${TARBALL}.sha256" || {
    echo "error: could not fetch ${URL}.sha256 — refusing to install unverified tarball"
    rm -f "/tmp/$TARBALL"
    exit 1
}
(
    cd /tmp
    if command -v sha256sum > /dev/null 2>&1; then
        sha256sum -c "${TARBALL}.sha256" > /dev/null 2>&1
    elif command -v shasum > /dev/null 2>&1; then
        shasum -a 256 -c "${TARBALL}.sha256" > /dev/null 2>&1
    else
        echo "error: no SHA-256 tool (sha256sum/shasum) — cannot verify" >&2
        exit 1
    fi
) || {
    echo "error: checksum mismatch (or no verifier) for $TARBALL — aborting"
    rm -f "/tmp/$TARBALL" "/tmp/${TARBALL}.sha256"
    exit 1
}
echo "  checksum verified"
rm -f "/tmp/${TARBALL}.sha256"

tar xzf "/tmp/$TARBALL" -C "$CYRIUS_HOME"
rm -f "/tmp/$TARBALL"

# Symlink binaries
for bin in "$CYRIUS_HOME"/versions/"$VERSION"/bin/*; do
    [ -f "$bin" ] && ln -sf "$bin" "$CYRIUS_HOME/bin/$(basename "$bin")"
done
echo "$VERSION" > "$CYRIUS_HOME/current"

# Verify
if [ -x "$CYRIUS_HOME/bin/cycc" ]; then
    echo "  cycc:  ok"
else
    echo "  error: cycc not found"
    exit 1
fi

if [ -x "$CYRIUS_HOME/bin/cyrius" ]; then
    echo "  cyrius: $("$CYRIUS_HOME/bin/cyrius" version 2>/dev/null || echo 'ok')"
else
    echo "  error: cyrius not found"
    exit 1
fi

echo ""
echo "Add to PATH:"
echo "  export PATH=\"$CYRIUS_HOME/bin:\$PATH\""

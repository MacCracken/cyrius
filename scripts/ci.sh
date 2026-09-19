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

# ⛔ CVE-44 (v6.6.6) — EVERY downloaded artifact lands in a PRIVATE directory, never a fixed
# /tmp name. This script used /tmp/$TARBALL, /tmp/$TARBALL.sha256, /tmp/SHA256SUMS,
# /tmp/SHA256SUMS.sig, /tmp/cyrius-release.pub and /tmp/cyrius_tsum — six predictable paths, in
# a world-writable directory, holding the tarball being installed AND the three inputs to the
# signature check that is supposed to authorise it. Any local user could create those names
# first (the sticky bit stops them DELETING another user's file, not creating one that does not
# exist yet), own the resulting files, and rewrite them between the download and the verify, or
# between the verify and `tar xzf` — including `cyrius-release.pub`, so the signature would be
# checked against THEIR key. A verification whose inputs another user can swap is not a
# verification. mktemp -d is 0700 and unpredictable, so there is nothing to pre-create and
# nothing to swap. CHANGELOG [6.6.6]
TD=$(mktemp -d) && [ -d "$TD" ] || { echo "error: could not create a private temp directory (TMPDIR=${TMPDIR:-/tmp}) — refusing to stage a release in a shared one" >&2; exit 1; }
chmod 700 "$TD" 2>/dev/null || true
trap 'rm -rf "$TD"' EXIT
trap 'rm -rf "$TD"; exit 1' INT TERM HUP

echo "=== Cyrius CI Setup ==="
echo "  version: $VERSION"
echo "  target:  $CYRIUS_HOME"

mkdir -p "$CYRIUS_HOME/bin"

echo "  fetching $TARBALL..."
curl -sfL "$URL" -o "$TD/$TARBALL" || {
    echo "error: failed to download $URL"
    exit 1
}

# CVE-21 (v6.2.30): verify the published .sha256 sidecar fail-closed before
# extracting. Pre-fix, ci.sh curl'd + untarred with NO integrity check at all —
# a CI pipeline installing an unverified toolchain is the supply-chain hole the
# sovereignty stance exists to remove. macOS runners ship `shasum`, not
# `sha256sum`, so try both.
echo "  verifying checksum..."
curl -sfL "${URL}.sha256" -o "$TD/${TARBALL}.sha256" || {
    echo "error: could not fetch ${URL}.sha256 — refusing to install unverified tarball"
    exit 1
}
(
    cd "$TD"
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
    exit 1
}
echo "  checksum verified"
rm -f "$TD/${TARBALL}.sha256"

# CVE-13 (v6.2.31): if a trusted cyrsign is present (a prior install on PATH /
# in $CYRIUS_HOME/bin — the upgrade path), also verify the sovereign Ed25519
# signature over SHA256SUMS against the pinned public key, then confirm this
# tarball matches the SIGNED manifest line. Fail-closed. A fresh CI box with no
# prior cyrsign / an unsigned release falls back to the HTTPS + .sha256 floor.
CYRIUS_RELEASE_PUBKEY="adbde6b11ccf8d86dc760387fa7f4dfbe3942fa318e459fb6e62d1536e254008"
BASE="https://github.com/MacCracken/cyrius/releases/download/${VERSION}"
_cs=""
if command -v cyrsign > /dev/null 2>&1; then _cs="cyrsign"
elif [ -x "$CYRIUS_HOME/bin/cyrsign" ]; then _cs="$CYRIUS_HOME/bin/cyrsign"; fi
if [ -n "$_cs" ] && curl -sfL "${BASE}/SHA256SUMS" -o "$TD/SHA256SUMS" 2>/dev/null \
        && curl -sfL "${BASE}/SHA256SUMS.sig" -o "$TD/SHA256SUMS.sig" 2>/dev/null; then
    printf '%s\n' "$CYRIUS_RELEASE_PUBKEY" > "$TD/cyrius-release.pub"
    grep "  ${TARBALL}$" "$TD/SHA256SUMS" > "$TD/cyrius_tsum" 2>/dev/null || true
    if "$_cs" verify "$TD/SHA256SUMS" "$TD/SHA256SUMS.sig" "$TD/cyrius-release.pub" > /dev/null 2>&1 \
            && [ -s "$TD/cyrius_tsum" ] \
            && ( cd "$TD" && { sha256sum -c cyrius_tsum > /dev/null 2>&1 || shasum -a 256 -c cyrius_tsum > /dev/null 2>&1; } ); then
        echo "  signature verified (Ed25519)"
    else
        echo "error: release signature verification FAILED for $VERSION — aborting" >&2
        exit 1
    fi
    rm -f "$TD/SHA256SUMS" "$TD/SHA256SUMS.sig" "$TD/cyrius-release.pub" "$TD/cyrius_tsum"
else
    echo "  signature check skipped (no prior cyrsign / unsigned release)"
fi

tar xzf "$TD/$TARBALL" -C "$CYRIUS_HOME"
rm -f "$TD/$TARBALL"

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

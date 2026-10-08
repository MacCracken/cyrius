#!/bin/sh
# ci.sh — install Cyrius from latest release for CI pipelines
# Usage: sh scripts/ci.sh [version]
# Pulls the release tarball, extracts to ~/.cyrius, adds to PATH.

set -e

# 6.6.20 (SEC-07): whether the version came from the caller or from the "latest" lookup — an
# auto-resolved version older than the first signed release is refused below.
_VERSION_FROM_LATEST=0
[ -n "${1:-}" ] || _VERSION_FROM_LATEST=1
VERSION="${1:-$(curl -sf https://api.github.com/repos/MacCracken/cyrius/releases/latest | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": "//;s/".*//')}"

if [ -z "$VERSION" ]; then
    echo "error: could not determine version"
    exit 1
fi

CYRIUS_HOME="${CYRIUS_HOME:-$HOME/.cyrius}"
TARBALL="cyrius-${VERSION}-x86_64-linux.tar.gz"
URL="https://github.com/MacCracken/cyrius/releases/download/${VERSION}/${TARBALL}"

# ⛔ CYRIUS-2026-0007 (v6.6.6) — EVERY downloaded artifact lands in a PRIVATE directory, never a fixed
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

# the release-integrity hardening item (v6.2.30): verify the published .sha256 sidecar fail-closed before
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

# the release-signing hardening item (v6.2.31): if a trusted cyrsign is present (a prior install on PATH /
# in $CYRIUS_HOME/bin — the upgrade path), also verify the sovereign Ed25519
# signature over SHA256SUMS against the pinned public key, then confirm this
# tarball matches the SIGNED manifest line. Fail-closed. A fresh CI box with no
# prior cyrsign / an unsigned release falls back to the HTTPS + .sha256 floor.
CYRIUS_RELEASE_PUBKEY="adbde6b11ccf8d86dc760387fa7f4dfbe3942fa318e459fb6e62d1536e254008"
BASE="https://github.com/MacCracken/cyrius/releases/download/${VERSION}"
# ⛔ 6.6.20 (SEC-07): a trusted verifier that cannot fetch the signature is a REFUSAL at or above
# the first signed release. This block skipped whenever SHA256SUMS or its .sig failed to download,
# so with cyrsign on PATH a tampered 6.6.19 served with its tarball + .sha256 and no SHA256SUMS
# installed ("signature check skipped"). Every release since 6.2.31 is signed (release.yml refuses
# to publish one that is not), so the missing pair is a stripped signature. Same rule, same
# constant, as scripts/install.sh — tests/gates/toolchain/install_signature_required.sh holds
# them in step. CHANGELOG [6.6.20]
_FIRST_SIGNED_RELEASE="6.2.31"
# _predates_signing V → true iff V is a WELL-FORMED release version (three decimal fields, no
# leading zero) strictly below the first signed release; anything else must verify.
_predates_signing() {
    case "$1" in ''|*[!0-9.]*|.*|*.|*..*|0[0-9]*|*.0[0-9]*) return 1 ;; esac
    case "$1" in *.*.*.*) return 1 ;; *.*.*) ;; *) return 1 ;; esac
    [ "$1" != "$_FIRST_SIGNED_RELEASE" ] || return 1
    [ "$(printf '%s\n%s\n' "$1" "$_FIRST_SIGNED_RELEASE" | sort -t. -k1,1n -k2,2n -k3,3n | head -1)" = "$1" ]
}
_cs=""
if command -v cyrsign > /dev/null 2>&1; then _cs="cyrsign"
elif [ -x "$CYRIUS_HOME/bin/cyrsign" ]; then _cs="$CYRIUS_HOME/bin/cyrsign"; fi
_sig_fetched=0
if [ -n "$_cs" ] && curl -sfL "${BASE}/SHA256SUMS" -o "$TD/SHA256SUMS" 2>/dev/null \
        && curl -sfL "${BASE}/SHA256SUMS.sig" -o "$TD/SHA256SUMS.sig" 2>/dev/null; then
    _sig_fetched=1
fi
if [ -n "$_cs" ] && [ "$_sig_fetched" -eq 0 ]; then
    if _predates_signing "$VERSION" && [ "$_VERSION_FROM_LATEST" != "1" ]; then
        echo "  signature check skipped (pre-signing release $VERSION, requested by name)"
    else
        if _predates_signing "$VERSION"; then
            _sr_why="the latest release resolved to $VERSION, which predates release signing ($_FIRST_SIGNED_RELEASE) — a downgrade to a build nothing can verify"
        else
            _sr_why="every Cyrius release since $_FIRST_SIGNED_RELEASE is signed and a trusted cyrsign is present, but ${VERSION}'s SHA256SUMS / SHA256SUMS.sig could not be fetched — a stripped signature, not an unsigned release"
        fi
        if [ "${CYRIUS_ALLOW_UNSIGNED:-0}" = "1" ]; then
            echo "  signature required but absent: $_sr_why — allowed via CYRIUS_ALLOW_UNSIGNED=1 (NOT recommended)"
        else
            echo "error: refusing UNSIGNED $VERSION: $_sr_why. Retry (a network failure looks the same), or set CYRIUS_ALLOW_UNSIGNED=1 only if you genuinely trust this unsigned build." >&2
            exit 1
        fi
    fi
elif [ "$_sig_fetched" -eq 1 ]; then
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
    echo "  signature check skipped (no prior cyrsign on this machine)"
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

#!/bin/sh
# funcgate-stage.sh — stage a throwaway CYRIUS_HOME for the functional gate.
#
# Lays out the exact install structure `cyrius lib sync` / the wrapper expect
# (versions/<v>/{bin,lib} + current + bin/lib symlinks), copied straight from a
# repo checkout's freshly-built binaries + lib/. Portable (cp/ln/tr only) so it
# runs identically on x86 Linux, aarch64 Linux, and the AGNOS container — no
# tool-rebuild, no sha256sum dependency. For the macOS funcgate the real release
# tarball + install.sh is used instead (that path tests the shipped artifact).
#
# Usage: funcgate-stage.sh <cycc-bin> <cyrius-bin> <CYRIUS_HOME>
# Run from a cyrius repo root (reads VERSION + lib/).
set -e

CYCC="${1:?usage: funcgate-stage.sh <cycc-bin> <cyrius-bin> <CYRIUS_HOME>}"
CYRIUS="${2:?cyrius wrapper bin}"
H="${3:?CYRIUS_HOME}"
V="$(tr -d '[:space:]' < VERSION)"

# v6.6.2 — REFUSE TO WIPE A LIVE TOOLCHAIN STORE.
# This script's whole contract is "stage a THROWAWAY CYRIUS_HOME", and the next
# line is an unguarded `rm -rf "$H"`. Pointed at $HOME/.cyrius it destroys every
# installed version — which is exactly what happened on 2026-09-07, taking the
# entire versions/ store with it and leaving 104 pinned sibling repos unable to
# run any `cyrius` verb. The only protection until now was a sentence in
# docs/development/handoff.md, and a sentence is not a guard.
# Refuse when the target is the user's real store, or any tree that already holds
# more than one installed version. CYRIUS_FUNCGATE_ALLOW_LIVE=1 is the deliberate
# override; a temp-dir target needs no override at all.
_fg_abort() { echo "funcgate-stage: REFUSING to rm -rf $1" >&2; echo "  $2" >&2; exit 1; }
if [ "${CYRIUS_FUNCGATE_ALLOW_LIVE:-0}" != "1" ]; then
    # Canonicalise without realpath(1) — this runs on the AGNOS container too.
    if [ -d "$H" ]; then _H_ABS="$(cd "$H" 2>/dev/null && pwd -P)" || _H_ABS="$H"
    else _H_ABS="$H"; fi
    case "$_H_ABS" in
        /|"$HOME"|"$HOME"/) _fg_abort "$_H_ABS" "that is / or \$HOME." ;;
    esac
    [ "$_H_ABS" = "${CYRIUS_HOME_REAL:-$HOME/.cyrius}" ] &&
        _fg_abort "$_H_ABS" "that is the live toolchain store. Stage into a temp dir."
    # A tree with 2+ installed versions is a real store no matter where it lives.
    if [ -d "$_H_ABS/versions" ]; then
        _nv=$(ls -1 "$_H_ABS/versions" 2>/dev/null | wc -l | tr -d ' ')
        [ "${_nv:-0}" -gt 1 ] &&
            _fg_abort "$_H_ABS" "it holds $_nv installed versions. Set CYRIUS_FUNCGATE_ALLOW_LIVE=1 if you truly mean it."
    fi
fi

rm -rf "$H"
mkdir -p "$H/versions/$V/bin" "$H/versions/$V/lib"
cp "$CYCC"   "$H/versions/$V/bin/cycc"
cp "$CYRIUS" "$H/versions/$V/bin/cyrius"
[ -f scripts/cyriusly ] && cp scripts/cyriusly "$H/versions/$V/bin/" || true

# v6.2.40: `cyrius init` / `cyrius port` are the native cyrius-init binary
# (no bash shims). Build it with the staged cycc so the functional gate
# exercises the shipped scaffolder, not a stale dev copy. Fail loud — a
# missing scaffolder must red the gate, not silently skip (the macOS-rot
# placebo lesson).
cat programs/cyrius-init.cyr | "$CYCC" > "$H/versions/$V/bin/cyrius-init"

# Remaining helper scripts the wrapper still shells out to.
# Same lookup as install.sh: scripts/shims/ first, then flat scripts/.
for s in cyrius-repl.sh cyrius-watch.sh cyrius-prompt-info; do
    if   [ -f "scripts/shims/$s" ]; then cp "scripts/shims/$s" "$H/versions/$V/bin/"
    elif [ -f "scripts/$s" ];       then cp "scripts/$s"       "$H/versions/$V/bin/"
    fi
done
chmod +x "$H/versions/$V/bin"/*

# lib snapshot — cp -L dereferences any `cyrius deps` symlinks so the home is
# self-contained (mirrors install.sh's cp -L). lib/ is flat .cyr files.
cp -RL lib/. "$H/versions/$V/lib/"

# init scaffolding templates — `cyrius init` reads these from
# versions/<v>/programs/cyrius-init-templates (install.sh:296). Without them
# init fails, so the gate's very first step would falsely red on staging, not
# the toolchain.
if [ -d programs/cyrius-init-templates ]; then
    mkdir -p "$H/versions/$V/programs"
    cp -r programs/cyrius-init-templates "$H/versions/$V/programs/"
fi

echo "$V" > "$H/current"
echo "$V" > "$H/versions/$V/VERSION"
rm -rf "$H/bin" "$H/lib"
ln -sf "versions/$V/bin" "$H/bin"
ln -sf "versions/$V/lib" "$H/lib"

echo "staged CYRIUS_HOME=$H for $V ($(ls "$H/versions/$V/lib" | wc -l) lib files)"

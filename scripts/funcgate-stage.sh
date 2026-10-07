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
# docs/development/handoff.md (archived 6.6.20; that sentence is in its git history), and a sentence is not a guard.
# Refuse when the target is the user's real store, or any tree that already holds
# more than one installed version. CYRIUS_FUNCGATE_ALLOW_LIVE=1 is the deliberate
# override; a temp-dir target needs no override at all.
_fg_abort() { echo "funcgate-stage: REFUSING to rm -rf $1" >&2; echo "  $2" >&2; exit 1; }
# The physical path of directory $1 whether or not it exists yet: its deepest EXISTING
# ancestor, resolved with `cd && pwd -P`, plus the missing tail. A copy of install.sh's
# `_rs_real` (no realpath(1) — this runs on the AGNOS container too). Never fails.
_fg_real() {
    _rp="$1"
    while [ "$_rp" != "/" ] && [ "${_rp%/}" != "$_rp" ]; do _rp="${_rp%/}"; done
    [ -n "$_rp" ] || _rp="/"
    _rtail=""
    while [ ! -d "$_rp" ]; do
        _rtail="/$(basename "$_rp")$_rtail"
        _rp="$(dirname "$_rp")"
    done
    _rbase="$( (cd "$_rp" 2>/dev/null && pwd -P) || true )"
    [ -n "$_rbase" ] || _rbase="$_rp"
    _rout="${_rbase%/}$_rtail"
    [ -n "$_rout" ] || _rout="/"
    printf '%s\n' "$_rout"
}
# True when $1 is $2 or lies inside it (both physical paths, $2 != "/").
_fg_within() { case "$1/" in "$2"/*) return 0 ;; esac; return 1; }
if [ "${CYRIUS_FUNCGATE_ALLOW_LIVE:-0}" != "1" ]; then
    # EVERY side of every compare is a physical path. Comparing `pwd -P` of the target with the
    # raw strings $HOME / $HOME/.cyrius let a symlinked HOME (Fedora Atomic, FreeBSD: /home is a
    # link), a trailing slash on HOME, or a symlinked target straight past the guard; and an
    # equality test missed a PARENT of HOME and the repo root. CHANGELOG [6.6.20]
    # `_fg_real` resolves only the EXISTING prefix; a `..` after a directory that does not exist
    # yet would be compared as a plain string, then `mkdir -p` makes the directory and the
    # restage's `rm -rf "$H/bin"` follows the `..` into whatever it names. So refuse `.` / `..`.
    case "/$H/" in
        */../*|*/./*) _fg_abort "$H" "a target with . or .. components cannot be checked — spell it plainly." ;;
    esac
    _H_R="$(_fg_real "$H")"
    _HOME_R="$(_fg_real "${HOME:-/}")"
    _ST_R="$(_fg_real "${CYRIUS_HOME_REAL:-${HOME:-/}/.cyrius}")"
    _CWD_R="$(pwd -P)"
    [ "$_H_R" = "/" ] && _fg_abort "$_H_R" "that is /."
    _fg_within "$_HOME_R" "$_H_R" &&
        _fg_abort "$_H_R" "that is \$HOME ($_HOME_R) or a directory holding it."
    _fg_within "$_ST_R" "$_H_R" &&
        _fg_abort "$_H_R" "that is the live toolchain store ($_ST_R) or a directory holding it. Stage into a temp dir."
    _fg_within "$_CWD_R" "$_H_R" &&
        _fg_abort "$_H_R" "that is the working directory ($_CWD_R) or a directory holding it — the source tree."
    # A tree with 2+ installed versions is a real store no matter where it lives.
    if [ -d "$_H_R/versions" ]; then
        _nv=$(ls -1 "$_H_R/versions" 2>/dev/null | wc -l | tr -d ' ')
        [ "${_nv:-0}" -gt 1 ] &&
            _fg_abort "$_H_R" "it holds $_nv installed versions. Set CYRIUS_FUNCGATE_ALLOW_LIVE=1 if you truly mean it."
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

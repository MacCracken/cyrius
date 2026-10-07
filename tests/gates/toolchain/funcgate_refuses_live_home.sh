#!/bin/sh
# Gate: `funcgate-stage.sh` REFUSES to `rm -rf` a live toolchain store (v6.6.2).
#
# THE INCIDENT (2026-09-07). `scripts/funcgate-stage.sh` stages a THROWAWAY CYRIUS_HOME
# for the functional gate, and its third line of real work was a bare, unguarded
# `rm -rf "$H"`. Pointed at `$HOME/.cyrius` it took the ENTIRE installed store with it —
# every `versions/<v>` directory on the box. `~/.cyrius/versions` was left holding only
# the two versions reinstalled afterwards (6.6.0, 6.6.1), while 104 of the 126
# `cyrius.cyml` manifests under ~/Repos pin a version that no longer existed locally.
# `_try_redirect_to_pinned()` fires before command dispatch, so those repos could not run
# ANY cyrius verb — not `build`, not `lint`, not `--version`.
#
# ⚠ THE ONLY PROTECTION WAS A SENTENCE. `docs/development/handoff.md` (archived 6.6.20) carried
# "Never pass $HOME/.cyrius as a staging target to funcgate-stage.sh" as a standing rule.
# A rule in a document is not a guard: it protects only the reader who happens to have
# read it, and this tree's own history says handoff.md sat stale for thirty-eight
# releases at a stretch. The script now refuses; that is what this gate pins.
#
# ⭐ AXIS 2 IS THE LOAD-BEARING ONE. Guarding only the literal path `$HOME/.cyrius` would
# be defeated by any store staged elsewhere ($CYRIUS_HOME exported to a scratch tree that
# later became real, a second account layout, a container mount). The structural test is
# "does this tree already hold more than one installed version" — that is what makes a
# directory a STORE rather than a staging area, wherever it happens to live.
#
# Axis 4 is the anti-vacuous one: a guard that refuses everything would pass axes 1-3 and
# break the functional gate on every CI run. The clean-temp-dir path must still stage.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
STAGE="$ROOT/scripts/funcgate-stage.sh"
WORK=$(mktemp -d) && [ -d "$WORK" ] || { echo "FAIL: funcgate_refuses_live_home: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: funcgate_refuses_live_home: $1"; exit 1; }

[ -f "$STAGE" ] || fail "scripts/funcgate-stage.sh missing"

# The script reads VERSION + lib/ relative to CWD, so every axis runs from the repo root.
cd "$ROOT"

# ── axis 1: target IS the user's live store → refuse, and leave it untouched ─────────
# HOME is redirected so the axis exercises the real `$HOME/.cyrius` branch without ever
# pointing the script at the actual store on this box. ONE installed version on purpose:
# with two, axis 2's count heuristic refuses first and the `$HOME/.cyrius` compare is never
# reached — a mutation that deleted that compare left this axis green until 6.6.20.
mkdir -p "$WORK/h1/.cyrius/versions/6.5.9"
echo "sentinel" > "$WORK/h1/.cyrius/versions/6.5.9/marker"
if HOME="$WORK/h1" sh "$STAGE" /bin/true /bin/true "$WORK/h1/.cyrius" >"$WORK/o1" 2>&1; then
    fail "axis 1: staging into \$HOME/.cyrius was ALLOWED"
fi
grep -q 'REFUSING to rm -rf' "$WORK/o1" || fail "axis 1: refused but printed no reason"
grep -q 'live toolchain store' "$WORK/o1" || fail "axis 1: wrong refusal reason: $(cat "$WORK/o1")"
[ -f "$WORK/h1/.cyrius/versions/6.5.9/marker" ] || fail "axis 1: store was destroyed anyway"

# ── axis 2: any tree holding 2+ installed versions is a store, wherever it lives ─────
mkdir -p "$WORK/store/versions/6.4.1" "$WORK/store/versions/6.5.0"
echo "sentinel" > "$WORK/store/versions/6.4.1/marker"
if HOME="$WORK/h1" sh "$STAGE" /bin/true /bin/true "$WORK/store" >"$WORK/o2" 2>&1; then
    fail "axis 2: staging into a 2-version store outside \$HOME was ALLOWED"
fi
grep -q 'installed versions' "$WORK/o2" || fail "axis 2: wrong refusal reason"
[ -f "$WORK/store/versions/6.4.1/marker" ] || fail "axis 2: store was destroyed anyway"

# ── axis 3: the deliberate override still works ─────────────────────────────────────
# Someone who genuinely means to restage over a live tree must be able to, or the guard
# becomes something people work around by editing the script.
mkdir -p "$WORK/ovr/versions/6.4.1" "$WORK/ovr/versions/6.5.0"
HOME="$WORK/h1" CYRIUS_FUNCGATE_ALLOW_LIVE=1 sh "$STAGE" /bin/true /bin/true "$WORK/ovr" \
    >"$WORK/o3" 2>&1 || fail "axis 3: override did not stage: $(cat "$WORK/o3")"
[ -d "$WORK/ovr/versions/6.4.1" ] && fail "axis 3: override did not actually replace the tree"

# ── axis 4 (ANTI-VACUOUS): a clean temp target must still stage ──────────────────────
# Without this, "refuse unconditionally" passes axes 1-3 and reds the functional gate on
# every CI run instead.
HOME="$WORK/h1" sh "$STAGE" /bin/true /bin/true "$WORK/fresh" >"$WORK/o4" 2>&1 \
    || fail "axis 4: clean temp target was refused: $(cat "$WORK/o4")"
grep -q '^staged CYRIUS_HOME=' "$WORK/o4" || fail "axis 4: staged but printed no confirmation"
[ -d "$WORK/fresh/versions" ] || fail "axis 4: nothing was staged"
[ -L "$WORK/fresh/bin" ] || fail "axis 4: bin symlink not created"

# ── axes 5-10: every side of the compare is a PHYSICAL path (6.6.20) ─────────────────
# The guard compared `pwd -P` of the target with the RAW strings $HOME and $HOME/.cyrius, so
# any spelling of HOME that is not already physical — a symlinked home (Fedora Atomic and
# FreeBSD link /home), a symlinked parent, a trailing slash — walked straight past it, and an
# equality test never saw a PARENT of HOME or the source tree itself. Each of these deleted
# the tree before the fix. They run from a FAKE repo root (VERSION, lib/, the init source) so
# that a regression in axis 10 wipes a scratch copy, never this checkout.
FR="$WORK/root"
mkdir -p "$FR/lib" "$FR/programs"
echo "6.6.99" > "$FR/VERSION"; echo "# a" > "$FR/lib/a.cyr"; echo "# init" > "$FR/programs/cyrius-init.cyr"
_refuses() { # <axis> <home> <target> <survivor-file>
    if (cd "$FR" && HOME="$2" sh "$STAGE" /bin/true /bin/true "$3") >"$WORK/o$1" 2>&1; then
        fail "axis $1: staging into $3 (HOME=$2) was ALLOWED"
    fi
    grep -q 'REFUSING to rm -rf' "$WORK/o$1" || fail "axis $1: refused but printed no reason"
    [ -f "$4" ] || fail "axis $1: refused, but $4 was destroyed anyway"
}

# axis 5: HOME is a symlink; target "$HOME/" (the trailing slash makes rm -rf follow the link)
mkdir -p "$WORK/s5/hreal/Documents"; echo precious > "$WORK/s5/hreal/Documents/thesis.txt"
ln -s "$WORK/s5/hreal" "$WORK/s5/hlink"
_refuses 5 "$WORK/s5/hlink" "$WORK/s5/hlink/" "$WORK/s5/hreal/Documents/thesis.txt"

# axis 6: HOME is a symlink; target "$HOME/.cyrius", a ONE-version store
mkdir -p "$WORK/s6/hreal/.cyrius/versions/6.6.19"; echo s > "$WORK/s6/hreal/.cyrius/versions/6.6.19/marker"
ln -s "$WORK/s6/hreal" "$WORK/s6/hlink"
_refuses 6 "$WORK/s6/hlink" "$WORK/s6/hlink/.cyrius" "$WORK/s6/hreal/.cyrius/versions/6.6.19/marker"

# axis 7: a symlinked PARENT (home -> var/home, the Fedora Atomic layout); target "$HOME"
mkdir -p "$WORK/s7/var/home/user/Documents"; echo precious > "$WORK/s7/var/home/user/Documents/thesis.txt"
ln -s var/home "$WORK/s7/home"
_refuses 7 "$WORK/s7/home/user" "$WORK/s7/home/user" "$WORK/s7/var/home/user/Documents/thesis.txt"

# axis 8: HOME carries a trailing slash; target "$HOME/.cyrius" spelled from it, one version
mkdir -p "$WORK/s8/h/.cyrius/versions/6.6.19"; echo s > "$WORK/s8/h/.cyrius/versions/6.6.19/marker"
_refuses 8 "$WORK/s8/h/" "$WORK/s8/h//.cyrius" "$WORK/s8/h/.cyrius/versions/6.6.19/marker"

# axis 9: the target is a PARENT of HOME — an equality test never sees it
mkdir -p "$WORK/s9/users/me/Documents"; echo precious > "$WORK/s9/users/me/Documents/thesis.txt"
_refuses 9 "$WORK/s9/users/me" "$WORK/s9/users" "$WORK/s9/users/me/Documents/thesis.txt"

# axis 10: the target is the working directory — the script runs from a repo root, so that
# is the source tree
echo precious > "$FR/precious.src"
_refuses 10 "$WORK/h1" "$FR" "$FR/precious.src"
[ -f "$FR/VERSION" ] || fail "axis 10: refused, but the fake repo root was wiped anyway"

# ── axes 11-12: a `..` after a directory that does not exist yet ─────────────────────
# The resolver walks up to the deepest EXISTING ancestor and copies the missing tail on
# unchanged, so a `..` in that tail was never resolved and the guard compared a string the
# kernel would read differently: `mkdir -p` then creates the missing directory and
# `rm -rf "$H/bin" "$H/lib"` follows the `..` into whatever it names. Neither case deleted
# the target itself (rm -rf of a path through a missing directory is a no-op) — the damage
# is the restage written INTO the tree the `..` lands on. CHANGELOG [6.6.20]
# axis 11: "$HOME/missing/../.cyrius" — a ONE-version live store (so axis 2's count does not
# refuse first); the restage rewrote its `current`, added versions/6.6.99, replaced bin/lib.
mkdir -p "$WORK/s11/h/.cyrius/versions/6.6.19/bin"
echo "6.6.19" > "$WORK/s11/h/.cyrius/current"
ln -s versions/6.6.19/bin "$WORK/s11/h/.cyrius/bin"
_refuses 11 "$WORK/s11/h" "$WORK/s11/h/missing/../.cyrius" "$WORK/s11/h/.cyrius/current"
[ "$(cat "$WORK/s11/h/.cyrius/current")" = "6.6.19" ] || fail "axis 11: refused, but the store's current was rewritten"
[ -e "$WORK/s11/h/.cyrius/versions/6.6.99" ] && fail "axis 11: refused, but a version was staged into the live store"
[ "$(readlink "$WORK/s11/h/.cyrius/bin")" = "versions/6.6.19/bin" ] || fail "axis 11: refused, but the store's bin link was replaced"
# axis 12: "$HOME/missing/.." — that is HOME; the restage deleted $HOME/bin and $HOME/lib.
mkdir -p "$WORK/s12/h/bin"; echo precious > "$WORK/s12/h/bin/tool"
_refuses 12 "$WORK/s12/h" "$WORK/s12/h/missing/.." "$WORK/s12/h/bin/tool"
[ -e "$WORK/s12/h/versions" ] && fail "axis 12: refused, but a store was staged into HOME"

echo "PASS: funcgate_refuses_live_home (12 axes)"

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
# ⚠ THE ONLY PROTECTION WAS A SENTENCE. `docs/development/handoff.md` carried
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
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: funcgate_refuses_live_home: $1"; exit 1; }

[ -f "$STAGE" ] || fail "scripts/funcgate-stage.sh missing"

# The script reads VERSION + lib/ relative to CWD, so every axis runs from the repo root.
cd "$ROOT"

# ── axis 1: target IS the user's live store → refuse, and leave it untouched ─────────
# HOME is redirected so the axis exercises the real `$HOME/.cyrius` branch without ever
# pointing the script at the actual store on this box.
mkdir -p "$WORK/h1/.cyrius/versions/6.5.9" "$WORK/h1/.cyrius/versions/6.6.1"
echo "sentinel" > "$WORK/h1/.cyrius/versions/6.5.9/marker"
if HOME="$WORK/h1" sh "$STAGE" /bin/true /bin/true "$WORK/h1/.cyrius" >"$WORK/o1" 2>&1; then
    fail "axis 1: staging into \$HOME/.cyrius was ALLOWED"
fi
grep -q 'REFUSING to rm -rf' "$WORK/o1" || fail "axis 1: refused but printed no reason"
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

echo "PASS: funcgate_refuses_live_home (4 axes)"

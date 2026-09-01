#!/bin/sh
# Gate: a generated `.deps` sidecar names ONLY leaves that exist in the stdlib (v6.5.37).
#
# THE FILED FAILURE. `include "lib/X.cyr"` in a bundled module means "X must be in scope" —
# it does NOT mean X is a STDLIB leaf, because a VENDORED dep lands in `lib/` too. dhancha's
# sidecar carried `kashi_font_data` (from `[deps.kashi] modules = ["src/font_data.cyr"]`),
# and a consumer's `cyrius deps` then hunted for it in the stdlib and failed outright:
#
#     error: dep dhancha requires 'kashi_font_data' but it is not in the cyrius stdlib
#
# crab and puka could not resolve dhancha AT ALL, and diagnosing it cost three wrong answers
# (a toolchain regression, then lib/ pollution, then dep ordering) before anyone read the
# sidecar. Still live at 6.5.36 in shabda and shabdakosh, whose sidecars name `hisab`,
# `goonj` and `naad` — all vendored, none stdlib.
#
# ⭐ THE ASYMMETRY THAT MAKES THIS FIRST: an UNDER-reported sidecar fails silently at the
# consumer's compile step; an OVER-reported one is a HARD resolver error before compilation
# is reached. Over-reporting is the fatal direction and the one a pure include-scan cannot
# avoid on its own.
#
# ⛔ THE REPO'S OWN `lib/` CANNOT ANSWER "IS THIS STDLIB?" — a vendored dep and a stdlib leaf
# are both files in `lib/`. The first cut of this fix checked `lib/<leaf>.cyr` first and so
# accepted exactly the leaves it was written to drop: measured 26 leaves in, 26 out, all
# three bogus names surviving in shabda. Only the stdlib SNAPSHOT can answer it. Axis 1
# fails against that first cut, which is the whole reason it is written this way.
#
# Measured before landing, read-only across the ecosystem: of 1177 sidecar leaves, exactly 6
# drop — the three bogus names in each of shabda and shabdakosh. Zero legitimate leaves lost.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CYRIUS=${CYRIUS_BIN:-"$ROOT/build/cyrius"}
[ -x "$CYRIUS" ] || CYRIUS=$(command -v cyrius)
HOMEDIR=${CYRIUS_HOME:-"$HOME/.cyrius"}
VER=$(cat "$ROOT/VERSION")
SNAP="$HOMEDIR/versions/$VER/lib"
[ -d "$SNAP" ] || SNAP="$HOMEDIR/lib"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: distlib_sidecar_stdlib_only: $1"; exit 1; }

[ -d "$SNAP" ] || { echo "  SKIPPED: no stdlib snapshot at $SNAP"; exit 0; }
[ -f "$SNAP/alloc.cyr" ] || fail "fixture premise: $SNAP/alloc.cyr missing"
# The directory-family leaf. If the tree ever stops shipping one, axis 3 must be re-pointed
# rather than dropped — it is the axis that fails a flat-file-only check.
FAMILY=""
[ -d "$SNAP/unicode" ] && FAMILY="unicode"

mkdir -p "$WORK/proj/src"
cat > "$WORK/proj/cyrius.cyml" <<EOF
[package]
name = "probe"
version = "0.1.0"
cyrius = "$VER"

[lib]
modules = ["src/lib.cyr"]
EOF
# A module that includes: a real stdlib leaf, a VENDORED (non-stdlib) leaf, and — when the
# tree has one — a directory-family leaf.
{
    echo 'include "lib/alloc.cyr"'
    echo 'include "lib/notastdlibleaf.cyr"'
    [ -n "$FAMILY" ] && echo "include \"lib/$FAMILY.cyr\""
    echo 'fn probe_entry(): i64 { return 0; }'
} > "$WORK/proj/src/lib.cyr"
# The vendored leaf exists in the project's OWN lib/ — exactly the shape that fooled the
# first cut. It must still be rejected, because it is not in the snapshot.
mkdir -p "$WORK/proj/lib"
echo 'fn notastdlibleaf_fn(): i64 { return 0; }' > "$WORK/proj/lib/notastdlibleaf.cyr"

( cd "$WORK/proj" && "$CYRIUS" distlib >/dev/null 2>&1 ) || true
DEPS="$WORK/proj/dist/probe.deps"
[ -f "$DEPS" ] || fail "no sidecar was written at $DEPS"

# ── axis 1: THE DEFECT — a vendored leaf present in the project's own lib/ is rejected ──
if grep -qx 'notastdlibleaf' "$DEPS"; then
    fail "axis 1: 'notastdlibleaf' is in the sidecar — a vendored dep was captured as a stdlib leaf"
fi

# ── axis 2: ANTI-VACUOUS — a real stdlib leaf is still captured ────────────────────────
# Without this, rejecting everything passes axis 1.
grep -qx 'alloc' "$DEPS" || fail "axis 2: 'alloc' is missing — the validator is dropping real stdlib leaves"

# ── axis 3: a DIRECTORY-family leaf survives ───────────────────────────────────────────
# `unicode` is the one stdlib module that is a package DIRECTORY with no flat lib/unicode.cyr.
# A validator that tests only `<snap>/<leaf>.cyr` drops it from every sidecar that needs it —
# the exact family the v6.5.31 resolver fix exists for.
if [ -n "$FAMILY" ]; then
    grep -qx "$FAMILY" "$DEPS" || fail "axis 3: directory-family leaf '$FAMILY' was dropped — the check tests only the flat <leaf>.cyr form"
else
    echo "  axis 3 SKIPPED: no directory-family leaf in $SNAP to test with"
fi

# ── axis 4: every leaf the sidecar names actually resolves ─────────────────────────────
# The property, stated directly: this is what the consumer's resolver will demand.
while IFS= read -r l; do
    case "$l" in ''|'#'*) continue;; esac
    [ -f "$SNAP/$l.cyr" ] || [ -d "$SNAP/$l" ] || fail "axis 4: sidecar names '$l', which does not resolve in $SNAP"
done < "$DEPS"

echo "PASS: distlib_sidecar_stdlib_only (vendored leaf rejected, stdlib kept, family kept, all leaves resolve)"

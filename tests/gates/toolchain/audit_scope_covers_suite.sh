#!/bin/sh
# Gate: `cyrius audit` walks the test/bench/fuzz tree, recursively (v6.5.42).
#
# THE DEFECT. The sweep pushed only `src/` and `programs/` (plus `lib/` in this repo) into its
# directory list, so `tests/`, `benches/` and `fuzz/` were never formatted, linted or checked —
# **the suite that guards the compiler was itself unaudited.** 289 `.tcyr` files, every shell
# gate's fixtures, and every bench.
#
# ⛔ TWO INDEPENDENT HALVES, AND EITHER ALONE STILL REPORTS A CLEAN VERDICT OVER NOTHING:
#   1. SCOPE — `tests/` was not in the list at all.
#   2. DESCENT — the walkers listed each directory and nothing beneath it, and the suite lives
#      at `tests/tcyr/<bucket>/*.tcyr`, TWO levels down. Adding `tests/` to a flat lister finds
#      a directory containing only directories and audits zero files, while the `scope:` banner
#      cheerfully prints "tests".
#   3. EXTENSION — `_aw_is_cyr` matched only `.cyr`. The tail scan is anchored at `len-4`, so
#      "foo.tcyr" ends in "tcyr", not ".cyr", and did NOT fall out of the same check. All three
#      had to change together.
#
# ⭐ AXIS 2 IS THE NON-VACUOUS ONE AND IT IS THE WHOLE POINT. "audit passes" proves nothing
# here — it is exactly what the broken version did. The gate plants a deliberately
# mis-formatted `.tcyr` two levels down and requires audit to FAIL on it, then removes it and
# requires audit to pass. Without that, every fix to this reports success by not looking.
#
# ⛔ v6.6.6 — THE PROBE GOES INTO A SCRATCH COPY OF THE TREE, NEVER INTO tests/. This gate used
# to write its probe to $ROOT/tests/tcyr/lang/ and rely on `rm` + an EXIT trap to take it back
# out — a write-then-restore of the tree it checks, the shape that let syscall_xlat_generated.sh
# restore an EMPTY file over a tracked source at the 6.6.5 close. SIGKILL (a timeout, a dying
# parent) runs no trap: measured in a scratch copy of 6.6.5, a kill ~105 s in left
# `?? tests/tcyr/lang/_audit_scope_probe.tcyr` behind, and a real 6.6.5 check.sh run found one
# left by two killed runs. `cyrius audit` now runs in $WORK/t, a copy of every directory it
# walks plus the manifest and the four tools it resolves from ./build, so the tree is only
# ever READ. tests/gates/toolchain/gates_never_write_tree.sh pins it. CHANGELOG [6.6.6]
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "FAIL: audit_scope_covers_suite: build/cycc missing"; exit 1; }
fail() { echo "FAIL: audit_scope_covers_suite: $1"; exit 1; }
WORK=$(mktemp -d) && [ -d "$WORK" ] || { echo "FAIL: audit_scope_covers_suite: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$WORK"' EXIT

# The scratch tree. `_audit_sweep` walks lib/ src/ programs/ tests/ benches/ fuzz/ cbt/ (lib/
# and cbt/ only when cyrius.cyml names the package `cyrius`, so the manifest comes too) and
# resolves cyrfmt/cyrlint/cyrdoc from ./build when ./build/cycc exists. Copies, never links: a
# symlinked subtree would put the tree back under the probe.
T="$WORK/t"
mkdir -p "$T/build" || fail "could not create the scratch tree under $WORK"
for d in lib src programs tests benches fuzz cbt; do
    [ -d "$ROOT/$d" ] || continue
    cp -R "$ROOT/$d" "$T/$d" || fail "could not copy $d/ into the scratch tree (a full TMPDIR?)"
done
for f in cyrius.cyml cyrius.lock VERSION; do
    [ -f "$ROOT/$f" ] || continue
    cp "$ROOT/$f" "$T/$f" || fail "could not copy $f into the scratch tree"
done
for b in cycc cyrfmt cyrlint cyrdoc; do
    [ -x "$ROOT/build/$b" ] || continue
    cp "$ROOT/build/$b" "$T/build/$b" || fail "could not copy build/$b into the scratch tree"
done
[ -x "$T/build/cyrfmt" ] || fail "build/cyrfmt missing — the fmt stage would print 'skip' and axis 2 could measure nothing"
PROBE="$T/tests/tcyr/lang/_audit_scope_probe.tcyr"
[ -d "$T/tests/tcyr/lang" ] || fail "tests/tcyr/lang/ is missing from the scratch tree — the probe has nowhere to go"

# Built from source against build/cycc — never the installed `cyrius`, which is the last
# release and would test the wrong binary.
( cd "$ROOT" && cat cbt/cyrius.cyr | "$CC" > "$WORK/cyrius" ) 2>/dev/null \
    || fail "could not build cbt/cyrius.cyr"
chmod +x "$WORK/cyrius"

# ── axis 1: the scope banner names the suite directories ──────────────────────────
SCOPE=$( cd "$T" && "$WORK/cyrius" audit 2>&1 | grep -m1 '^  scope:' || true )
[ -n "$SCOPE" ] || fail "axis 1: audit printed no 'scope:' line at all"
for d in tests benches fuzz; do
    echo "$SCOPE" | grep -qw "$d" || fail "axis 1: audit scope does not include '$d' — got: $SCOPE"
done

# ── axis 2: ⭐ NON-VACUOUS — adding one bad file TWO LEVELS DOWN must move the fmt count ──
# ⚠ Three things this gate cannot do, each learned the hard way on its own earlier versions:
#   1. It cannot assert "audit passes". `cyrius audit` already fails in this repo BY DESIGN —
#      cycc's `main*.cyr` forks are deliberately not cyrfmt-clean (documented residual since
#      v6.4.78) — and the OLD un-widened audit failed with the identical message.
#   2. It cannot grep the whole transcript for the probe's name. The first version did, and the
#      match came from `cyrius audit`'s own TEST stage failing an invalid `.tcyr` — so the gate
#      passed with the recursive descent deliberately removed, measuring the test runner rather
#      than the audit walker. The probe is now a VALID test that passes the test stage and is
#      mis-formatted so only fmt objects.
#   3. It cannot require the probe to be NAMED. The fmt stage caps its file list at 20 and
#      prints "… and N more", and widening the scope surfaced ~86 pre-existing unformatted
#      files, so the probe lands past the cap.
# What is left, and is exact: the fmt stage's TOTAL must rise by exactly one when the probe is
# added. That is reached only if the scope includes `tests/`, the walkers descend two levels,
# and `.tcyr` is recognised.
fmt_total() {   # named-lines + the "… and N more" remainder, from an audit transcript
    sec=$(awk '/── fmt ──/{f=1;next} f && /^── /{exit} f' "$1")
    named=$(printf '%s\n' "$sec" | grep -cE '^    [^ …]' || true)
    more=$(printf '%s\n' "$sec" | grep -oE '… and [0-9]+ more' | grep -oE '[0-9]+' || true)
    [ -z "$more" ] && more=0
    echo $((named + more))
}

# ⚠ 6.6.5 — no probe in BASE. A probe that a pre-6.6.6 run left in a working tree is COPIED
# into the scratch tree with everything else; counted in BASE it would collapse the +1 delta
# to BASE -> BASE and read as a broken descent. Unlinked from the COPY — the tree is not ours.
rm -f "$PROBE"
set +e
( cd "$T" && "$WORK/cyrius" audit > "$WORK/base.out" 2>&1 )
set -e
BASE=$(fmt_total "$WORK/base.out")
[ "$BASE" -gt 0 ] || fail "axis 2 setup: the fmt stage reported 0 failing files, so a +1 delta cannot be measured — the section markers or the cap wording changed and this gate is blind"

cat > "$PROBE" <<'PROBE_EOF'
# valid but deliberately mis-formatted probe for audit_scope_covers_suite.
# It PASSES `cyrius test` (so the test stage stays quiet) and is over-indented by four spaces,
# which cyrfmt normalises — so only the fmt stage objects to it.
include "lib/assert.cyr"
include "lib/syscalls.cyr"
fn _asp_add(a, b): i64 {
        return a + b;
}
fn main(): i64 {
    assert_eq(_asp_add(2, 3), 5, "probe adds");
    var r = assert_summary();
    return r;
}
var ec = main();
syscall(60, ec);
PROBE_EOF

set +e
( cd "$T" && "$WORK/cyrius" audit > "$WORK/bad.out" 2>&1 )
set -e
WITH=$(fmt_total "$WORK/bad.out")
rm -f "$PROBE"
[ "$WITH" -eq $((BASE + 1)) ] \
    || fail "axis 2: adding a mis-formatted tests/tcyr/lang/*.tcyr moved the fmt count $BASE -> $WITH (expected $((BASE + 1))) — the scope banner says 'tests' but nothing two levels beneath it is being read (recursive descent or the .tcyr extension is missing)"

# ── axis 3: the count returns once the probe is removed ───────────────────────────
# Guards the opposite error: a count that drifts on its own would satisfy axis 2 by accident.
set +e
( cd "$T" && "$WORK/cyrius" audit > "$WORK/good.out" 2>&1 )
set -e
AFTER=$(fmt_total "$WORK/good.out")
[ "$AFTER" -eq "$BASE" ] \
    || fail "axis 3: the fmt count did not return to $BASE after the probe was removed (got $AFTER) — it is drifting between runs, so axis 2's +1 proves nothing"

echo "PASS: audit_scope_covers_suite (scope names tests/benches/fuzz; a mis-formatted .tcyr two levels down moves the fmt count $BASE -> $WITH and back — measured in a scratch copy, the tree is only read)"

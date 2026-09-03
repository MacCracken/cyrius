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
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "FAIL: audit_scope_covers_suite: build/cycc missing"; exit 1; }
WORK=$(mktemp -d)
PROBE="$ROOT/tests/tcyr/lang/_audit_scope_probe.tcyr"
trap 'rm -rf "$WORK"; rm -f "$PROBE"' EXIT
fail() { echo "FAIL: audit_scope_covers_suite: $1"; exit 1; }

# Built from source against build/cycc — never the installed `cyrius`, which is the last
# release and would test the wrong binary.
( cd "$ROOT" && cat cbt/cyrius.cyr | "$CC" > "$WORK/cyrius" ) 2>/dev/null \
    || fail "could not build cbt/cyrius.cyr"
chmod +x "$WORK/cyrius"

# ── axis 1: the scope banner names the suite directories ──────────────────────────
SCOPE=$( cd "$ROOT" && "$WORK/cyrius" audit 2>&1 | grep -m1 '^  scope:' || true )
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

set +e
( cd "$ROOT" && "$WORK/cyrius" audit > "$WORK/base.out" 2>&1 )
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
( cd "$ROOT" && "$WORK/cyrius" audit > "$WORK/bad.out" 2>&1 )
set -e
WITH=$(fmt_total "$WORK/bad.out")
rm -f "$PROBE"
[ "$WITH" -eq $((BASE + 1)) ] \
    || fail "axis 2: adding a mis-formatted tests/tcyr/lang/*.tcyr moved the fmt count $BASE -> $WITH (expected $((BASE + 1))) — the scope banner says 'tests' but nothing two levels beneath it is being read (recursive descent or the .tcyr extension is missing)"

# ── axis 3: the count returns once the probe is removed ───────────────────────────
# Guards the opposite error: a count that drifts on its own would satisfy axis 2 by accident.
set +e
( cd "$ROOT" && "$WORK/cyrius" audit > "$WORK/good.out" 2>&1 )
set -e
AFTER=$(fmt_total "$WORK/good.out")
[ "$AFTER" -eq "$BASE" ] \
    || fail "axis 3: the fmt count did not return to $BASE after the probe was removed (got $AFTER) — it is drifting between runs, so axis 2's +1 proves nothing"

echo "PASS: audit_scope_covers_suite (scope names tests/benches/fuzz; a mis-formatted .tcyr two levels down moves the fmt count $BASE -> $WITH and back)"

#!/bin/sh
# Gate: resolution errors carry a source excerpt, and `#assert` cannot eat the next
# statement (v6.5.39).
#
# TWO defects, one function apart, both found while closing the DX multi-error residual.
#
# (A) THE EXCERPT ASYMMETRY — the actual filed residual. v6.5.23 converted the five
# `undefined variable` sites from fail-fast to report-and-continue, which is why a compile
# now lists every unresolved name instead of stopping at the first. But `_err_excerpt` lives
# inside `ERR_IDENT`, and those five sites deliberately BYPASS `ERR_IDENT` — it sets
# `_panic = 1`, which reinstates the manufactured `unexpected else` regression on lib/fs.cyr
# that got an earlier attempt reverted. So resolution errors printed a bare message while
# every syntax error got line + caret. ⚠ The fix must stay a bare `_err_excerpt(S)` call and
# must NOT be "tidied" into a reroute through `ERR_IDENT`; that is the same revert, again.
#
# (B) ⛔ A LATENT SILENT MISCOMPILE in the `#assert` skip-loop. Its comment promised
# "consume remaining tokens until ; or newline change" and the loop tested only `;` and EOF —
# there was no newline check at all. A `#assert` with no trailing `;` therefore skipped across
# the following `fn` header and ate the first statement AND its `;`. Measured pre-fix: the
# axis-3 fixture exits 0 instead of 7 — wrong code, no diagnostic, no crash. Latent only
# because nothing in the tree uses `#assert` today (all 12 grep hits are compiler
# implementation or comments), so it was waiting for the first consumer who did. Duplicated at
# three sites in three files: src/frontend/parse.cyr (pass 2, shared by all forks) and the
# pass-1 arms in src/main.cyr and src/main_win.cyr.
#
# ⚠ THE FILING THIS CLOSES WAS WRONG THREE WAYS, recorded so a sweep does not re-inflate it:
# its residual count (7, re-stamped to 8) was 1 on live code; its "_ends_guard added a site"
# is false (that site recovers); and its "R2 must land before R1" dependency is contradicted
# by the CHANGELOG of the release that shipped both.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC="$ROOT/build/cycc"
[ -x "$CC" ] || { echo "FAIL: resolution_excerpt_and_assert_skip: build/cycc missing"; exit 1; }
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: resolution_excerpt_and_assert_skip: $1"; exit 1; }

# ── axis 1: a resolution error prints the excerpt AND the caret ────────────────────
cat > "$WORK/multi.cyr" <<'EOF'
fn main(): i64 {
    var a = ALPHA;
    var b = BRAVO;
    return a + b;
}
EOF
set +e
( cd "$ROOT" && cat "$WORK/multi.cyr" | "$CC" > /dev/null ) 2> "$WORK/err"; RC=$?
set -e
[ "$RC" -ne 0 ] || fail "axis 1: a program with two undefined variables compiled successfully"
grep -q "undefined variable 'ALPHA'" "$WORK/err" || fail "axis 1: the first undefined variable was not reported"
# The excerpt is the SOURCE LINE echoed back; the caret is the column marker under it.
grep -q "var a = ALPHA;" "$WORK/err" \
    || fail "axis 1: the error has no source excerpt — resolution errors still print a bare message while syntax errors get line+caret: $(cat "$WORK/err")"
grep -q '\^' "$WORK/err" || fail "axis 1: excerpt present but no caret line"

# ── axis 2: R1 regression guard — ALL resolution errors in one compile ─────────────
# If someone re-routes these sites through ERR_IDENT to "reuse" the excerpt, `_panic = 1`
# comes back with it and the compile stops reporting after the first.
grep -q "undefined variable 'BRAVO'" "$WORK/err" \
    || fail "axis 2: only the first undefined variable was reported — report-and-continue was lost (an ERR_IDENT reroute sets _panic and does exactly this)"

# ── axis 3: `#assert` with no trailing ';' must not consume the next statement ─────
cat > "$WORK/asrt.cyr" <<'EOF'
include "lib/syscalls.cyr"
#assert 1 == 1 "ok"
fn main(): i64 {
    var x = 7;
    return x;
}
var ec = main();
syscall(60, ec);
EOF
# ⚠ TWO failure symptoms, and the gate must name both. If only the pass-2 copy
# (src/frontend/parse.cyr) regresses, the two passes disagree about where the directive ends
# and the fixture fails to COMPILE. If all three copies regress together, it compiles fine
# and returns the WRONG ANSWER. Reporting only the second would misdiagnose the first.
set +e
( cd "$ROOT" && cat "$WORK/asrt.cyr" | "$CC" > "$WORK/a.out" ) 2> "$WORK/aerr"; ARC=$?
set -e
[ "$ARC" -eq 0 ] || fail "axis 3: the #assert fixture did not compile ($(head -1 "$WORK/aerr")) — most likely the pass-1 and pass-2 skip-loops now disagree about where the directive ends"
chmod +x "$WORK/a.out"
set +e
( cd "$ROOT" && "$WORK/a.out" ); AR=$?
set -e
[ "$AR" -eq 7 ] || fail "axis 3: exit $AR, expected 7 — the #assert skip-loop consumed 'var x = 7;' and its ';' (pre-fix this returns 0: wrong code, no diagnostic)"

# ── axis 4: ANTI-VACUOUS — the excerpt machinery is live for syntax errors too ─────
# If `_err_excerpt` were globally broken, axis 1 would fail for an unrelated reason and the
# diagnosis would go to the wrong place. This pins that the machinery itself works.
cat > "$WORK/syn.cyr" <<'EOF'
fn main(): i64 {
    var b = ;
    return 0;
}
EOF
set +e
( cd "$ROOT" && cat "$WORK/syn.cyr" | "$CC" > /dev/null ) 2> "$WORK/serr"
set -e
grep -q '\^' "$WORK/serr" || fail "axis 4 anti-vacuous: even a plain SYNTAX error has no caret — _err_excerpt is broken generally, not just at the resolution sites"

echo "PASS: resolution_excerpt_and_assert_skip (resolution errors carry excerpt+caret, all are reported, and #assert no longer eats the following statement)"

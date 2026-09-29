#!/bin/sh
# Gate: the check driver's .tcyr reader requires the assert summary (6.6.11 B01, O3).
#
# THE DEFECT. `_tcyr_compile_and_run` (programs/checks/selfhost.cyr) scored a PASS on
# `failed == 0 && ec == 0`, where `failed` came from the FIRST " failed" substring in the
# captured stdout. The driver captures stdout only, so a test's FAIL rows (stderr) are never
# seen. A binary that died before its summary — `assert_eq(1, 2, ..); syscall(60, 0);` — or
# that printed `0 passed, 0 failed` read PASS. MEASURED against the 6.6.10 driver on the
# fixtures below: rows `die_early` and `zero` both PASS.
#
# THE RULE, the same one every .tcyr reader applies since 6.6.11 (see `_tcyr_grade`): when the
# SOURCE calls assert_summary(, the LAST `N passed, M failed` line must exist with N >= 1 and
# M == 0, and the exit code must be 0. A source without assert_summary( is graded on its exit
# code alone (the corpus has one: frontend/struct_sid_20_21_field.tcyr) — row `optout`.
#
# ROWS (a staged root: build/cycc + lib symlinked, tests/tcyr/zz/*.tcyr):
#   good        asserts, prints its summary, exits on it                  -> PASS
#   die_early   a failing assert, then exit 0 before the summary          -> FAIL (no summary)
#   main_twice  fn main + top-level `main();` (the epilogue runs it again) -> FAIL (1 failed)
#   zero        a summary with 0 assertions                               -> FAIL (0 assertions)
#   exit3       a clean summary and exit 3                                -> FAIL (exit)
#   optout      no assert_summary in the source, exit 0                   -> PASS
#   late        a FIRST summary reading `0 failed`, a LATER one `1 failed` -> FAIL (the LAST
#               line decides; the first-substring parse this replaced read the first)
#
# MUTATION (run on every invocation): a driver built from a copy of selfhost.cyr with the
# summary requirement deleted (the no-summary and 0-assertion returns) must score `die_early`
# PASS — otherwise the row proves nothing.
#
# Exit 77 when it could not run (no compiler). CHANGELOG [6.6.11]
set -u

NAME=check_driver_requires_summary
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: $NAME — no compiler at $CC"; exit 77; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $NAME — mktemp"; exit 1; }
trap 'rm -rf "$T"' EXIT
ulimit -c 0 2>/dev/null || true
fails=0
check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 — expected $2, got $3"; fails=$((fails + 1)); fi
}
strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

# ── build the driver (and its mutant) from staged copies, so the mutant is a textual edit ──
_build_drv() {   # $1 = staged programs/checks dir root, $2 = output
    ( cd "$1" && "$CC" < programs/checks/main.cyr > "$2" 2> "$2.err" ) || return 1
    chmod +x "$2"
}
mkdir -p "$T/src"
cp -R "$ROOT/programs" "$T/src/programs"
ln -s "$ROOT/lib" "$T/src/lib"
_build_drv "$T/src" "$T/drv" || { echo "FAIL: $NAME — the check driver does not compile"; sed 's/^/    /' "$T/drv.err"; exit 1; }
mkdir -p "$T/msrc"
cp -R "$ROOT/programs" "$T/msrc/programs"
ln -s "$ROOT/lib" "$T/msrc/lib"
grep -vF -e 'if (have == 0) { return 0 - 3; }' -e 'if (load64(sm) < 1) { return 0 - 4; }' "$ROOT/programs/checks/selfhost.cyr" > "$T/msrc/programs/checks/selfhost.cyr"
MUT_OK=yes
cmp -s "$T/msrc/programs/checks/selfhost.cyr" "$ROOT/programs/checks/selfhost.cyr" && MUT_OK=no
_build_drv "$T/msrc" "$T/drv_mut" || MUT_OK=no

# ── the staged root ──
R="$T/root"
mkdir -p "$R/build" "$R/tests/tcyr/zz"
ln -s "$CC" "$R/build/cycc"
ln -s "$ROOT/lib" "$R/lib"
Z="$R/tests/tcyr/zz"
printf 'include "lib/assert.cyr"\nassert_eq(1, 1, "ok");\nvar r = assert_summary();\nsyscall(60, r);\n' > "$Z/good.tcyr"
printf 'include "lib/assert.cyr"\nassert_eq(1, 2, "dies early");\nsyscall(60, 0);\nvar r = assert_summary();\n' > "$Z/die_early.tcyr"
printf 'include "lib/assert.cyr"\nfn main() {\n    assert_eq(1, 1, "right");\n    assert_eq(1, 2, "wrong");\n    return 0;\n}\nmain();\nvar r = assert_summary();\n' > "$Z/main_twice.tcyr"
printf 'include "lib/assert.cyr"\nvar r = assert_summary();\nsyscall(60, r);\n' > "$Z/zero.tcyr"
printf 'include "lib/assert.cyr"\nassert_eq(1, 1, "ok");\nvar r = assert_summary();\nsyscall(60, 3);\n' > "$Z/exit3.tcyr"
printf 'var q = 0;\nsyscall(60, q);\n' > "$Z/optout.tcyr"
printf 'include "lib/assert.cyr"\nassert_eq(1, 1, "ok");\nvar r1 = assert_summary();\nassert_eq(1, 2, "after the first summary");\nvar r2 = assert_summary();\nsyscall(60, 0);\n' > "$Z/late.tcyr"
NROWS=$(ls "$Z" | grep -c '\.tcyr$')
# The floor is 1 so the suite's own floor check is not what this gate reads.
echo 1 > "$R/tests/tcyr/CORPUS_FLOOR"

( cd "$R" && CYRIUS_CHECK_TIMEOUT=60 timeout 300 "$T/drv" tcyr ) 2>&1 | strip_ansi > "$T/out.txt"
row() { grep -E "^  zz/$1 " "$T/out.txt" | sed -E 's/^  zz\/[a-z_0-9]+ +//'; }
echo "the check driver's tcyr rows:"
check "good        passes"                       "PASS" "$(row good)"
check "die_early   fails on the missing summary" "yes"  "$(row die_early | grep -q '^FAIL (no assert summary' && echo yes || echo no)"
check "main_twice  fails on its failed count"    "FAIL (1 failed)" "$(row main_twice)"
check "zero        fails on 0 assertions"        "yes"  "$(row zero | grep -q '^FAIL (the assert summary reports 0 assertions' && echo yes || echo no)"
check "exit3       fails on the exit code"       "yes"  "$(row exit3 | grep -q '^FAIL (the summary is clean but the process exited nonzero.*exit 3)$' && echo yes || echo no)"
check "optout      passes on exit 0 alone"       "PASS" "$(row optout)"
check "late        the LAST summary decides"     "FAIL (1 failed)" "$(row late)"
check "every staged row was read"                "$NROWS" "$(grep -cE '^  zz/' "$T/out.txt")"
check "the suite row is RED"                     "yes"  "$(grep -q "^  FAIL: test suite ($NROWS files)$" "$T/out.txt" && echo yes || echo no)"

echo "mutation: the summary requirement deleted"
if [ "$MUT_OK" = yes ]; then
    ( cd "$R" && CYRIUS_CHECK_TIMEOUT=60 timeout 300 "$T/drv_mut" tcyr ) 2>&1 | strip_ansi > "$T/mut.txt"
    check "the mutant scores die_early PASS (so the row is load-bearing)" "PASS" \
        "$(grep -E '^  zz/die_early ' "$T/mut.txt" | sed -E 's/^  zz\/[a-z_0-9]+ +//')"
else
    check "the mutant could be built (the deleted line is still in selfhost.cyr)" "yes" "no"
fi

if [ "$fails" -gt 0 ]; then
    echo "FAIL: $NAME: $fails problem(s)"
    exit 1
fi
echo "PASS: $NAME ($NROWS rows; a missing, empty or failing summary, or a nonzero exit, is a failure; mutant proven)"
exit 0

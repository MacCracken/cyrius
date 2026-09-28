#!/bin/sh
# tests/gates/toolchain/check_driver_skip_is_not_pass.sh — 6.6.9 (bite 11)
#
# A CHECK-DRIVER ROW THAT DID NOT RUN ITS CHECK SAYS SKIP, IS COUNTED AS A SKIP, AND UNDER
# CYRIUS_CHECK_NO_SKIP=1 IS A FAILURE.
#
# THE DEFECT. 86 rows in programs/checks/*.cyr answered "the tool / host / fixture I need is
# missing" with `_check(label, 0)` — a `skip:` note, then a green `PASS:` line and +1 on the
# passed count. `cyrius_check linker` with no build/cyrld printed
#     skip: build/cyrld not present
#     PASS: cyrld cross-module link
#     1 passed, 0 failed (1 total)
# and exited 0: a run that exercised nothing read exactly like one that exercised everything.
# That blocked the obvious fix for CI's hand-copied driver gates (delegate the CI step to the
# driver row): the old inline CI step FAILED on a missing tool, the driver row PASSED on it,
# so delegating would have turned a red CI into a silent green.
#
# THE FIX (programs/checks/main.cyr `_skip`). A SKIP row prints `SKIP: <row> — <why>`, is
# tallied as `N skipped` in the final line (`P passed, F failed, S skipped (T total)` — the
# `passed, F failed` and `(T total)` shapes that release-gate.sh and check_targeted_run_selects
# read are unchanged), and never touches the passed count. CYRIUS_CHECK_NO_SKIP=1 — what CI
# runs its delegated steps under — scores every SKIP as a FAIL that names why the row could not
# run; any value other than 1/0/empty is refused (exit 2) so a typo cannot silently mean "off".
#
# AXES
#   1  a row whose prerequisite is missing: SKIP line, no PASS line, `0 passed, 0 failed,
#      1 skipped (1 total)`, exit 0
#   2  the same row under CYRIUS_CHECK_NO_SKIP=1: FAIL line, the reason, `1 failed`, exit != 0
#   3  CYRIUS_CHECK_NO_SKIP=yes is refused with exit 2, naming the variable, running nothing;
#      =0 and empty behave as unset
#   4  POSITIVE CONTROL — a row that CAN run still PASSes under CYRIUS_CHECK_NO_SKIP=1 (a
#      strict mode that failed everything would satisfy axis 2 and be useless)
#   5  STRUCTURAL RATCHET 0 — no `_check(<row>, 0)` in programs/checks/*.cyr sits right after a
#      print of a skip message (the old shape); the detector is self-tested on that shape, and
#      a floor on `_skip(` calls keeps the scan from going vacuous
#
# MUTATIONS (each RED; ledger measured when this gate was written):
#   M1 `_skip` scores the row as a PASS (G_PASS + 1, `PASS:` line)       -> axis 1 RED
#   M2 `_read_no_skip` always returns 0 (strict mode ignored)             -> axis 2 RED
#   M3 `_read_no_skip` accepts any value as "on"                         -> axis 3 RED
#   M4 the linker row's `_skip` restored to `_p("  skip: …"); _check(label, 0)` -> axes 1, 5 RED
#   M5 `_skip` under NO_SKIP scores every row, not just skips, as failed
#      (G_NO_SKIP makes `_tally` fail everything)                          -> axis 4 RED
set -e
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
NAME=check_driver_skip_is_not_pass
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: mktemp -d"; exit 1; }
trap 'rm -rf "$D"' EXIT
FAILS=0
_fail() { echo "  FAIL: $1"; FAILS=$((FAILS + 1)); }
strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

[ -x "$CC" ] || { echo "FAIL: $NAME — no compiler at $CC"; exit 1; }
# Build the driver from THIS tree's source (never a stale build/cyrius_check).
( cd "$ROOT" && cat programs/checks/main.cyr | "$CC" > "$D/drv" 2>"$D/drv.err" ) \
    || { cat "$D/drv.err"; echo "FAIL: $NAME — the check driver does not compile"; exit 1; }
chmod +x "$D/drv"

# A scratch ROOT: the driver takes its root from its cwd. It holds build/cycc and nothing else,
# so the linker row's build/cyrld is missing (a SKIP) while the object-init row — which needs
# only build/cycc — can run (axis 4).
R="$D/root"
mkdir -p "$R/build"
cp "$CC" "$R/build/cycc"
run() {  # $1 = out file, rest = env assignments then the row
    _o=$1; shift
    _rc=0
    ( cd "$R" && env "$@" "$D/drv" "$ROW" ) > "$_o.raw" 2>&1 || _rc=$?
    strip_ansi < "$_o.raw" > "$_o"
    echo "$_rc" > "$_o.rc"
}
TALLY_RE='^[0-9]+ passed, [0-9]+ failed, [0-9]+ skipped \([0-9]+ total\)$'

echo "axis 1: a row whose prerequisite is missing is a SKIP, not a PASS"
ROW=linker
run "$D/a1" CYRIUS_CHECK_NO_SKIP=
[ "$(cat "$D/a1.rc")" = 0 ] || _fail "axis 1: a SKIP-only run exited $(cat "$D/a1.rc"), expected 0 (a SKIP is not a failure by default)"
grep -q '^  SKIP: cyrld cross-module link — build/cyrld not present$' "$D/a1" \
    || _fail "axis 1: no 'SKIP: cyrld cross-module link — build/cyrld not present' line"
grep -q '^  PASS: ' "$D/a1" && _fail "axis 1: a row that did not run printed PASS"
grep -qx '0 passed, 0 failed, 1 skipped (1 total)' "$D/a1" \
    || _fail "axis 1: tally is '$(grep -E 'passed,' "$D/a1" | tail -1)', expected '0 passed, 0 failed, 1 skipped (1 total)'"
grep -qE "$TALLY_RE" "$D/a1" || _fail "axis 1: the tally line lost its 'P passed, F failed, S skipped (T total)' shape"

echo "axis 2: under CYRIUS_CHECK_NO_SKIP=1 the same row is a FAIL that says why"
run "$D/a2" CYRIUS_CHECK_NO_SKIP=1
[ "$(cat "$D/a2.rc")" != 0 ] || _fail "axis 2: CYRIUS_CHECK_NO_SKIP=1 with a missing build/cyrld exited 0"
grep -q '^  FAIL: cyrld cross-module link$' "$D/a2" || _fail "axis 2: no 'FAIL: cyrld cross-module link' line"
grep -q 'SKIP REFUSED.*build/cyrld not present' "$D/a2" || _fail "axis 2: the failure does not say which prerequisite was missing"
grep -qx '0 passed, 1 failed, 0 skipped (1 total)' "$D/a2" \
    || _fail "axis 2: tally is '$(grep -E 'passed,' "$D/a2" | tail -1)', expected '0 passed, 1 failed, 0 skipped (1 total)'"

echo "axis 3: an unrecognised CYRIUS_CHECK_NO_SKIP value is refused; 0 and empty mean off"
run "$D/a3" CYRIUS_CHECK_NO_SKIP=yes
[ "$(cat "$D/a3.rc")" = 2 ] || _fail "axis 3: CYRIUS_CHECK_NO_SKIP=yes exited $(cat "$D/a3.rc"), expected 2"
grep -q "CYRIUS_CHECK_NO_SKIP.*'yes'" "$D/a3" || _fail "axis 3: the refusal does not name the variable and the value"
grep -q 'Audit' "$D/a3" && _fail "axis 3: a refused CYRIUS_CHECK_NO_SKIP still started the run"
run "$D/a3z" CYRIUS_CHECK_NO_SKIP=0
{ [ "$(cat "$D/a3z.rc")" = 0 ] && grep -qx '0 passed, 0 failed, 1 skipped (1 total)' "$D/a3z"; } \
    || _fail "axis 3: CYRIUS_CHECK_NO_SKIP=0 does not behave as unset (rc $(cat "$D/a3z.rc"))"

echo "axis 4: positive control — a row that can run still PASSes in strict mode"
ROW=object-init
run "$D/a4" CYRIUS_CHECK_NO_SKIP=1
[ "$(cat "$D/a4.rc")" = 0 ] || _fail "axis 4: the object-init row (needs only build/cycc) exited $(cat "$D/a4.rc") under CYRIUS_CHECK_NO_SKIP=1"
grep -qx '1 passed, 0 failed, 0 skipped (1 total)' "$D/a4" \
    || _fail "axis 4: tally is '$(grep -E 'passed,' "$D/a4" | tail -1)', expected '1 passed, 0 failed, 0 skipped (1 total)'"

echo "axis 5: no row scores a skip as _check(<row>, 0) (ratchet 0)"
# The detector: a `_check(<x>, 0);` whose own line, or the run of print-only lines right above
# it, prints a string containing skip/SKIP. A LABEL that says "skips" is not a print, so
# `_check("cyrfmt skips {/} …", fail)` is not a hit.
detect() {
    awk '
    function isprint(l) { return l ~ /^[ \t]*((_p|println|print_num)\(.*\);[ \t]*)+$/ }
    function skipmsg(l) { return l ~ /(_p|println)\("[^"]*(skip|SKIP)/ }
    FNR == 1 { split("", line) }
    { line[FNR] = $0 }
    /_check\(.*, 0\);/ && $0 !~ /^[ \t]*#/ {
        hit = skipmsg($0)
        j = FNR - 1
        while (!hit && j > 0 && isprint(line[j])) { if (skipmsg(line[j])) hit = 1; j-- }
        if (hit) print FILENAME ":" FNR
    }' "$@"
}
printf '    if (x) {\n        _p("  skip: ");\n        _p(CC_PATH);\n        println(" not present");\n        _check(label, 0);\n        return 0;\n    }\n    if (y) { _p("  skip: z missing"); println(""); _check(label, 0); return 0; }\n    _check("cyrfmt skips {/} x", 0);\n' > "$D/selftest.cyr"
NST=$(detect "$D/selftest.cyr" | grep -c . || true)
[ "$NST" = 2 ] || _fail "axis 5: the detector found $NST of the 2 planted skip-as-pass shapes (and must not flag a label saying 'skips')"
detect "$ROOT"/programs/checks/*.cyr > "$D/hits" || true
NH=$(grep -c . "$D/hits" || true)
[ "$NH" = 0 ] || { _fail "axis 5: $NH row(s) still score a skip as a pass:"; sed 's/^/      /' "$D/hits"; }
NSK=$(grep -hE '(^|[^A-Za-z0-9_])_skip\(' "$ROOT"/programs/checks/*.cyr | grep -vcE '^[[:space:]]*#|fn _skip' || true)
[ "$NSK" -ge 80 ] || _fail "axis 5: only $NSK _skip( call(s) in programs/checks/ (floor 80) — the scan read nothing, or skips were turned back into passes"

echo ""
if [ "$FAILS" -gt 0 ]; then
    echo "FAIL: $NAME — $FAILS check(s) failed"
    exit 1
fi
echo "PASS: $NAME (a missing prerequisite is a SKIP row and a SKIP count, a FAIL under CYRIUS_CHECK_NO_SKIP=1, $NSK skip sites, 0 scored as passes)"
exit 0

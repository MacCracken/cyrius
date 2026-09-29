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
#
# ⛔ 6.6.11 (K1, K3) — THE SHELL-GATE HALF, AND THE EMPTY SELECTION.
# K1: a SHELL gate had no way to say "I could not run" but `echo SKIP; exit 0`, and both paths
# that run one — the driver's `_gate` (programs/checks/main.cyr) and check.sh's `_chk_gate` —
# scored rc 0 as PASS and everything else as FAIL, so 57 whole-gate SKIPs (and ~50 gates that
# skipped an axis) were PASSes and CYRIUS_CHECK_NO_SKIP never reached a shell gate at all.
# Exit 77 (automake's SKIP) is now "could not run its check": a SKIP row by default, a FAIL
# under CYRIUS_CHECK_NO_SKIP=1, in BOTH paths; check.sh reads the variable with the driver's
# 1/0/unset/refuse contract. K3: `CYRIUS_CHECK_NO_SKIP=1 ./drv <suite>` over a row that
# tallied NOTHING printed `0 passed, 0 failed, 0 skipped (0 total)` and exited 0 — the mode
# every CI-delegated step runs in. A selected suite that ran no rows now fails, by name.
#   6  the DRIVER path: a scratch driver whose object-init row is ONE `_gate(...)` over a fake
#      gate that exits 77 — SKIP row / `1 skipped` / exit 0 by default, SKIP REFUSED + FAIL
#      under NO_SKIP=1; `--gate-row` (the same `_gate_score`) agrees, and honours NO_SKIP too
#   7  the CHECK.SH path: the real scripts/check.sh over a fake bucket {a 77 gate, a 0 gate},
#      run through the real driver's `--run-gate` supervisor — SKIP result, `skipped: 1`, the
#      SKIPPED list, rc 0 and NOT `ALL GREEN` by default; FAIL + rc != 0 under NO_SKIP=1 with
#      the 0 gate still PASS (positive control); `=yes` refused with rc 2, running nothing
#   8  the EMPTY SELECTION: a scratch driver whose object-init row tallies nothing exits != 0
#      and names the suite, default and strict; the real row still exits 0 (axis 4)
# MUTATIONS (6.6.11, each RED; measured):
#   M6 `_gate_score` drops its 77 branch (77 -> `_check` -> FAIL)          -> axis 6 RED
#   M7 `_gate` calls `_check` directly again (bypasses `_gate_score`)      -> axis 6 RED
#   M8 check.sh's `_chk_gate` 77 branch removed (77 -> the FAIL arm)       -> axis 7 RED
#   M9 `_chk_read_no_skip` never called (NO_SKIP ignored by check.sh)       -> axis 7 RED
#   M10 main()'s `only >= 0 && G_TOTAL == 0` check removed                  -> axis 8 RED
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
cp "$D/drv" "$D/drv0"

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

# ── 6.6.11: scratch drivers built from THIS tree with one row body swapped ─────────────────
# `mkdrv <out> <replacement>` copies programs/checks/ into a scratch source tree (lib/ is a
# symlink — nothing under $ROOT is written), replaces the `_object_init_gate();` call inside
# `fn _row_object_init` with <replacement>, and builds it. The row is the SAME one `object-init`
# selects, so the real selector, run loop and verdict code run around it.
mkdrv() {
    _t="$D/src_$1"
    mkdir -p "$_t/programs"
    cp -R "$ROOT/programs/checks" "$_t/programs/"
    ln -s "$ROOT/lib" "$_t/lib"
    awk -v rep="$2" '
        /^fn _row_object_init\(/ { inrow = 1 }
        inrow && /_object_init_gate\(\);/ { print rep; hit = 1; next }
        inrow && /^}/ { inrow = 0 }
        { print }
        END { if (!hit) exit 3 }' "$ROOT/programs/checks/main.cyr" > "$_t/programs/checks/main.cyr" \
        || { _fail "mkdrv $1: fn _row_object_init no longer calls _object_init_gate(); — re-anchor this gate"; return 1; }
    ( cd "$_t" && cat programs/checks/main.cyr | "$CC" > "$D/$1" 2>"$D/$1.err" ) \
        || { cat "$D/$1.err"; _fail "mkdrv $1: the scratch driver does not compile"; return 1; }
    chmod +x "$D/$1"
}
mkdir -p "$R/tests/gates/zzskip"
printf '#!/bin/sh\necho "SKIP: zzskip/s77 — the fake tool is not installed"\nexit 77\n' > "$R/tests/gates/zzskip/s77.sh"
printf '#!/bin/sh\necho "PASS: zzskip/ok"\nexit 0\n' > "$R/tests/gates/zzskip/ok.sh"

echo "axis 6: the DRIVER path — a shell gate's exit 77 is a SKIP row, a FAIL under NO_SKIP=1"
if mkdrv drv77 '    _gate("zz fake skip gate", "tests/gates/zzskip/s77.sh");'; then
    cp "$D/drv77" "$D/drv"
    ROW=object-init
    run "$D/a6" CYRIUS_CHECK_NO_SKIP=
    [ "$(cat "$D/a6.rc")" = 0 ] || _fail "axis 6: a gate that exited 77 made the default run exit $(cat "$D/a6.rc"), expected 0 (a SKIP is not a failure by default)"
    grep -q '^  SKIP: zz fake skip gate — the gate exited 77' "$D/a6" || _fail "axis 6: no 'SKIP: zz fake skip gate — the gate exited 77' row"
    grep -q '^  PASS: zz fake skip gate' "$D/a6" && _fail "axis 6: a gate that exited 77 was scored PASS"
    grep -q '^  FAIL: zz fake skip gate' "$D/a6" && _fail "axis 6: a gate that exited 77 was scored FAIL by default"
    grep -qx '0 passed, 0 failed, 1 skipped (1 total)' "$D/a6" \
        || _fail "axis 6: tally is '$(grep -E 'passed,' "$D/a6" | tail -1)', expected '0 passed, 0 failed, 1 skipped (1 total)'"
    run "$D/a6s" CYRIUS_CHECK_NO_SKIP=1
    [ "$(cat "$D/a6s.rc")" != 0 ] || _fail "axis 6: under CYRIUS_CHECK_NO_SKIP=1 a gate that exited 77 still exited 0"
    grep -q 'SKIP REFUSED.*the gate exited 77' "$D/a6s" || _fail "axis 6: under NO_SKIP=1 the failure does not say the gate exited 77"
    grep -qx '0 passed, 1 failed, 0 skipped (1 total)' "$D/a6s" \
        || _fail "axis 6: strict tally is '$(grep -E 'passed,' "$D/a6s" | tail -1)', expected '0 passed, 1 failed, 0 skipped (1 total)'"
    cp "$D/drv0" "$D/drv"
fi
# `--gate-row` — the one-gate mode other gates use to drive the real `_gate_run` path.
for mode in default strict; do
    _v=; [ "$mode" = strict ] && _v=1
    _rc=0
    ( cd "$R" && env CYRIUS_CHECK_NO_SKIP=$_v "$D/drv0" --gate-row tests/gates/zzskip/s77.sh ) > "$D/a6g.raw" 2>&1 || _rc=$?
    strip_ansi < "$D/a6g.raw" > "$D/a6g"
    if [ "$mode" = default ]; then
        { [ "$_rc" = 0 ] && grep -q '^  SKIP: tests/gates/zzskip/s77.sh' "$D/a6g"; } \
            || _fail "axis 6: --gate-row over a 77 gate: rc $_rc, expected 0 and a SKIP row"
    else
        { [ "$_rc" != 0 ] && grep -q '^  FAIL: tests/gates/zzskip/s77.sh' "$D/a6g"; } \
            || _fail "axis 6: --gate-row over a 77 gate under NO_SKIP=1: rc $_rc, expected != 0 and a FAIL row"
    fi
done

echo "axis 7: the CHECK.SH path — _chk_gate scores 77 as SKIP, and reads CYRIUS_CHECK_NO_SKIP"
# The REAL scripts/check.sh and the REAL driver (its `--run-gate` supervisor passes 77 through)
# over a fake bucket, in a scratch root. CYRIUS_HOME is set, so check.sh stages no home.
W7="$D/w7"
mkdir -p "$W7/scripts" "$W7/build" "$W7/programs/checks" "$W7/lib" "$W7/tests/gates/zzskip" "$W7/home"
cp "$ROOT/scripts/check.sh" "$W7/scripts/check.sh"
cp "$ROOT/VERSION" "$W7/"
: > "$W7/lib/placeholder.cyr"
: > "$W7/programs/checks/placeholder.cyr"
printf '#!/bin/sh\nexit 0\n' > "$W7/build/cycc"; chmod +x "$W7/build/cycc"
cp "$D/drv0" "$W7/build/cyrius_check"
touch -d '2038-01-01' "$W7/build/cyrius_check"
cp "$R/tests/gates/zzskip/s77.sh" "$R/tests/gates/zzskip/ok.sh" "$W7/tests/gates/zzskip/"
printf '_chk_gate "$ROOT/tests/gates/zzskip/s77.sh"\n_chk_gate "$ROOT/tests/gates/zzskip/ok.sh"\n' >> "$W7/scripts/check.sh"
run7() {  # $1 = out, $2 = CYRIUS_CHECK_NO_SKIP value
    _rc=0
    ( cd "$W7" && env CYRIUS_HOME="$W7/home" CYRIUS_CHECK_NO_SKIP="$2" sh scripts/check.sh zzskip ) \
        > "$1.raw" 2>&1 || _rc=$?
    strip_ansi < "$1.raw" > "$1"
    echo "$_rc" > "$1.rc"
}
run7 "$D/a7" ""
[ "$(cat "$D/a7.rc")" = 0 ] || _fail "axis 7: check.sh with a 77 gate exited $(cat "$D/a7.rc") by default, expected 0"
grep -q 'SKIP (exit 77.*zzskip/s77.sh' "$D/a7" || _fail "axis 7: check.sh printed no SKIP line for the 77 gate"
grep -q 'FAILED (exit 77)' "$D/a7" && _fail "axis 7: check.sh scored the 77 gate as a FAILURE by default"
grep -q '^  skipped:     1 ' "$D/a7" || _fail "axis 7: the summary does not count 1 skipped gate"
grep -q '^    tests/gates/zzskip/s77.sh$' "$D/a7" || _fail "axis 7: the summary's SKIPPED list does not name the 77 gate"
grep -q '2 of 2 produced a result, 0 NOT RUN' "$D/a7" || _fail "axis 7: a SKIP was not counted as a result (bookkeeping: $(grep 'produced a result' "$D/a7"))"
grep -q 'ALL GREEN' "$D/a7" && _fail "axis 7: a run with a SKIPPED gate still says ALL GREEN"
run7 "$D/a7s" 1
[ "$(cat "$D/a7s.rc")" != 0 ] || _fail "axis 7: under CYRIUS_CHECK_NO_SKIP=1 check.sh with a 77 gate exited 0"
grep -q 'SKIP REFUSED.*zzskip/s77.sh' "$D/a7s" || _fail "axis 7: under NO_SKIP=1 check.sh does not say the SKIP was refused"
grep -qE '^    FAIL tests/gates/zzskip/s77.sh$' "$D/a7s" || _fail "axis 7: under NO_SKIP=1 the 77 gate is not listed as FAILED"
grep -qE '^    FAIL tests/gates/zzskip/ok.sh$' "$D/a7s" && _fail "axis 7: under NO_SKIP=1 the PASSING gate was failed too (positive control)"
run7 "$D/a7y" yes
[ "$(cat "$D/a7y.rc")" = 2 ] || _fail "axis 7: CYRIUS_CHECK_NO_SKIP=yes made check.sh exit $(cat "$D/a7y.rc"), expected 2"
grep -q "CYRIUS_CHECK_NO_SKIP.*'yes'" "$D/a7y" || _fail "axis 7: check.sh's refusal does not name the variable and the value"
grep -q 'zzskip/' "$D/a7y" && _fail "axis 7: a refused CYRIUS_CHECK_NO_SKIP still ran a gate"

echo "axis 8: a selected suite that ran NO rows is a failure, default and strict"
if mkdrv drvempty '    # (emptied by check_driver_skip_is_not_pass.sh axis 8)'; then
    for _v in "" 1; do
        _rc=0
        ( cd "$R" && env CYRIUS_CHECK_NO_SKIP=$_v "$D/drvempty" object-init ) > "$D/a8.raw" 2>&1 || _rc=$?
        strip_ansi < "$D/a8.raw" > "$D/a8"
        [ "$_rc" != 0 ] || _fail "axis 8: an object-init row that tallied nothing exited 0 (CYRIUS_CHECK_NO_SKIP='$_v')"
        grep -q "^FAIL: suite 'object-init' ran no rows" "$D/a8" \
            || _fail "axis 8: no \"FAIL: suite 'object-init' ran no rows\" line (CYRIUS_CHECK_NO_SKIP='$_v')"
    done
fi

echo ""
if [ "$FAILS" -gt 0 ]; then
    echo "FAIL: $NAME — $FAILS check(s) failed"
    exit 1
fi
echo "PASS: $NAME (a missing prerequisite is a SKIP row and a SKIP count, a FAIL under CYRIUS_CHECK_NO_SKIP=1, $NSK skip sites, 0 scored as passes; a shell gate's exit 77 is a SKIP in both the driver and check.sh; an empty selection fails)"
exit 0

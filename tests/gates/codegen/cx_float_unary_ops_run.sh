#!/bin/sh
# cx_float_unary_ops_run.sh — 6.6.10. f64_sqrt / f64_floor / f64_ceil / f64_round and mulh64
# compute on the cx bytecode target, and the crossos .tcyr files that pin them RUN on cxvm.
# 6.6.13 adds f64_le / f64_ge / f64_trunc (builtins since; trunc is the new 0x6E ftrunc).
#
# THE DEFECT. The five cx emitters were `return 0` stubs (src/backend/cx/emit.cyr), so the
# operand stayed in r0 and was the "result": sqrt(4.0) = 4.0, floor/ceil/round(2.5) = 2.5,
# mulh64(2^32, 2^32) = 2^32. Silent. The fix emits cxvm's existing fsqrt (0x68) and the new
# host-backed ffloor / fceil / fround / mulhu opcodes (0x6A-0x6D, programs/cxvm.cyr).
#
# WHY A GATE. The crossos corpus runs NATIVELY on the four hosts; nothing ran these files on
# cxvm, so a cx row in them proved nothing. This gate builds cycc_cx and cxvm from source (so a
# revert turns it RED, not a stale build/ binary), compiles each file for cx, runs it on cxvm,
# and requires exit 0 AND an assertion count equal to the one derived from the source by grep —
# a harness that silently stopped asserting cannot pass. It also runs each file natively, so a
# cx green cannot come from a file that is vacuous everywhere.
#
# MUTATION (6.6.10, built and run): restore the five `return 0` stubs → cx_float_unary_ops.tcyr
# reports 26 FAILs and f64_negation.tcyr 1 (its sqrt row, enabled on cx in the same change),
# both exit non-zero → RED. Drop only cxvm's 0x6A-0x6D arms → the floor/ceil/round/mulh64 rows
# read back the unchanged operand (an unknown cxvm opcode is a no-op) → RED. Native leg: change
# one expected value → the native run reports "27 passed, 1 failed" and exits 1 → RED; restore
# the old top-level `main(); var r = assert_summary();` ending → main's second run prints after
# the summary → RED (and with a failing row it still exits 0, which the count check catches).
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL cx_float_unary_ops_run: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL cx_float_unary_ops_run: mktemp -d failed"; exit 1; }
trap 'rm -rf "$T"' EXIT
cd "$ROOT" || exit 1
ulimit -c 0

"$CC" < src/main_cx.cyr > "$T/cycc_cx" 2> "$T/eb" || { echo "FAIL cx_float_unary_ops_run: could not build src/main_cx.cyr"; sed -n 1,3p "$T/eb"; exit 1; }
"$CC" < programs/cxvm.cyr > "$T/cxvm" 2> "$T/eb" || { echo "FAIL cx_float_unary_ops_run: could not build programs/cxvm.cyr"; sed -n 1,3p "$T/eb"; exit 1; }
chmod +x "$T/cycc_cx" "$T/cxvm"
fail=0
pass=0
_bad() { echo "  FAIL: $1"; fail=$((fail + 1)); }

# check <tcyr> <floor> — cx: compile, run on cxvm, exit 0, "<N> passed, 0 failed" with N == the
# source's assertion count on cx (cx-disabled rows sit between #ifndef CYRIUS_TARGET_CX/#endif).
check() {
  f=$1
  want=$(awk '/^#ifndef CYRIUS_TARGET_CX/{skip=1; next} /^#endif/{skip=0; next} !skip && /^[[:space:]]*assert_(eq|neq)\(/{n++} END{print n+0}' "$f")
  if [ "$want" -lt "$2" ]; then _bad "$f: only $want cx assertions in the source (floor $2)"; return; fi
  "$T/cycc_cx" < "$f" > "$T/o.cyx" 2> "$T/e"; rc=$?
  if [ "$rc" -ne 0 ]; then _bad "$f: cycc_cx rc $rc"; grep '^error' "$T/e" | head -3 | sed 's/^/      /'; return; fi
  "$T/cxvm" < "$T/o.cyx" > "$T/out" 2>&1; vrc=$?
  if [ "$vrc" -ne 0 ]; then _bad "$f on cxvm: exit $vrc"; grep 'FAIL' "$T/out" | head -5 | sed 's/^/      /'; return; fi
  if ! grep -q "^$want passed, 0 failed" "$T/out"; then _bad "$f on cxvm: expected '$want passed, 0 failed', got: $(tail -1 "$T/out")"; return; fi
  pass=$((pass + 1))
  # Natively every assertion row is compiled in (no #ifndef CYRIUS_TARGET_CX skip), and the
  # count must match too: rc 0 alone is not evidence — a file that let cycc auto-call main a
  # second time exited with main's constant return value whatever the summary said (6.6.10).
  nwant=$(grep -cE '^[[:space:]]*assert_(eq|neq)\(' "$f")
  "$CC" < "$f" > "$T/nat" 2> "$T/e" && chmod +x "$T/nat" && "$T/nat" > "$T/out" 2>&1; nrc=$?
  if [ "$nrc" -ne 0 ]; then _bad "$f natively: rc $nrc — the file must pass on the host too"; grep 'FAIL' "$T/out" | head -3 | sed 's/^/      /'; return; fi
  if ! grep -q "^$nwant passed, 0 failed" "$T/out"; then _bad "$f natively: expected '$nwant passed, 0 failed', got: $(grep 'passed,' "$T/out" | tail -1)"; return; fi
  if ! tail -1 "$T/out" | grep -q "^$nwant passed, 0 failed"; then _bad "$f natively: output continues after the summary (main ran a second time): $(tail -1 "$T/out")"; return; fi
  pass=$((pass + 1))
}
check tests/tcyr/crossos/cx_float_unary_ops.tcyr 28
check tests/tcyr/crossos/f64_negation.tcyr 38
# 6.6.13 — f64_le / f64_ge (fle / fge) and f64_trunc (0x6E ftrunc) became builtins.
check tests/tcyr/crossos/f64_le_ge_trunc_builtins.tcyr 39

# The cxvm opcode table documents what the VM executes.
for op in 0x6A 0x6B 0x6C 0x6D 0x6E; do
  if grep -q "^#   $op = " programs/cxvm.cyr; then pass=$((pass + 1)); else _bad "programs/cxvm.cyr: the header opcode table does not list $op"; fi
done

if [ "$fail" -ne 0 ]; then echo "FAIL cx_float_unary_ops_run: $fail row(s) red, $pass green"; exit 1; fi
echo "PASS cx_float_unary_ops_run: $pass rows — f64_sqrt/floor/ceil/round/trunc, f64_le/ge + mulh64 compute on cxvm (the three crossos files pass on cx AND natively, assertion counts derived from source), opcode table current"
exit 0

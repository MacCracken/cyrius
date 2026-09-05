#!/bin/sh
# ir_edges_scaling.sh — v6.5.54. ir_build_edges resolves jump targets within a function,
# not by scanning the whole program.
#
# WHY. _ir_find_bb_for_patch scanned every BB of the PROGRAM and every node inside each of
# them, once per forward jump; _ir_find_bb_for_cp scanned every BB once per backward jump.
# On a cycc self-compile that is 29,499 BBs, and CYRIUS_IR=3 took 13,967 ms against the
# default path's 672 ms — 21x. The cost was ENTIRELY here: with CYRIUS_FOLD_OFF,
# CYRIUS_LASE_OFF, CYRIUS_DCE_CAP=0 and CYRIUS_DSE_CAP=0 all set it was still 13,910 ms.
# Starting each scan at the first BB of the jump's own function drops it to ~1,012 ms.
#
# ⭐ PINS THE PROPERTY (cost), NOT THE MECHANISM. It does not grep for `fn_lo`: any
# indexing scheme that keeps target resolution sub-quadratic passes. A gate that checked for
# the hint variable would pass while the scan was quietly made quadratic again elsewhere.
#
# ⚠ RATIO, not absolute time, and both halves measured back-to-back on the same box, so load
# affects them together. The bound is 5x against a measured 1.5x and a pre-fix 20.8x — wide
# enough that a busy machine cannot flip it, tight enough that restoring either full-program
# scan does (mutation-proven: reverting to a scan from BB 0 gives ~21x).
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
CC="$R/build/cycc"
[ -x "$CC" ] || { echo "FAIL ir_edges_scaling: no build/cycc"; exit 1; }

"$CC" < "$R/src/main.cyr" > "$T/stage1" 2>/dev/null || { echo "FAIL ir_edges_scaling: stage1 build failed"; exit 1; }
chmod +x "$T/stage1"

ms() {
  s=$(date +%s%N)
  env "$@" "$T/stage1" < "$R/src/main.cyr" > /dev/null 2>&1 || { echo "-1"; return; }
  e=$(date +%s%N)
  echo $(( (e - s) / 1000000 ))
}
BASE=$(ms CYRIUS_IR=)
IR3=$(ms CYRIUS_IR=3)
if [ "$BASE" -le 0 ] || [ "$IR3" -le 0 ]; then echo "FAIL ir_edges_scaling: a timed compile failed"; exit 1; fi
if [ "$BASE" -lt 50 ]; then echo "FAIL ir_edges_scaling: baseline ${BASE}ms implausibly fast — did the compile run?"; exit 1; fi

# integer ratio x100 to avoid floating point
R100=$(( IR3 * 100 / BASE ))
if [ "$R100" -ge 500 ]; then
  echo "FAIL ir_edges_scaling: CYRIUS_IR=3 is ${IR3}ms vs ${BASE}ms default (${R100}% — bound is 500%)."
  echo "  ir_build_edges is resolving jump targets by scanning the whole program again."
  exit 1
fi
echo "PASS ir_edges_scaling: IR=3 ${IR3}ms vs ${BASE}ms default (${R100}% of baseline, bound 500%)"
exit 0

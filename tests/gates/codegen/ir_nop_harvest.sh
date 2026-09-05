#!/bin/sh
# ir_nop_harvest.sh — v6.5.54. The NOP-harvest compactor runs under IR mode, and an
# IR-built cycc is a WORKING compiler.
#
# WHY. The compactor deletes the NOP runs that regalloc and frame-trim leave behind. It was
# gated `IR_ENABLED(S) == 0` — off for every IR mode — so CYRIUS_IR=3 shipped every one of
# them: MEASURED at 19,067 NOP instructions in a cycc self-compile against the default path's
# 44, i.e. +65,320 bytes of .text (+6.2%). 10,748 of those were plain regalloc NOPs this pass
# already knew how to collect.
#
# ⭐ THE GATE IS NOT ABOUT NOP COUNT — IT IS ABOUT CP REPAIR. The gate could not simply be
# lifted: the IR records a code position per node, the compactor MOVES code, and the IR
# fixpoint then reads and rewrites at stale offsets. Lifting the gate WITHOUT the stage-3c
# repair in parse_fn.cyr produces a cycc that dies at startup with `alloc_init: mmap failed`.
# So step 3 below — the IR-built compiler must reproduce the default compiler byte-identically
# — is the real assertion; the NOP bound just proves the pass actually ran.
#
# ⚠ Builds stage1 FROM SOURCE and measures what stage1 emits. The harvesting behaviour under
# test lives in the compiler being built, not in build/cycc, so a source revert flips this gate
# RED (mutation-proven: reverting the gate to `IR_ENABLED(S) == 0` gives 19,067 NOPs).
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
CC="$R/build/cycc"
[ -x "$CC" ] || { echo "FAIL ir_nop_harvest: no build/cycc"; exit 1; }

"$CC" < "$R/src/main.cyr" > "$T/stage1" 2>"$T/e1" || { echo "FAIL ir_nop_harvest: stage1 build failed"; sed -n 1,3p "$T/e1"; exit 1; }
chmod +x "$T/stage1"

CYRIUS_IR=3 "$T/stage1" < "$R/src/main.cyr" > "$T/ir3" 2>"$T/e2" || { echo "FAIL ir_nop_harvest: IR=3 build failed"; sed -n 1,3p "$T/e2"; exit 1; }
chmod +x "$T/ir3"

# 1. the pass ran: NOP count must be far below the un-harvested 19,067.
N=$(llvm-objdump -d "$T/ir3" 2>/dev/null | grep -cE '\bnopl?\b|\bnop\b')
if [ -z "$N" ] || [ "$N" -eq 0 ]; then echo "FAIL ir_nop_harvest: could not count NOPs (llvm-objdump missing?)"; exit 1; fi
if [ "$N" -ge 14000 ]; then
  echo "FAIL ir_nop_harvest: IR=3 build carries $N NOP instructions (un-harvested baseline was 19067,"
  echo "  harvested is ~8250). The compactor is not running under IR mode."
  exit 1
fi

# 2. no size regression against the default path.
SD=$(stat -c%s "$T/stage1"); SI=$(stat -c%s "$T/ir3")
D=$(( SI - SD )); [ "$D" -lt 0 ] && D=$(( -D ))
if [ "$D" -gt 20000 ]; then
  echo "FAIL ir_nop_harvest: IR=3 build is $SI B vs default $SD B (delta $D). Un-harvested delta was +65320."
  exit 1
fi

# 3. THE REAL ASSERTION: the IR-built compiler works and is a fixpoint with the default one.
"$T/ir3" < "$R/src/main.cyr" > "$T/ir3out" 2>"$T/e3"
rc=$?
if [ $rc -ne 0 ]; then
  echo "FAIL ir_nop_harvest: the IR=3-built cycc cannot compile (rc=$rc) — stale IR node CPs."
  sed -n 1,3p "$T/e3"; exit 1
fi
if ! cmp -s "$T/ir3out" "$T/stage1"; then
  echo "FAIL ir_nop_harvest: the IR=3-built cycc does not reproduce the default cycc."
  echo "  This is the stale-IR_NODE_CP failure (stage 3c in parse_fn.cyr)."
  exit 1
fi

echo "PASS ir_nop_harvest: IR=3 build $N NOPs, ${SI}B vs ${SD}B default, reproduces default cycc"
exit 0

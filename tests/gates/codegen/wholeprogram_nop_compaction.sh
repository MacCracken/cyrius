#!/bin/sh
# wholeprogram_nop_compaction.sh — v6.5.68. The NOP runs the IR passes write AFTER every
# per-function compaction has run are collected, and the compacted compiler is a WORKING
# compiler that emits exactly the same bytes as the uncompacted one.
#
# ⛔ WHY A SECOND COMPACTOR. `_PARSE_FN_DEF_IMPL`'s pass runs per function during parsing;
# the IR fixpoint runs once, after all parsing, into a table that has already been consumed
# and reset 1,275 times. v6.5.54 recovered the 10,748 bytes that were plain regalloc runs by
# lifting that pass's IR gate and left this residual explicitly open.
#
# ⭐ THE ASSERTION THAT MATTERS IS #3, NOT THE BYTE COUNT. Moving code invalidates every
# stored code position in the compiler, and ONE unrepaired table is a silent miscompile —
# v6.5.54 demonstrated exactly that by lifting the gate without repairing `IR_NODE_CP` and
# getting a cycc that died with `alloc_init: mmap failed`. Seven position tables are repaired
# (disp32 sources, fixup CPs, fn starts, fn ends, switch tables, IR node CPs, and the entry
# trampoline's hand-emitted disp32, which is in no emitter's registry at all). A byte count
# proves the pass ran; only compiling with the result proves it was repaired correctly.
#
# ⚠ MUTATION-PROVEN, each with the mutant binary first checked to DIFFER from the original
# (a mutation that silently does not apply proves nothing — the v6.5.54 stage-3c lesson):
#   entry-trampoline unregistered -> compacted cycc rc=139 (axis 2 RED)
#   fn start/end repair removed   -> compacted cycc rc=139 (axis 2 RED)
# ⚠ AND ONE THAT DID NOT: disabling run COALESCING changes nothing measurable — the compacted
# compiler still self-hosts and the corpus still passes. Coalescing is retained because two
# producers CAN register the same span (a node inside a const-folded span may itself be
# IR_ELIMINATED, and an overlap would both double-count the prefix sum and defeat the move
# loop's `rp == run.cp` test), but no input reaches that state today. It is unproven
# insurance and is recorded as such rather than listed as a proof.
# ⚠ The first attempt at that mutation was WRONG in a way worth recording: setting `rq = n`
# skipped the merge loop AND collapsed the table to a single run, i.e. it turned the pass
# into something safe instead of something broken, and reported a clean PASS. A mutation
# that neuters rather than corrupts proves nothing.
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
CC="$R/build/cycc"
[ -x "$CC" ] || { echo "FAIL wholeprogram_nop_compaction: no build/cycc"; exit 1; }

# Build stage1 FROM SOURCE — the pass under test lives in the compiler being built, so a
# source revert must flip this gate RED rather than be masked by a stale build/cycc.
"$CC" < "$R/src/main.cyr" > "$T/stage1" 2>"$T/e1" || {
  echo "FAIL wholeprogram_nop_compaction: stage1 build failed"; sed -n 1,3p "$T/e1"; exit 1; }
chmod +x "$T/stage1"

# ── axis 1 — the pass RUNS and reports a non-trivial harvest ─────────────────────────────
CYRIUS_IR=3 "$T/stage1" < "$R/src/main.cyr" > "$T/ir3" 2>"$T/e2" || {
  echo "FAIL wholeprogram_nop_compaction axis1: IR=3 build failed"; sed -n 1,3p "$T/e2"; exit 1; }
chmod +x "$T/ir3"
line=$(grep -a 'wp-compact:' "$T/e2" | head -1)
[ -n "$line" ] || { echo "FAIL wholeprogram_nop_compaction axis1: no wp-compact line — the pass did not run."; exit 1; }
BYTES=$(echo "$line" | sed 's/wp-compact: \([0-9]*\) bytes.*/\1/')
[ "$BYTES" -ge 5000 ] || {
  echo "FAIL wholeprogram_nop_compaction axis1: only $BYTES bytes reclaimed (expected >=5000;"
  echo "  measured 8,292 at v6.5.68). The IR passes' NOP runs are not reaching the registry."
  exit 1; }

# ── axis 2 — THE REAL ASSERTION: the compacted compiler WORKS and is byte-exact ──────────
# A compactor that deletes the right number of bytes and repairs one table wrongly still
# passes axis 1. This is the assertion that catches it, and it is the one v6.5.54's
# equivalent failure (`alloc_init: mmap failed`) would have tripped.
"$T/ir3" < "$R/src/main.cyr" > "$T/ir3out" 2>"$T/e3"
rc=$?
[ $rc -eq 0 ] || {
  echo "FAIL wholeprogram_nop_compaction axis2: the compacted cycc cannot compile (rc=$rc)."
  echo "  A position table was moved without being repaired."; sed -n 1,3p "$T/e3"; exit 1; }
cmp -s "$T/ir3out" "$T/stage1" || {
  echo "FAIL wholeprogram_nop_compaction axis2: the compacted cycc does not reproduce the"
  echo "  uncompacted one. Compaction changed WHAT the compiler emits, not just where it sits."
  exit 1; }

# ── axis 3 — SIZE CONTROL: the harvest must actually shrink the binary ───────────────────
# Anti-vacuous companion to axis 1: a pass that "reclaims" bytes without shrinking `.text`
# has not moved anything, and axes 1-2 would both still pass.
SD=$(stat -c%s "$T/stage1"); SI=$(stat -c%s "$T/ir3")
[ "$SI" -lt "$SD" ] || {
  echo "FAIL wholeprogram_nop_compaction axis3: IR=3 build is $SI B against the default $SD B."
  echo "  $BYTES bytes were reported reclaimed but the binary did not shrink."
  exit 1; }

# ── axis 4 — ANTI-VACUOUS: the DEFAULT path must be untouched ────────────────────────────
# The registries record on every compile, including default builds where nothing is
# harvested. If recording alone changed a single emitted byte, every non-IR build in the
# ecosystem would silently change — so this row pins that the pass is inert without IR.
"$T/stage1" < "$R/tests/tcyr/lang/regression.tcyr" > "$T/reg_new" 2>/dev/null || {
  echo "FAIL wholeprogram_nop_compaction axis4: probe did not compile"; exit 1; }
"$CC" < "$R/tests/tcyr/lang/regression.tcyr" > "$T/reg_ref" 2>/dev/null || {
  echo "FAIL wholeprogram_nop_compaction axis4: probe did not compile with build/cycc"; exit 1; }
cmp -s "$T/reg_new" "$T/reg_ref" || {
  echo "FAIL wholeprogram_nop_compaction axis4: recording alone changed the DEFAULT-path output."
  echo "  The pass must be inert when no IR NOPs exist."
  exit 1; }

# ── axis 5 — behavioural: a compaction-heavy program must still give the right answer ────
# Bytes moving under a running program is the failure this whole slot risks, and a
# byte-identity check on cycc cannot see a program shape cycc itself does not contain.
cat > "$T/probe.cyr" <<'EOF'
include "lib/syscalls.cyr"
fn work(n) {
    var acc = 0; var i = 0;
    while (i < n) {
        var dead = i * 3 + 7;
        if (i % 2 == 0) { acc = acc + i; } else { acc = acc + (n / (i + 1)); }
        i = i + 1;
    }
    return acc;
}
fn main(): i64 {
    var a = work(20);
    var b = work(7);
    syscall(60, (a + b) & 0xFF);
    return 0;
}
var e = main();
EOF
"$T/stage1" < "$T/probe.cyr" > "$T/p_d" 2>/dev/null; chmod +x "$T/p_d"; "$T/p_d"; want=$?
CYRIUS_IR=3 "$T/stage1" < "$T/probe.cyr" > "$T/p_i" 2>/dev/null; chmod +x "$T/p_i"; "$T/p_i"; got=$?
[ "$got" -eq "$want" ] || {
  echo "FAIL wholeprogram_nop_compaction axis5: IR=3+compaction gives $got where the default"
  echo "  path gives $want. A jump displacement or a fixup CP was repaired wrongly."
  exit 1; }

echo "PASS wholeprogram_nop_compaction: $BYTES B reclaimed, compacted cycc reproduces the uncompacted one byte-identically, default path inert, behaviour preserved"
exit 0

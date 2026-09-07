#!/bin/sh
# dce_eliminates.sh — v6.5.72. `CYRIUS_DCE=1` REMOVES dead code instead of padding it.
#
# ⛔ WHY. The flag found unreachable functions, overwrote their bodies with 0x90, and reclaimed
# ZERO bytes — while the default-path message told users to "set CYRIUS_DCE=1 to eliminate".
# Measured before this release: 76 unreachable fns, 34,847 bytes, recognised, padded, shipped,
# binary byte-for-byte the same size. The pass's own comment called that an "intentional
# tradeoff" because "code shifting would break cycc==cycc byte-identity" — which v6.5.68
# disproved: compaction is deterministic, so a compacted compiler reaches the same fixpoint.
#
# ⭐ AXIS 2 IS THE LOAD-BEARING ONE. Moving code invalidates every stored code position, and one
# unrepaired table is a silent miscompile. It took four attempts and six distinct causes:
#   1. a binary search (`_wp_inside`) called before its table was sorted;
#   2. `dbase` recomputed after compaction — data does NOT follow code (`.rodata`/`.bss` land at
#      identical vaddrs either way), so recomputing relocated every data reference;
#   3. the fixup patch loop extracted into its own function — which breaks the SEED chain, cybs
#      cannot compile it — so the sites are repaired arithmetically instead;
#   4. the position registries gated on `IR_ENABLED`, correct when written and silently EMPTY
#      for this new consumer;
#   5. the fixup repair placed AFTER the CP shift, so it wrote at post-compaction coordinates
#      into a buffer that had not moved (3 corrupted bodies in a 5-line program, 147 in cycc);
#   6. ftype-3 fixups — absolute function ADDRESSES behind indirect calls — never repaired,
#      which no body-level check can see because every body still decodes.
# A byte count proves the pass ran. Only compiling WITH the result proves it was repaired.
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
CC="$R/build/cycc"
[ -x "$CC" ] || { echo "FAIL dce_eliminates: no build/cycc"; exit 1; }

"$CC" < "$R/src/main.cyr" > "$T/stage1" 2>"$T/e1" || {
  echo "FAIL dce_eliminates: stage1 build failed"; sed -n 1,3p "$T/e1"; exit 1; }
chmod +x "$T/stage1"

# ── axis 1 — the binary actually SHRINKS ────────────────────────────────────────────────
CYRIUS_DCE=1 "$T/stage1" < "$R/src/main.cyr" > "$T/dce" 2>"$T/e2" || {
  echo "FAIL dce_eliminates axis1: the DCE build failed"; sed -n 1,3p "$T/e2"; exit 1; }
chmod +x "$T/dce"
grep -qa 'bytes of dead code eliminated' "$T/e2" || {
  echo "FAIL dce_eliminates axis1: no elimination line — the pass did not run."; exit 1; }
SP=$(stat -c%s "$T/stage1"); SD=$(stat -c%s "$T/dce")
[ "$SD" -lt "$SP" ] || {
  echo "FAIL dce_eliminates axis1: DCE build is $SD B against $SP B — dead code was reported"
  echo "  eliminated but the binary did not shrink. That is the pre-v6.5.72 behaviour: NOP-fill."
  exit 1; }
SAVED=$(( SP - SD ))
[ "$SAVED" -ge 16384 ] || { echo "FAIL dce_eliminates axis1: only $SAVED bytes reclaimed (expected >=16384; measured 36,864)"; exit 1; }

# ── axis 2 — THE REAL ASSERTION: the eliminated compiler WORKS and is byte-exact ─────────
"$T/dce" < "$R/src/main.cyr" > "$T/dceout" 2>"$T/e3"
rc=$?
[ $rc -eq 0 ] || {
  echo "FAIL dce_eliminates axis2: the eliminated cycc cannot compile (rc=$rc)."
  echo "  rc=139 -> a position table was moved without being repaired."
  echo "  rc=132 -> an indirect call target is stale (ftype-3 fixups)."
  sed -n 1,3p "$T/e3"; exit 1; }
cmp -s "$T/dceout" "$T/stage1" || {
  echo "FAIL dce_eliminates axis2: the eliminated cycc does not reproduce the normal build."
  echo "  Elimination changed WHAT the compiler emits, not just where it sits."
  exit 1; }

# ── axis 3 — the SELF-AUDIT is present and is BASELINE-RELATIVE ──────────────────────────
# The pass walks every surviving live body with the length decoder and refuses to emit if one
# stopped decoding. ⚠ It must compare against a pre-elimination baseline: the first cut
# asserted absolutely and blocked 240 of 301 corpus programs, every one of them for a DECODER
# gap (`fmt_float_buf` uses `0F 3A` roundsd) rather than for corruption. This row pins that a
# float-formatting program — the one that exposed that gap — still compiles under DCE.
cat > "$T/a3.cyr" <<'EOF'
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/vec.cyr"
include "lib/syscalls.cyr"
fn main(): i64 {
    alloc_init();
    # `fmt_float` is the point: its body is what carries `0F 3A` (roundsd), the opcode the
    # length decoder bailed on until v6.5.72. The RESULT is irrelevant here — the exit code is
    # fixed so the row compares compile-and-run behaviour, not floating-point formatting.
    var s = fmt_float(f64_div(f64_from(22), f64_from(7)), 4);
    syscall(60, 7);
    return 0;
}
var e = main();
EOF
"$T/stage1" < "$T/a3.cyr" > "$T/a3p" 2>/dev/null || { echo "SKIP dce_eliminates axis3: float probe needs fmt_float"; exit 0; }
chmod +x "$T/a3p"; "$T/a3p" >/dev/null 2>&1; want=$?
CYRIUS_DCE=1 "$T/stage1" < "$T/a3.cyr" > "$T/a3d" 2>"$T/a3.err" || {
  echo "FAIL dce_eliminates axis3: a float-formatting program stopped compiling under DCE."
  echo "  If the message names a corrupted body, the audit is firing on a DECODER gap rather"
  echo "  than on real corruption — it must be baseline-relative."
  grep -m2 -a 'error' "$T/a3.err" | sed 's/^/    /'; exit 1; }
chmod +x "$T/a3d"; "$T/a3d" >/dev/null 2>&1; got=$?
[ "$got" -eq "$want" ] || { echo "FAIL dce_eliminates axis3: float probe gave $got under DCE, $want without"; exit 1; }

# ── axis 4 — ANTI-VACUOUS: the DEFAULT path is untouched ─────────────────────────────────
"$T/stage1" < "$R/tests/tcyr/lang/regression.tcyr" > "$T/r_new" 2>/dev/null || { echo "FAIL dce_eliminates axis4: probe did not compile"; exit 1; }
"$CC"       < "$R/tests/tcyr/lang/regression.tcyr" > "$T/r_ref" 2>/dev/null || { echo "FAIL dce_eliminates axis4: probe did not compile with build/cycc"; exit 1; }
cmp -s "$T/r_new" "$T/r_ref" || { echo "FAIL dce_eliminates axis4: a DEFAULT-path build changed. Elimination must be inert without CYRIUS_DCE=1."; exit 1; }

echo "PASS dce_eliminates: $SAVED B removed (not padded), eliminated cycc reproduces the normal build byte-identically, float path unaffected, default path inert"
exit 0

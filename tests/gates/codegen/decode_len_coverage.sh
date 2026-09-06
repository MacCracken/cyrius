#!/bin/sh
# decode_len_coverage.sh — v6.5.68. cycc's x86 length decoder must be able to walk every
# function body cycc itself emits, landing exactly on each function's end.
#
# ⛔ WHY THIS EXISTS. `DECODE_LEN` (src/backend/x86/decode.cyr) is load-bearing on the
# DEFAULT path: `RA_SCAN_LOOPS` walks the emitted bytes with it to find backward edges, and
# those edges drive v6.5.35's loop-aware live-interval extension in the register allocator.
# NOTHING verified the decoder against the bytes cyrius actually emits, and two gaps had
# accumulated:
#
#   * `0x99` (CQO) had NO CASE AT ALL. `ECQO` (backend/x86/emit.cyr:282) emits `48 99`
#     before EVERY integer division, so `RA_SCAN_LOOPS` returned -1 — which the picker
#     documents as "no information, NOT no loops" — for every function containing `/` or
#     `%`. Register time-sharing was silently OFF there. 81 sites in cycc's own `.text`.
#   * The two-byte opcodes carrying an imm8 AFTER the ModR/M byte — `0F BA` (BT/BTS/BTR/BTC),
#     `0F 70`-`0F 73` (the PSRL/PSRA/PSLL groups), `0F C2`/`C4`/`C5`/`C6` — returned a length
#     ONE BYTE SHORT. 559 sites across a 39-binary corpus. `48 0F BA F0 3F` (`btr rax, 63`,
#     the f64 tag strip at emit.cyr:3164) is five bytes and the decoder said four.
#
# ⭐ THE SECOND CLASS IS THE DANGEROUS ONE AND IT IS WHY THIS GATE MEASURES A WALK RATHER
# THAN A SIZE. An INCOMPLETE decoder returns 0 and every caller falls back conservatively —
# expensive but safe. A WRONG length desynchronises the walk, so the walker decodes an
# immediate as an opcode and can step straight over a real backward edge, which is precisely
# the v5.6.22 miscompile the loop extension exists to prevent. Measured: the mutant with the
# imm8 fix reverted is byte-for-byte the SAME SIZE as the correct compiler (1,213,864 B
# both) — a size or NOP-count assertion cannot see it. Only walking real emitted code can.
#
# ⚠ MUTATION-PROVEN TWO WAYS, and in both cases the mutant binary was first checked to
# DIFFER from the original (a mutation that silently does not apply proves nothing — the
# v6.5.54 stage-3c lesson):
#     CQO case removed        -> 1275 fns, 1247 clean, 28 undecodable
#     imm8 class reverted     -> 1275 fns, 1266 clean,  9 undecodable
#     correct                 -> 1275 fns, 1275 clean,  0 undecodable, 0 desynced
set -u
R=$(cd "$(dirname "$0")/../../.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
CC="$R/build/cycc"
[ -x "$CC" ] || { echo "FAIL decode_len_coverage: no build/cycc"; exit 1; }

# Builds stage1 FROM SOURCE: the decoder under test lives in the compiler being built, so a
# source revert must flip this gate RED rather than being masked by a stale build/cycc.
"$CC" < "$R/src/main.cyr" > "$T/stage1" 2>"$T/e1" || {
  echo "FAIL decode_len_coverage: stage1 build failed"; sed -n 1,3p "$T/e1"; exit 1; }
chmod +x "$T/stage1"

audit() {   # audit <source-file> <label>; sets FNS CLEAN UNDEC DESYNC
  CYRIUS_DECODE_AUDIT=1 "$T/stage1" < "$1" > /dev/null 2>"$T/a.err" || {
    echo "FAIL decode_len_coverage $2: compile failed"; sed -n 1,3p "$T/a.err"; exit 1; }
  line=$(grep -a 'decode-audit:' "$T/a.err" | head -1)
  [ -n "$line" ] || { echo "FAIL decode_len_coverage $2: no decode-audit line — the audit did not run"; exit 1; }
  FNS=$(echo "$line" | sed 's/decode-audit: \([0-9]*\) fns.*/\1/')
  CLEAN=$(echo "$line" | sed 's/.*fns, \([0-9]*\) clean.*/\1/')
  UNDEC=$(echo "$line" | sed 's/.*clean, \([0-9]*\) undecodable.*/\1/')
  DESYNC=$(echo "$line" | sed 's/.*undecodable, \([0-9]*\) desynced.*/\1/')
}

# ── axis 1 — every function of the COMPILER ITSELF walks cleanly ─────────────────────────
audit "$R/src/main.cyr" axis1
[ "$UNDEC" -eq 0 ] || { echo "FAIL decode_len_coverage axis1: $UNDEC of $FNS fn bodies hit an undecodable byte."; echo "  DECODE_LEN has a gap. RA_SCAN_LOOPS returns -1 for those fns, so the register"; echo "  allocator falls back to whole-function intervals and v6.5.35 is silently off there."; exit 1; }
[ "$DESYNC" -eq 0 ] || { echo "FAIL decode_len_coverage axis1: $DESYNC of $FNS fn bodies OVERSHOT their end."; echo "  That is a WRONG length, not a missing one — the walk desynchronises and can step over"; echo "  a real backward edge. This is the miscompile class, not the lost-optimisation class."; exit 1; }

# ── axis 2 — ANTI-VACUOUS: the audit must be measuring a real program ────────────────────
# Without this, a build emitting three functions would score a perfect 3/3 and pass.
[ "$FNS" -ge 1000 ] || { echo "FAIL decode_len_coverage axis2: the audit saw only $FNS fns compiling cycc itself."; echo "  Expected >=1000. A near-empty audit passes axis 1 trivially and proves nothing."; exit 1; }
[ "$CLEAN" -eq "$FNS" ] || { echo "FAIL decode_len_coverage axis2: clean=$CLEAN != fns=$FNS (the three counts must partition)"; exit 1; }
SELF_FNS=$FNS

# ── axis 3 — the opcode classes the fix added, which cycc's own source may not exercise ──
# Each line here emits an opcode DECODE_LEN did not previously handle: `%`/`/` -> 48 99 CQO;
# f64 tagging -> 48 0F BA (bts/btr rax,63); the SIMD shift groups -> 66 0F 73 (psrlq/psllq);
# a dense `switch` -> 63 MOVSXD in the table dispatch. A loop is present in each so the
# picker's RA_SCAN_LOOPS actually walks them.
cat > "$T/probe.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
fn divmod_loop(n) {
    var acc = 0; var i = 1;
    while (i <= n) { acc = acc + (n / i) + (n % i); i = i + 1; }
    return acc;
}
fn float_tag_loop(n) {
    var acc = f64_from(0); var i = 0;
    while (i < n) { acc = f64_add(acc, f64_mul(f64_from(i), f64_from(2))); i = i + 1; }
    return f64_to(acc);
}
fn switch_loop(n) {
    var acc = 0; var i = 0;
    while (i < n) {
        switch (i % 6) {
            case 0: acc = acc + 1;
            case 1: acc = acc + 2;
            case 2: acc = acc + 3;
            case 3: acc = acc + 4;
            case 4: acc = acc + 5;
            default: acc = acc + 6;
        }
        i = i + 1;
    }
    return acc;
}
fn main(): i64 {
    var a = divmod_loop(12);
    var b = float_tag_loop(10);
    var c = switch_loop(12);
    syscall(60, (a + b + c) & 0xFF);
    return 0;
}
var e = main();
EOF
audit "$T/probe.cyr" axis3
[ "$UNDEC" -eq 0 ] || { echo "FAIL decode_len_coverage axis3: $UNDEC fn bodies undecodable in the opcode-class probe"; exit 1; }
[ "$DESYNC" -eq 0 ] || { echo "FAIL decode_len_coverage axis3: $DESYNC fn bodies desynced in the opcode-class probe"; exit 1; }

# ── axis 4 — CORRECTNESS CONTROL: the probe must still compute the right answer ──────────
# Decoder coverage drives the register allocator, so a coverage change is a codegen change.
# A gate that only counted clean walks would stay green on a compiler that walks perfectly
# and allocates wrongly.
"$T/stage1" < "$T/probe.cyr" > "$T/probe" 2>/dev/null || { echo "FAIL decode_len_coverage axis4: probe did not compile"; exit 1; }
chmod +x "$T/probe"; "$T/probe"; got=$?
"$CC" < "$T/probe.cyr" > "$T/probe_ref" 2>/dev/null || { echo "FAIL decode_len_coverage axis4: probe did not compile with build/cycc"; exit 1; }
chmod +x "$T/probe_ref"; "$T/probe_ref"; want=$?
[ "$got" -eq "$want" ] || { echo "FAIL decode_len_coverage axis4: the source-built compiler gives $got where build/cycc gives $want."; echo "  Decoder coverage feeds RA_SCAN_LOOPS, so this is a register-allocation divergence."; exit 1; }

echo "PASS decode_len_coverage: $SELF_FNS-fn self-compile walks 100% clean (0 undecodable, 0 desynced) · CQO/imm8/MOVSXD classes covered · probe agrees with build/cycc"
exit 0

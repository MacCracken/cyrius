#!/bin/sh
# Gate: the linear-scan register allocator TIME-SHARES registers, safely.
#
# WHAT WAS WRONG (v5.6.20 → v6.5.34). A Poletto-Sarkar linear-scan picker has shipped and
# been default-on for every function since v5.6.21, and it computes real live intervals
# (`ra_first` / `ra_last`). It could never use them, for TWO independent reasons — and the
# roadmap's long-standing "the cross-BB defect is ONE line" framing named only the first:
#
#   1. Every interval's end was force-set to the function end, so the expire step never
#      fired. That line was NOT an oversight: v5.6.22 put it there because naive
#      time-sharing is UNSOUND across a backward edge — when the picker reuses a register
#      for a later interval, a JMP_BACK into a position inside an EARLIER interval re-reads
#      the register expecting the earlier value and finds the later one. Reverting that one
#      line ALONE reintroduces the miscompile: measured at v6.5.35, naive expire fails
#      **69 of the 282 corpus tests**, across 13 buckets (crypto 13, formats 11, text 10,
#      stdlib 8, derive 8 …). Anyone who reads "one line" and deletes it will ship that.
#
#   2. `picked` counted assignments over the whole FUNCTION's lifetime and was capped at
#      `_cur_fn_regalloc` (5). So once five locals had EVER received a register, every later
#      interval was blocked regardless of how many registers expire had just freed. Fixing
#      (1) alone therefore changed **not one byte** of any consumer program's output —
#      json_engine, math_pack_integration and sakshi_full all compiled byte-identical. The
#      knob's own comment already documented `-1 = uncapped`; the code did not implement it.
#
# THE FIX. `RA_SCAN_LOOPS` (src/backend/x86/decode.cyr) finds the backward edges in a
# function's emitted range; `_ra_loop_extend` (parse_fn.cyr) extends an interval overlapping
# a loop body to that loop's branch, to a fixpoint for nesting; and the lifetime cap now
# applies only when the bisection knob asks for it. Simultaneity is enforced where it
# belongs — by `free_r == -1` falling through to the spill heuristic.
#
# ⚠ FAIL-SAFE: `RA_SCAN_LOOPS` returns -1 for an undecodable range or more edges than the
# cap, and -1 means "no information", NOT "no loops". The caller must then extend to the
# whole function, i.e. exactly the pre-v6.5.35 behaviour. A partial edge list would be worse
# than none — the picker would time-share across precisely the loop the scan failed to see.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
CC="$ROOT/build/cycc"
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
fails=0

check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 — expected $2, got $3"; fails=$((fails + 1)); fi
}

# Count `mov r64,[rbp+disp32]` / `mov [rbp+disp32],r64` — the frame accesses the picker
# rewrites into register moves. Fewer = more locals resident.
frame_movs() {
    od -An -v -tx1 "$1" 2>/dev/null | tr -s ' ' '\n' | grep -v '^$' | awk '
        { b[NR]=$1 }
        END { n=0; for (i=1; i<=NR-2; i++)
                if (b[i]=="48" && (b[i+1]=="8b" || b[i+1]=="89") && b[i+2]=="85") n++
              print n }'
}

# ── AXIS 1: time-sharing is LIVE, and the old behaviour is exactly reproducible.
# Twelve locals with disjoint live ranges against five callee-saved registers: impossible to
# hold simultaneously, trivial to time-share. `CYRIUS_REGALLOC_PICKER_CAP=5` restores the
# pre-v6.5.35 lifetime cap, which makes this a self-contained A/B needing no second binary.
cat > "$D/ts.cyr" <<'EOF'
fn t(): i64 {
    var acc = 0;
    var a1 = 1; var b1 = 2; acc = acc + a1 * b1 + a1 + b1;
    var a2 = 3; var b2 = 4; acc = acc + a2 * b2 + a2 + b2;
    var a3 = 5; var b3 = 6; acc = acc + a3 * b3 + a3 + b3;
    var a4 = 7; var b4 = 8; acc = acc + a4 * b4 + a4 + b4;
    var a5 = 9; var b5 = 10; acc = acc + a5 * b5 + a5 + b5;
    var a6 = 11; var b6 = 12; acc = acc + a6 * b6 + a6 + b6;
    return acc;
}
var r = t();
syscall(60, r - 400);
EOF
echo "axis 1 — disjoint intervals time-share a register file too small to hold them:"
"$CC" < "$D/ts.cyr" > "$D/ts_def" 2>/dev/null; chmod +x "$D/ts_def" 2>/dev/null
CYRIUS_REGALLOC_PICKER_CAP=5 "$CC" < "$D/ts.cyr" > "$D/ts_cap" 2>/dev/null; chmod +x "$D/ts_cap" 2>/dev/null
"$D/ts_def" >/dev/null 2>&1; check "default build is CORRECT" 0 "$?"
"$D/ts_cap" >/dev/null 2>&1; check "capped build is correct too" 0 "$?"
fm_def=$(frame_movs "$D/ts_def")
fm_cap=$(frame_movs "$D/ts_cap")
echo "    frame accesses: default=$fm_def  PICKER_CAP=5=$fm_cap"
# ANTI-VACUOUS: the capped build must actually have some, or "fewer" is meaningless.
if [ "$fm_cap" -gt 0 ]; then check "premise: the capped build spills to the frame" "yes" "yes"
else check "premise: the capped build spills to the frame" "yes" "no"; fi
if [ "$fm_def" -lt "$fm_cap" ]; then check "time-sharing reduces frame accesses" "yes" "yes"
else check "time-sharing reduces frame accesses" "yes" "no"; fi

# ── AXIS 2: the loop shapes naive expire miscompiles. These are ORDINARY corpus tests that
# passed throughout — under naive time-sharing they fail with wrong answers, not crashes,
# which is what makes the hazard worth a gate rather than a comment. One representative per
# affected bucket; the full mutation result is 69 of 282.
echo "axis 2 — loop-heavy corpus shapes stay correct (naive expire fails 69 of 282):"
for t in keccak sha1 fmt_i64_min thread_safety large_input chrono_datetime; do
    src=$(find tests/tcyr -name "$t.tcyr" | head -1)
    # An unmatched find must fail loudly: cycc on EMPTY stdin exits 0 and emits a runnable
    # binary, so a missing fixture would score a fake PASS (the v6.5.11 lesson).
    if [ -z "$src" ]; then check "$t (source found)" "yes" "no"; continue; fi
    "$CC" < "$src" > "$D/$t.bin" 2>/dev/null || { check "$t compiles" 0 1; continue; }
    chmod +x "$D/$t.bin"
    timeout 90 "$D/$t.bin" >/dev/null 2>&1
    check "$t" 0 "$?"
done

# ── AXIS 3: a loop that reuses a register inside its body — the v5.6.22 shape, reduced.
# The outer accumulator must survive the inner loop even though the inner locals are hotter
# and come later in the interval order.
cat > "$D/loop.cyr" <<'EOF'
fn t(): i64 {
    var total = 0;
    var i = 0;
    while (i < 40) {
        var p = i * 2;
        var q = p + 1;
        var r = q * 3;
        var s = r - p;
        var u = s + q;
        var v = u * 2;
        total = total + v - u - s - r - q - p;
        i = i + 1;
    }
    return total;
}
var z = t();
syscall(60, z + 6360);
EOF
# ⚠ ORACLE-BASED, deliberately. An earlier draft asserted a hand-computed constant and went
# red on the author's arithmetic while both builds AGREED — which would have read as a
# miscompile in this exact gate. `CYRIUS_REGALLOC_PICKER_CAP=0` disables the picker entirely,
# so it is a reference implementation for the same source: compare the two AND pin the value,
# so a wrong constant can never masquerade as a codegen bug again.
echo "axis 3 — a value live across a loop body is not handed to a later interval:"
"$CC" < "$D/loop.cyr" > "$D/loop.bin" 2>/dev/null; chmod +x "$D/loop.bin" 2>/dev/null
"$D/loop.bin" >/dev/null 2>&1; rc_on=$?
CYRIUS_REGALLOC_PICKER_CAP=0 "$CC" < "$D/loop.cyr" > "$D/loop_off.bin" 2>/dev/null
chmod +x "$D/loop_off.bin" 2>/dev/null
"$D/loop_off.bin" >/dev/null 2>&1; rc_off=$?
check "regalloc ON agrees with regalloc OFF (the oracle)" "$rc_off" "$rc_on"
check "and the shared answer is the correct one" 0 "$rc_off"
# The fixture is only meaningful if the picker actually engaged on it.
fm_on=$(frame_movs "$D/loop.bin")
fm_off=$(frame_movs "$D/loop_off.bin")
echo "    frame accesses: regalloc ON=$fm_on  OFF=$fm_off"
if [ "$fm_on" -lt "$fm_off" ]; then check "premise: the picker engaged on this loop" "yes" "yes"
else check "premise: the picker engaged on this loop" "yes" "no"; fi

# ── AXIS 4: the capstone. A compiler this pass rewrote must still reproduce itself
# byte-identically — the strongest statement available, on the largest program in the tree.
echo "axis 4 — cycc still self-hosts byte-identically:"
"$CC" < src/main.cyr > "$D/gen" 2>/dev/null
if [ ! -s "$D/gen" ]; then
    check "self-host produced a compiler" "yes" "no"
else
    chmod +x "$D/gen"
    if cmp -s "$D/gen" "$CC"; then check "cycc(src) == build/cycc" "yes" "yes"
    else check "cycc(src) == build/cycc" "yes" "no"; fi
fi

echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: regalloc-cross-bb — intervals time-share, loops stay sound, cycc self-hosts"
    exit 0
fi
echo "FAIL: regalloc-cross-bb — $fails assertion(s) failed"
exit 1

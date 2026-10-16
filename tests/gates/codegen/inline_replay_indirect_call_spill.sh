#!/bin/sh
# inline_replay_indirect_call_spill.sh — 6.7.13. An indirect call as an argument of an inline-replayed fn reads its
# own arguments.
#
# WHY. `_PINDIRECT_CALL_IN` spills the callee into two frame slots of its own (the value, then the pointer it calls
# through). They were counted by GFLC alone. The inline replay releases GFLC back to its parameters after each
# argument, and the frame is sized from the final GFLC and the `_flc_hwm` high-water, so the spill slots could lie
# BELOW the frame: the call's own argument `push` then landed on the spilled callee pointer and the callee was passed
# its code address as its first argument. This release's D30 shape `la(callptr(&mkv, 4, 2))` into an inline-replayed
# value-form vector parameter read 2 on x86_64 where 42 is right (the vectors docs pass found it), and the
# two-parameter `lc(callptr(&mkv, 4, 2), 0)` faulted. `_icall_slot` records each spill slot in the high-water, as
# every other transient slot is (`_agg_temp_t`). An integer argument's spill stayed inside the frame (a register and an
# in-frame slot), so S1 / S2 are controls. Whether a caller shows it depends on its frame's padding — a caller with a
# local or two of its own hid it — so the programs below are standalone, one tight caller each.
#
#   S1 / S2 `sum2(1, callptr(..))` / `sum2(callptr(..), 1)`, the caller's only statement: 43 (controls)
#   V1 / V2 `la(callptr(&mkv, 4, 2))` / `la(fncall2(&mkv, 4, 2))` into an inline `x: f64v2`: 42
#   V3 `lc(callptr(&mkv, 4, 2), 0)`, the vector first of two: 42
#   each on x86_64 plain, CYRIUS_IR=3 and CYRIUS_DCE=1
#   T  tests/tcyr/crossos/inline_replay_indirect_call_argument.tcyr on x86_64: "N passed, 0 failed (N total)", N at
#      least FLOOR (the release gate runs it on ecb / ach / cass / pi)
#
# MUTATION LEDGER (2026-10-16, measured: `_icall_slot` without its `_flc_hwm` line, a two-stage mutant compiler, this
# gate run with CYCC=<it>):
#   M-H1 no high-water line -> RED 10: V1 V2 on plain and IR=3 (94), on DCE (20); V3 on every mode (139); T (rc 139
#        after "la(fncall2(&mkv, 4, 2)) (got 42463712, expected 42)"); S1 S2 green (controls)
#
# ⚠ NO `set -e`: exit codes are DATA.
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: inline_replay_indirect_call_spill: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
CC="${CYCC:-$ROOT/build/cycc}"
G=inline_replay_indirect_call_spill
FAIL=0
bad() { echo "  FAIL $*"; FAIL=$((FAIL + 1)); }
ok() { echo "  ok   $*"; }

HEAD='include "lib/fnptr.cyr"
fn mk(a, b): i64 { return a * 10 + b; }
fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn sum2(y, x): i64 { return x + y; }
fn la(x: f64v2): i64 { return load64(&x) * 10 + load64(&x + 8); }
fn lc(x: f64v2, y: i64): i64 { return y + load64(&x) * 10 + load64(&x + 8); }'

prog() {   # name, the caller's return expression
    printf '%s\nfn run(): i64 { return %s; }\nsyscall(60, run() %% 256);\n' "$HEAD" "$2" > "$D/$1.cyr"
}
prog S1 'sum2(1, callptr(&mk, 4, 2))'
prog S2 'sum2(callptr(&mk, 4, 2), 1)'
prog V1 'la(callptr(&mkv, 4, 2))'
prog V2 'la(fncall2(&mkv, 4, 2))'
prog V3 'lc(callptr(&mkv, 4, 2), 0)'

run_row() {   # row, mode label, env assignment or "", expected exit
    if [ -n "$3" ]; then env "$3" "$CC" < "$D/$1.cyr" > "$D/$1.bin" 2> "$D/$1.err"; else "$CC" < "$D/$1.cyr" > "$D/$1.bin" 2> "$D/$1.err"; fi
    rc=$?
    if [ $rc -ne 0 ]; then bad "$1 ($2): compile rc $rc: $(grep -m1 error "$D/$1.err")"; return; fi
    chmod +x "$D/$1.bin"
    "$D/$1.bin"; got=$?
    if [ "$got" -eq "$4" ]; then ok "$1 ($2): exit $got"; else bad "$1 ($2): exit $got, want $4"; fi
}
for m in plain IR3 DCE; do
    case $m in plain) e="";; IR3) e="CYRIUS_IR=3";; DCE) e="CYRIUS_DCE=1";; esac
    run_row S1 "$m" "$e" 43
    run_row S2 "$m" "$e" 43
    run_row V1 "$m" "$e" 42
    run_row V2 "$m" "$e" 42
    run_row V3 "$m" "$e" 42
done

# ── T: the crossos file, with a floor so a gutted file cannot pass ───────────────
TC=tests/tcyr/crossos/inline_replay_indirect_call_argument.tcyr
[ -f "$TC" ] || { echo "FAIL: $G: $TC is missing"; exit 1; }
N=$(awk '/^[[:space:]]*#/{next} /assert_eq\(/{n++} END{print n+0}' "$TC")
FLOOR=15
if [ "$N" -lt "$FLOOR" ]; then bad "T: only $N rows in $TC (floor $FLOOR) — rows were lost"
else
    "$CC" < "$TC" > "$D/t.bin" 2> "$D/t.err"
    rc=$?
    if [ $rc -ne 0 ]; then bad "T: compile rc $rc: $(grep -m1 error "$D/t.err")"
    else
        chmod +x "$D/t.bin"
        out=$("$D/t.bin" 2>&1); rc=$?
        want="$N passed, 0 failed ($N total)"
        if [ $rc -eq 0 ] && printf '%s\n' "$out" | grep -qF "$want"; then ok "T: $want"
        else bad "T: rc $rc, '$(printf '%s\n' "$out" | tail -1)' (want '$want')"; fi
    fi
fi

if [ "$FAIL" -ne 0 ]; then echo "FAIL: $G ($FAIL row(s))"; exit 1; fi
echo "PASS: $G (S1 S2 V1 V2 V3 on x86_64 plain / IR=3 / DCE, and the $N-row crossos file)"
exit 0

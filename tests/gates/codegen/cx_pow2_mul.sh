#!/bin/sh
# cx_pow2_mul.sh — `x * 2^k` on the cx target actually shifts.
#
# v6.6.4. `ESHLIMM` (src/backend/cx/emit.cyr) was a return-0 STUB, so the
# power-of-two multiply strength reduction in parse_expr.cyr `_TRY_MUL_BY_POW2`
# (`x * 2` -> `shl rax, 1`) emitted NOTHING on cx: `x * 2` and `x * 4` returned x
# unchanged under cxvm while `x * 3` and `x * k` (a variable) were correct — the
# v6.5.13 / v6.4.32 return-0-stub class. Surfaced by the 6.6.4 review's probe
# for cx_addr_past_64k. Same shell-gate-not-tcyr reason as cx_multi_return.sh.
#
# Mutation-proven against the 6.6.3 compiler: axes 1-2 exit 11 (want 22 / 44).
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: cx_pow2_mul: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }; trap 'rm -rf "$D"' EXIT

cat src/main_cx.cyr | ./build/cycc > "$D/cc" 2>/dev/null; chmod +x "$D/cc"
cat programs/cxvm.cyr | ./build/cycc > "$D/vm" 2>/dev/null; chmod +x "$D/vm"

pass=0; fail=0
run_case() {  # $1 label  $2 source  $3 expected exit code
    printf '%s' "$2" > "$D/c.cyr"
    cat "$D/c.cyr" | "$D/cc" > "$D/c.cyx" 2>/dev/null
    [ -s "$D/c.cyx" ] || { echo "  FAIL: $1 (empty .cyx)"; fail=$((fail+1)); return; }
    RC=0
    timeout 30 "$D/vm" < "$D/c.cyx" >/dev/null 2>&1 || RC=$?
    if [ "$RC" = "$3" ]; then
        printf '  ok: %-34s exit=%s\n' "$1" "$RC"; pass=$((pass+1))
    else
        printf '  FAIL: %-32s exit=%s (want %s)\n' "$1" "$RC" "$3"; fail=$((fail+1))
    fi
}

echo "axis 1 — local * 2 (the strength-reduced shl):"
run_case "a * 2" 'fn main(): i64 { var a = 11; var t = a * 2; return t; }
var r = main();
syscall(60, r);
' 22

echo "axis 2 — global * 4:"
run_case "g * 4" 'var g = 11;
fn main(): i64 { return g * 4; }
var r = main();
syscall(60, r);
' 44

echo "axis 3 — controls that never took the shl path (must stay right):"
run_case "g * 3 (imul)" 'var g = 11;
fn main(): i64 { return g * 3; }
var r = main();
syscall(60, r);
' 33
run_case "g * k (variable)" 'var g = 11; var k = 2;
fn main(): i64 { return g * k; }
var r = main();
syscall(60, r);
' 22

echo "cx_pow2_mul: $pass passed, $fail failed"
[ "$fail" -eq 0 ]

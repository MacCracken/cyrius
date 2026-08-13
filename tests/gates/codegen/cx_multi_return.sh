#!/bin/sh
# cx_multi_return.sh — the cx arm of multi-value return.
#
# v6.5.21. `EMOVRDXRAX` / `EMOVRA_RDX` were literal `return 0;` stubs in
# src/backend/cx/emit.cyr, so on the cx target EVERY multi-value return handed
# back the FIRST value TWICE — `return (5, 9)` scored 59 on x86 / aarch64 / PE and
# 55 under cxvm, at exit 0 with no diagnostic. The legacy `ret2` / `rethi` builtins
# share the same register pair and were broken identically.
#
# ⛔ WHY THIS IS A SHELL GATE AND NOT `tests/tcyr/crossos/multi_return.tcyr`:
# a .tcyr pulls in lib/assert.cyr + lib/fmt.cyr, and the cx backend cannot compile
# that surface ("undefined function(s) called (cx backend)"). The cross-host .tcyr
# therefore covers x86 / aarch64 / PE and CANNOT cover cx — which is precisely the
# one target the bug lived on. A cx exit-code case has to run under cxvm, the same
# split the v6.4.58 cx modulo fix used.
#
# ⚠ VALUES MUST BE DISTINGUISHABLE AND ORDER-SENSITIVE. `(5, 9) -> 59` is chosen so
# the first-value-twice defect is visible: with `(1, 1)`, or by summing, the broken
# compiler passes.
#
# Mutation-proven against the 6.5.20 compiler: both cases score 55, not 59.
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT"
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT

cat src/main_cx.cyr | ./build/cycc > "$D/cc" 2>/dev/null; chmod +x "$D/cc"
cat programs/cxvm.cyr | ./build/cycc > "$D/vm" 2>/dev/null; chmod +x "$D/vm"

pass=0; fail=0
run_case() {  # $1 label  $2 source  $3 expected exit code
    printf '%s' "$2" > "$D/c.cyr"
    cat "$D/c.cyr" | "$D/cc" > "$D/c.cyx" 2>/dev/null
    RC=0
    timeout 30 "$D/vm" < "$D/c.cyx" >/dev/null 2>&1 || RC=$?
    if [ "$RC" = "$3" ]; then
        printf '  ok: %-34s exit=%s\n' "$1" "$RC"; pass=$((pass+1))
    else
        printf '  FAIL: %-32s exit=%s (want %s)\n' "$1" "$RC" "$3"; fail=$((fail+1))
    fi
}

echo "axis 1 — 'return (a, b)' carries BOTH values on cx (stub returned the first twice):"
run_case "return (5, 9)" \
'fn t(): i64 { return (5, 9); }
fn main(): i64 { var a, b = t(); return a * 10 + b; }
var r = main();
syscall(60, r);
' 59

echo "axis 2 — legacy ret2/rethi share the pair and were broken identically:"
run_case "ret2(5, 9) + rethi()" \
'fn t(): i64 { ret2(5, 9); }
fn main(): i64 { var a = t(); var b = rethi(); return a * 10 + b; }
var r = main();
syscall(60, r);
' 59

echo "axis 3 — arity 3 (v6.5.21) lands all three slots on cx:"
run_case "return (1, 2, 3)" \
'fn t(a): (i64, i64, i64) { return (a, a + 1, a + 2); }
fn main(): i64 { var x, y, z = t(1); return x * 100 + y * 10 + z; }
var r = main();
syscall(60, r);
' 123

echo "axis 4 — a SINGLE return is unaffected (guards against over-correction):"
run_case "return 5 (single)" \
'fn t(): i64 { return 5; }
fn main(): i64 { var a = t(); return a * 10 + 9; }
var r = main();
syscall(60, r);
' 59

if [ "$fail" -gt 0 ]; then
    printf 'FAIL: cx-multi-return — %s assertion(s) failed\n' "$fail"
    exit 1
fi
printf 'PASS: cx-multi-return — %s/%s axes green\n' "$pass" "$pass"

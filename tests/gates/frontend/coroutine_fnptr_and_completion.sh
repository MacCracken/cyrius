#!/bin/sh
# coroutine_fnptr_and_completion.sh — 6.6.8 bite 1b: inside an `async fn` coroutine body an
# indirect call (fncallN / callptr / a closure) calls the right code.
#
# ⛔ WHY (fn pointer). PINDIRECT_CALL spills the callee to a fresh local and calls through it with
# ECALLIND. In a coroutine that local lives in the HEAP frame — EFLSTORE wrote it to [r11+off] —
# but ECALLIND always emitted `call [rbp+disp]`, so it called whatever the stack held there:
# `var f = &tri; fncall1(f, 10)` between two awaits SIGSEGV'd (exit 139) while `tri(10)` was fine.
#
# ⚠ `async`/`await` are gated behind CYRIUS_ASYNC=1, which is why this is a SHELL gate and not a
# `.tcyr` (the tcyr runner cannot set an env var). x86 family only, like the transform itself.
#
#   A  fncall1(&fn, 10) between two awaits            -> 132 (was SIGSEGV)
#   B  a fn pointer taken BEFORE an await, called after with fncall2, and callptr -> 1030
#   C  a capturing closure called inside the coroutine  -> 150
#
# Mutations: remove the coroutine branch of ECALLIND -> A, B, C RED (139).
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: coroutine_fnptr_and_completion: no compiler at $CC"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: coroutine_fnptr_and_completion: mktemp -d failed"; exit 1; }
trap 'rm -rf "$T"' EXIT
cd "$ROOT"
fails=0
ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }
PRE='include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/vec.cyr"
include "lib/syscalls.cyr"
include "lib/fnptr.cyr"
include "lib/async.cyr"
fn nopark(): i64 { return 0; }'
run() {     # <name> <want stdout> <what>
    rc=0
    CYRIUS_ASYNC=1 "$CC" < "$T/$1.cyr" > "$T/$1.bin" 2> "$T/$1.err" || rc=$?
    if [ "$rc" -ne 0 ]; then bad "$3: rc $rc: $(grep '^error' "$T/$1.err" | head -1)"; return; fi
    chmod +x "$T/$1.bin"
    got=$( (ulimit -c 0; timeout 30 "$T/$1.bin") 2>/dev/null); e=$?
    if [ "$e" -ne 0 ]; then bad "$3: exit $e (output '$got')"
    elif [ "$got" = "$2" ]; then ok "$3: $got"
    else bad "$3: printed '$got', want '$2'"; fi
}

cat > "$T/a.cyr" <<EOF
$PRE
fn tri(y): i64 { var z = y * 3; return z + 1; }
async fn steps(C): i64 {
    var x = 1;
    var s1 = await nopark();
    var f = &tri;
    x = x + fncall1(f, 10);
    var s2 = await nopark();
    x = x + 100;
    return x;
}
fn main(): i64 {
    alloc_init();
    var C = steps(0);
    var r1 = future_force(C); var r2 = future_force(C); var r3 = future_force(C);
    fmt_int(r3);
    return 0;
}
var e = main();
syscall(60, 0);
EOF
run a 132 "A: fncall1 through &fn between two awaits"

cat > "$T/b.cyr" <<EOF
$PRE
fn add2(a, b): i64 { return a * 10 + b; }
async fn steps(C): i64 {
    var f = &add2;
    var s1 = await nopark();
    var x = fncall2(f, 100, 7);
    var s2 = await nopark();
    x = x + callptr(f, 2, 3);
    return x;
}
fn main(): i64 {
    alloc_init();
    var C = steps(0);
    var r1 = future_force(C); var r2 = future_force(C); var r3 = future_force(C);
    fmt_int(r3);
    return 0;
}
var e = main();
syscall(60, 0);
EOF
run b 1030 "B: a fn pointer across a suspend (fncall2, callptr)"

cat > "$T/c.cyr" <<EOF
$PRE
async fn steps(C): i64 {
    var k = 50;
    var s1 = await nopark();
    var g = |y| y + k;
    var x = fncall1(g, 100);
    var s2 = await nopark();
    return x;
}
fn main(): i64 {
    alloc_init();
    var C = steps(0);
    var r1 = future_force(C); var r2 = future_force(C); var r3 = future_force(C);
    fmt_int(r3);
    return 0;
}
var e = main();
syscall(60, 0);
EOF
run c 150 "C: a capturing closure called inside the coroutine"

if [ "$fails" -ne 0 ]; then echo "FAIL: coroutine_fnptr_and_completion — $fails axis(es) red"; exit 1; fi
echo "PASS: coroutine_fnptr_and_completion — fncallN / callptr / closure calls inside a coroutine reach their callee (A-C)"

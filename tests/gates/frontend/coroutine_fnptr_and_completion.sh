#!/bin/sh
# coroutine_fnptr_and_completion.sh — 6.6.8 bite 1b: inside an `async fn` coroutine body an
# indirect call (fncallN / callptr / a closure) calls the right code, and forcing a coroutine that
# has already COMPLETED returns its value again without running any of its body or defers.
#
# ⛔ WHY (fn pointer). PINDIRECT_CALL spills the callee to a fresh local and calls through it with
# ECALLIND. In a coroutine that local lives in the HEAP frame — EFLSTORE wrote it to [r11+off] —
# but ECALLIND always emitted `call [rbp+disp]`, so it called whatever the stack held there:
# `var f = &tri; fncall1(f, 10)` between two awaits SIGSEGV'd (exit 139) while `tri(10)` was fine.
#
# ⛔ WHY (completion). The body's real return never wrote the coroutine's state word, so a force
# after completion re-entered at the LAST suspend: the tail ran again, with its defers, and a
# loop kept counting past its own exit (forces 5..10 of a three-await loop returned 4..9, and the
# defer ran on each). Completion now stamps DONE and keeps the value; the dispatch answers a DONE
# entry with it and runs nothing.
#
# ⚠ `async`/`await` are gated behind CYRIUS_ASYNC=1, which is why this is a SHELL gate and not a
# `.tcyr` (the tcyr runner cannot set an env var). x86 family only, like the transform itself.
#
#   A  fncall1(&fn, 10) between two awaits            -> 132 (was SIGSEGV)
#   B  a fn pointer taken BEFORE an await, called after with fncall2, and callptr -> 1030
#   C  a capturing closure called inside the coroutine  -> 150
#   D  a straight-line body forced 6 times              -> 3 x 0, then 327 x 3; body tail ran ONCE
#   E  a three-await loop with a defer, forced 10 times -> 3 x 0, then 3 x 7; defer ran ONCE
#   F  a TAIL-SHAPED `return helper(x);`, no defer, forced 6 times -> 0 0 12 12 12 12; helper ran
#      ONCE (a tail call's `jmp` skipped the epilogue that marks the coroutine done, so every later
#      force re-ran the tail; coroutines no longer tail-call)
#
# Mutations: remove the coroutine branch of ECALLIND -> A, B, C RED (139). Remove
# `_coro_mark_done` -> D, E, F RED (the tail and the defer re-run). Remove `_coro_done_check` ->
# D, E, F RED. Drop the `_cur_fn_coro` line of `_tc_frame_divert` -> F RED (helper ran 4 times).
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

cat > "$T/d.cyr" <<EOF
$PRE
var g_tail = 0;
async fn steps(C): i64 {
    var x = 7;
    var s1 = await nopark();
    x = x + 20;
    var s2 = await nopark();
    x = x + 300;
    var s3 = await nopark();
    g_tail = g_tail + 1;
    return x;
}
fn main(): i64 {
    alloc_init();
    var C = steps(0);
    var n = 0;
    while (n < 6) { fmt_int(future_force(C)); syscall(1, 1, " ", 1); n = n + 1; }
    fmt_int(g_tail);
    return 0;
}
var e = main();
syscall(60, 0);
EOF
run d '0 0 0 327 327 327 1' "D: a completed coroutine answers with its value; the tail ran once"

cat > "$T/e.cyr" <<EOF
$PRE
var cran = 0;
async fn steps(C): i64 {
    var i = 0;
    while (i < 3) {
        defer { cran = cran + 1; }
        var s = await nopark();
        i = i + 1;
    }
    return i + 4;
}
fn main(): i64 {
    alloc_init();
    var C = steps(0);
    var n = 0;
    while (n < 10) { fmt_int(future_force(C)); syscall(1, 1, " ", 1); n = n + 1; }
    fmt_int(cran);
    return 0;
}
var e = main();
syscall(60, 0);
EOF
run e '0 0 0 7 7 7 7 7 7 7 1' "E: a finished loop coroutine does not resume; its defer ran once"

cat > "$T/f.cyr" <<EOF
$PRE
var g_tail = 0;
fn helper(v): i64 { g_tail = g_tail + 1; return v * 2; }
async fn steps(C): i64 {
    var x = 5;
    var s1 = await nopark();
    x = x + 1;
    var s2 = await nopark();
    return helper(x);
}
fn main(): i64 {
    alloc_init();
    var C = steps(0);
    var n = 0;
    while (n < 6) { fmt_int(future_force(C)); syscall(1, 1, " ", 1); n = n + 1; }
    fmt_int(g_tail);
    return 0;
}
var e = main();
syscall(60, 0);
EOF
run f '0 0 12 12 12 12 1' "F: a tail-shaped return completes the coroutine; the tail ran once"

# ── 6.6.10 — arity, fall-off, the value of `await`, force-once ──────────────────────────────
cat > "$T/g.cyr" <<EOF
$PRE
async fn co(): i64 { var x = 3; var s = await nopark(); x = x + 4; return x; }
fn main(): i64 {
    alloc_init();
    var C = co();
    var n = 0;
    while (n < 5) { fmt_int(future_force(C)); syscall(1, 1, " ", 1); n = n + 1; }
    return 0;
}
var e = main();
syscall(60, 0);
EOF
run g '0 7 7 7 7 ' "G: a 0-parameter coroutine (was SIGSEGV: argc 0 left SELF garbage)"

cat > "$T/h.cyr" <<EOF
$PRE
async fn co(a, b, c, d, e1, f, g, h, i9): i64 {
    var x = a + b + c + d + e1 + f + g + h + i9;
    var s = await nopark();
    return x + 4;
}
fn main(): i64 {
    alloc_init();
    var C = co(1, 2, 3, 4, 5, 6, 7, 8, 9);
    var n = 0;
    while (n < 5) { fmt_int(future_force(C)); syscall(1, 1, " ", 1); n = n + 1; }
    return 0;
}
var e = main();
syscall(60, 0);
EOF
run h '0 49 49 49 49 ' "H: a 9-parameter coroutine (was exit 70 at the first force)"

# I — falling off the end completes the coroutine (was a hang: the fall-off ran into the resume
# dispatch and jumped back to the last landing forever). Four shapes: after an await, a body that
# ENDS in an await, a fall-off on one path only, and a fall-off with a defer.
fo() {    # <tag> <body> <want> <what>
    cat > "$T/$1.cyr" <<EOF
$PRE
var g_t = 0;
async fn co(a): i64 {
$2
}
fn main(): i64 {
    alloc_init();
    var C = co(3);
    var n = 0;
    while (n < 4) { fmt_int(future_force(C)); syscall(1, 1, " ", 1); n = n + 1; }
    fmt_int(g_t);
    return 0;
}
var e = main();
syscall(60, 0);
EOF
    run "$1" "$3" "$4"
}
fo i1 '    var x = a; var s = await nopark(); g_t = g_t + 1;' '0 0 0 0 1' "I1: falls off after an await"
fo i2 '    g_t = g_t + 1; var s = await nopark();' '0 0 0 0 1' "I2: the body ENDS in an await"
fo i3 '    var s = await nopark(); if (a > 5) { return 9; } g_t = g_t + 1;' '0 0 0 0 1' "I3: falls off on one path"
fo i4 '    defer { g_t = g_t + 100; } var s = await nopark(); g_t = g_t + 1;' '0 0 0 0 101' "I4: falls off with a defer (the defer runs once)"

# K — a PLAIN (no-await) async fn's Future runs its body ONCE however often it is forced (it
# re-ran on every force), a 0-parameter one too.
cat > "$T/k.cyr" <<EOF
$PRE
var g_n = 0;
async fn side(k): i64 { g_n = g_n + 1; return k + g_n * 100; }
async fn zero(): i64 { g_n = g_n + 10; return 7; }
fn main(): i64 {
    alloc_init();
    var F = side(3);
    fmt_int(await F); syscall(1, 1, " ", 1);
    fmt_int(await F); syscall(1, 1, " ", 1);
    fmt_int(future_force(F)); syscall(1, 1, " ", 1);
    var Z = zero();
    fmt_int(await Z); syscall(1, 1, " ", 1);
    fmt_int(await Z); syscall(1, 1, " ", 1);
    fmt_int(g_n);
    return 0;
}
var e = main();
syscall(60, 0);
EOF
run k '103 103 103 7 7 11' "K: a plain Future forced 3 times runs its body once"

# L — a PLAIN async fn with 9+ parameters is refused at its declaration, by name (it compiled
# clean and died at its first force, exit 70). The 8-parameter form still compiles.
cat > "$T/l.cyr" <<EOF
$PRE
async fn a8(a, b, c, d, e1, f, g, h): i64 { return a + h * 100; }
async fn a9(a, b, c, d, e1, f, g, h, i9): i64 { return a + i9 * 100; }
fn main(): i64 { alloc_init(); var F = a9(1, 2, 3, 4, 5, 6, 7, 8, 9); return await F; }
var e = main();
syscall(60, e);
EOF
rc=0; CYRIUS_ASYNC=1 "$CC" < "$T/l.cyr" > "$T/l.bin" 2> "$T/l.err" || rc=$?
if [ "$rc" -ne 1 ]; then bad "L: a 9-parameter plain async fn compiled (rc $rc), want a refusal"
elif grep -q 'async fn `a9` takes 9 parameters' "$T/l.err" && ! grep -q '`a8`' "$T/l.err"; then ok "L: a9 refused by name, a8 accepted"
else bad "L: the refusal did not name a9 (or named a8): $(grep -m1 '^error' "$T/l.err")"; fi

if [ "$fails" -ne 0 ]; then echo "FAIL: coroutine_fnptr_and_completion — $fails axis(es) red"; exit 1; fi
echo "PASS: coroutine_fnptr_and_completion — fncallN / callptr / closure calls inside a coroutine reach their callee (A-C); a completed coroutine answers with its value and runs nothing again (D-F); 0- and 9-parameter coroutines (G-H); a fall-off completes (I1-I4); a plain Future runs once (K); 9+ plain parameters refused (L)"

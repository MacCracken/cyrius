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
# `.tcyr` (the tcyr runner cannot set an env var). The coroutine rows are x86 family only, like
# the transform itself; the plain-Future rows also run on aarch64 (qemu) and cx (cxvm).
#
#   A  fncall1(&fn, 10) between two awaits            -> 132 (was SIGSEGV)
#   B  a fn pointer taken BEFORE an await, called after with fncall2, and callptr -> 1030
#   C  a capturing closure called inside the coroutine  -> 150
#   D  a straight-line body forced 6 times              -> 3 x 0, then 327 x 3; body tail ran ONCE
#   E  a three-await loop with a defer, forced 10 times -> 3 x 0, then 3 x 7; defer ran ONCE
#   F  a TAIL-SHAPED `return helper(x);`, no defer, forced 6 times -> 0 0 12 12 12 12; helper ran
#      ONCE (a tail call's `jmp` skipped the epilogue that marks the coroutine done, so every later
#      force re-ran the tail; coroutines no longer tail-call)
#   G  a 0-parameter coroutine                          -> 0 7 7 7 7 (was SIGSEGV)       6.6.10
#   H  a 9-parameter coroutine                          -> 0 49 x4 (was exit 70)          6.6.10
#   I1-I4 a body that falls off its end (after an await, ending in one, on one path, with a
#      defer) completes with 0, its defer once (was a hang)                                6.6.10
#   J1 `await five()` x3 -> 555 (was 123, the suspend indices); J2 `await inner(21)` forces the
#      Future (was 1002, inner never ran); J3 a nested coroutine re-suspends until it is done, a
#      Future in a variable is forced and then answered from the memo; both callees are defined
#      BELOW the caller (pass 1 marks async fns)                                           6.6.10
#   J4 `await` inside a larger expression — a binary op's left operand, earlier call arguments
#      (2 and 9 args), `+=`, store64's address, a nested coroutine under a pushed word — keeps
#      what the expression had pushed (was 5 for 105 .. and a SIGSEGV for store64)         6.6.10
#   J5 `await (inner(3))` forces like `await inner(3)` (was the raw Future pointer); a vec_get
#      Future bound to a variable forces                                                    6.6.10
#   K  a plain Future forced 3 times runs its body once (was 103 203 303)                 6.6.10
#   L  a plain async fn with 9 parameters is refused by name; 8 compiles                  6.6.10
#   PE (wine) G H I1 J3 J4 K, aarch64 (qemu) K, cx (cxvm) K + L + the coroutine refusal (the cx
#   leg says PENDING while the tree has no src/backend/common/env.cyr — S2 bite 10 — and FAILS if
#   that file exists and the cx compiler still refuses CYRIUS_ASYNC).
#
# Mutations: remove the coroutine branch of ECALLIND -> A, B, C RED (139). Remove
# `_coro_mark_done` -> D, E, F RED (the tail and the defer re-run). Remove `_coro_done_check` ->
# D, E, F RED. Drop the `_cur_fn_coro` line of `_tc_frame_divert` -> F RED (helper ran 4 times).
# 6.6.10: coroutine argc word = pc -> G, H RED (PE G 0xC0000005, H exit 70). Drop the fall-off
# `jmp` -> I1-I4 RED (timeout). Never force an awaited Future -> J2, J3 RED. future_pending
# always 0 -> J3 RED. Drop the pass-1 `SFAS` -> J3 RED. Drop the memo hit in future_force -> K
# (x86, PE, aarch64) and J3 RED. Raise the arity cap -> L RED. Spill no pending pushes in
# `_await_coro_suspend` (d = 0) -> J4 and PE J4 RED. Drop the parenthesis look-through in
# `_await_operand_is_future` -> J5 RED.
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

# J — what `await e` yields inside a coroutine. It was the suspend INDEX (J1: 123 for 555), and
# an awaited Future was never forced (inner's body never ran).
cat > "$T/j1.cyr" <<EOF
$PRE
fn five(): i64 { return 5; }
async fn co(a): i64 {
    var s = await five();
    var t = await five();
    var u = await five();
    return s * 100 + t * 10 + u;
}
fn main(): i64 {
    alloc_init();
    var C = co(1);
    var n = 0;
    while (n < 5) { fmt_int(future_force(C)); syscall(1, 1, " ", 1); n = n + 1; }
    return 0;
}
var e = main();
syscall(60, 0);
EOF
run j1 '0 0 0 555 555 ' "J1: await of a plain call yields its value (was 123, the suspend indices)"

cat > "$T/j2.cyr" <<EOF
$PRE
var g_ran = 0;
async fn inner(k): i64 { g_ran = g_ran + 1; return k * 2; }
async fn outer(a): i64 {
    var s = await nopark();
    var v = await inner(21);
    return v + 1000;
}
fn main(): i64 {
    alloc_init();
    var C = outer(1);
    var n = 0;
    while (n < 4) { fmt_int(future_force(C)); syscall(1, 1, " ", 1); n = n + 1; }
    fmt_int(g_ran);
    return 0;
}
var e = main();
syscall(60, 0);
EOF
run j2 '0 0 1042 1042 1' "J2: await of an async fn call forces it (inner ran once; was 1002 and never ran)"

# J3 — a nested COROUTINE is driven to its value (re-suspending while it is pending), a Future
# held in a variable is forced, and forcing it again answers from the memo. `inner` and `later`
# are defined BELOW `outer`, so `await inner(a)` can only classify as a Future through pass 1.
cat > "$T/j3.cyr" <<EOF
$PRE
var g_in = 0;
var g_lt = 0;
async fn outer(a): i64 {
    var F = later(a);
    var v = await inner(a);
    var w = await F;
    var x = await F;
    var p = await nopark();
    return v * 1000 + w * 10 + x + p;
}
async fn later(k): i64 { g_lt = g_lt + 1; return k + 5; }
async fn inner(k): i64 { g_in = g_in + 1; var s = await nopark(); var t = await nopark(); return k * 3; }
fn main(): i64 {
    alloc_init();
    var C = outer(7);
    var n = 0;
    while (n < 8) { fmt_int(future_force(C)); syscall(1, 1, " ", 1); n = n + 1; }
    fmt_int(g_in); fmt_int(g_lt);
    return 0;
}
var e = main();
syscall(60, 0);
EOF
run j3 '0 0 0 0 0 0 21132 21132 11' "J3: a nested coroutine, a forward async fn in a variable, awaited twice"

# J4 — `await` INSIDE A LARGER EXPRESSION. Whatever the enclosing expression had pushed before the
# await was reached (a binary op's left operand, earlier call arguments, a compound-assign target,
# store64's address) was lost across the suspend, and the landing's pop took whatever sat at the
# new rsp: `b + await five()` gave 5, `add(1000, await five())` 5, `s += await five()` 5, and the
# store64 form SIGSEGV'd. Every shape here, including a nested coroutine that re-suspends while
# the outer expression still holds a pushed word, and a 9-argument call (stack arguments on PE).
cat > "$T/j4.cyr" <<EOF
$PRE
fn five(): i64 { return 5; }
fn add(x, y): i64 { return x + y; }
fn s9(a, b, c, d, e, f, g, h, i): i64 { return a + b + c + d + e + f + g + h + i * 1000; }
async fn inner(k): i64 { return k * 2; }
async fn cor2(k): i64 { var q = await five(); return q + k; }
async fn c_plus(a): i64 { var b = 100; var v = b + await five(); return v; }
async fn c_ret(a): i64 { return 1 + await inner(3); }
async fn c_mul(a): i64 { var b = 3; return b * await five(); }
async fn c_add(a): i64 { return add(1000, await five()); }
async fn c_s9(a): i64 { return s9(1, 1, 1, 1, 1, 1, 1, 1, await five()); }
async fn c_pluseq(a): i64 { var s = 100; s += await five(); return s; }
async fn c_store(a): i64 { var m = alloc(16); store64(m, 0); store64(m + 8, await five()); return load64(m + 8) + load64(m); }
async fn c_loop(a): i64 { var s = 100; var i = 0; while (i < 3) { s = s + await inner(i); i = i + 1; } return s; }
async fn c_nest(a): i64 { var b = 1000; return b + await cor2(20); }
async fn c_two(a): i64 { return await five() * 10 + await five(); }
fn drain(C): i64 { var r = 0; var n = 0; while (n < 6) { r = future_force(C); n = n + 1; } fmt_int(r); syscall(1, 1, " ", 1); return 0; }
fn main(): i64 {
    alloc_init();
    drain(c_plus(0)); drain(c_ret(0)); drain(c_mul(0)); drain(c_add(0)); drain(c_s9(0));
    drain(c_pluseq(0)); drain(c_store(0)); drain(c_loop(0)); drain(c_nest(0)); drain(c_two(0));
    return 0;
}
var e = main();
syscall(60, 0);
EOF
run j4 '105 7 15 1005 5008 105 5 106 1025 55 ' "J4: await inside a larger expression keeps what the expression had pushed"

# J5 — the operand's SHAPE decides whether the landing forces it, and parentheses do not change
# the shape: `await (inner(3))` forces like `await inner(3)` (it yielded the raw Future pointer).
# A Future reached through a call to a PLAIN fn is "anything else" — bound to a variable first,
# `await F` forces it (the documented idiom).
cat > "$T/j5.cyr" <<EOF
$PRE
async fn inner(k): i64 { return k * 2; }
async fn c_paren(a): i64 { var v = await (inner(3)); return v; }
async fn c_pvar(a): i64 { var F = inner(4); var v = await ((F)); return v; }
async fn c_vec(a): i64 { var vv = vec_new(); vec_push(vv, inner(5)); var F = vec_get(vv, 0); var v = await F; return v; }
fn drain(C): i64 { var r = 0; var n = 0; while (n < 4) { r = future_force(C); n = n + 1; } fmt_int(r); syscall(1, 1, " ", 1); return 0; }
fn main(): i64 { alloc_init(); drain(c_paren(0)); drain(c_pvar(0)); drain(c_vec(0)); return 0; }
var e = main();
syscall(60, 0);
EOF
run j5 '6 8 10 ' "J5: a parenthesised Future operand forces; a vec_get Future forces once bound to a variable"

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

# ── the same rows on PE (wine) and, for the plain-Future row, aarch64 (qemu) ──────────────────
# CYRIUS_ASYNC is a compiler env knob, so async rows exist only as shell gates; these legs are what
# exercises the lockstep lib/async.cyr + constructor off the x86_64-Linux path.
xrun() {    # <runner> <compiler> <tag> <want> <what>
    rc=0
    CYRIUS_ASYNC=1 "$2" < "$T/$3.cyr" > "$T/$3.x" 2> "$T/$3.xerr" || rc=$?
    if [ "$rc" -ne 0 ]; then bad "$5: rc $rc: $(grep '^error' "$T/$3.xerr" | head -1)"; return; fi
    chmod +x "$T/$3.x"
    got=$( (ulimit -c 0; timeout 60 "$1" "$T/$3.x") 2>/dev/null); e=$?
    if [ "$e" -ne 0 ]; then bad "$5: exit $e (output '$got')"
    elif [ "$got" = "$4" ]; then ok "$5: $got"
    else bad "$5: printed '$got', want '$4'"; fi
}
if command -v wine > /dev/null 2>&1; then
    WCC="$T/wcc.sh"; printf '#!/bin/sh\nCYRIUS_TARGET_WIN=1 exec "%s"\n' "$CC" > "$WCC"; chmod +x "$WCC"
    WRUN="$T/wrun.sh"
    printf '#!/bin/sh\nWINEPREFIX="%s" WINEDEBUG=-all WINEDLLOVERRIDES="winemenubuilder.exe=d;mscoree=d;mshtml=d" exec wine "$1"\n' "$T/wp" > "$WRUN"; chmod +x "$WRUN"
    xrun "$WRUN" "$WCC" g '0 7 7 7 7 ' "PE G: 0-parameter coroutine"
    xrun "$WRUN" "$WCC" h '0 49 49 49 49 ' "PE H: 9-parameter coroutine"
    xrun "$WRUN" "$WCC" i1 '0 0 0 0 1' "PE I1: fall-off completes"
    xrun "$WRUN" "$WCC" j3 '0 0 0 0 0 0 21132 21132 11' "PE J3: await values"
    xrun "$WRUN" "$WCC" j4 '105 7 15 1005 5008 105 5 106 1025 55 ' "PE J4: await inside a larger expression"
    xrun "$WRUN" "$WCC" k '103 103 103 7 7 11' "PE K: a plain Future runs once"
else echo "  SKIP: PE leg (wine not installed)"; fi
if command -v qemu-aarch64 > /dev/null 2>&1; then
    if "$CC" < "$ROOT/src/main_aarch64.cyr" > "$T/cc_a64" 2>/dev/null && chmod +x "$T/cc_a64"; then
        xrun qemu-aarch64 "$T/cc_a64" k '103 103 103 7 7 11' "aarch64 K: a plain Future runs once"
    else bad "aarch64 leg: src/main_aarch64.cyr did not build"; fi
else echo "  SKIP: aarch64 leg (qemu-aarch64 not installed)"; fi

# ── cx: the plain-Future memo runs under cxvm, and the 9-parameter and coroutine refusals name
# themselves. ⚠ Until the cx compiler reads CYRIUS_ASYNC (S2 bite 10 wires cx `_read_env`) every
# cx compile stops at "requires CYRIUS_ASYNC=1"; the leg says PENDING instead of passing.
if "$CC" < "$ROOT/src/main_cx.cyr" > "$T/cc_cx" 2>/dev/null && chmod +x "$T/cc_cx" \
   && "$CC" < "$ROOT/programs/cxvm.cyr" > "$T/cxvm" 2>/dev/null && chmod +x "$T/cxvm"; then
    rc=0; CYRIUS_ASYNC=1 "$T/cc_cx" < "$T/k.cyr" > "$T/k.cyx" 2> "$T/k.cxerr" || rc=$?
    # ⛔ PENDING is allowed ONLY while the tree has no src/backend/common/env.cyr — the file S2
    # bite 10 adds to wire cx `_read_env`. Once it exists the leg must be real: a cx compiler that
    # still refuses CYRIUS_ASYNC there is a FAIL, not a vacuous pass. CHANGELOG [6.6.10]
    if grep -q 'requires CYRIUS_ASYNC=1' "$T/k.cxerr" && [ -f "$ROOT/src/backend/common/env.cyr" ]; then
        bad "cx leg: src/backend/common/env.cyr is present but the cx compiler still refuses CYRIUS_ASYNC=1"
    elif grep -q 'requires CYRIUS_ASYNC=1' "$T/k.cxerr"; then
        echo "  PENDING cx leg: the cx compiler cannot read CYRIUS_ASYNC yet (S2 bite 10: no src/backend/common/env.cyr)"
    else
        if [ "$rc" -ne 0 ]; then bad "cx K: rc $rc: $(grep -m1 '^error' "$T/k.cxerr")"
        else
            got=$( (ulimit -c 0; timeout 60 "$T/cxvm" < "$T/k.cyx") 2>/dev/null)
            if [ "$got" = '103 103 103 7 7 11' ]; then ok "cx K: a plain Future runs once under cxvm: $got"
            else bad "cx K: printed '$got', want '103 103 103 7 7 11'"; fi
        fi
        rc=0; CYRIUS_ASYNC=1 "$T/cc_cx" < "$T/l.cyr" > /dev/null 2> "$T/l.cxerr" || rc=$?
        if [ "$rc" -ne 0 ] && grep -q 'async fn `a9` takes 9 parameters' "$T/l.cxerr"; then ok "cx L: a9 refused by name"
        else bad "cx L: rc $rc, $(grep -m1 '^error' "$T/l.cxerr")"; fi
        rc=0; CYRIUS_ASYNC=1 "$T/cc_cx" < "$T/g.cyr" > /dev/null 2> "$T/g.cxerr" || rc=$?
        if [ "$rc" -ne 0 ] && grep -q 'cx backend has no coroutine frame' "$T/g.cxerr"; then ok "cx G: a coroutine is refused, naming the cx backend"
        else bad "cx G: rc $rc, $(grep -m1 '^error' "$T/g.cxerr")"; fi
    fi
else bad "cx leg: could not build src/main_cx.cyr / programs/cxvm.cyr"; fi

if [ "$fails" -ne 0 ]; then echo "FAIL: coroutine_fnptr_and_completion — $fails axis(es) red"; exit 1; fi
echo "PASS: coroutine_fnptr_and_completion — fncallN / callptr / closure calls inside a coroutine reach their callee (A-C); a completed coroutine answers with its value and runs nothing again (D-F); 0- and 9-parameter coroutines (G-H); a fall-off completes (I1-I4); await yields its value and forces Futures, inside any expression (J1-J5); a plain Future runs once (K); 9+ plain parameters refused (L); PE / aarch64 / cx legs"

#!/bin/sh
# destructure_one_value_refused.sh — 6.6.17 (a5). `var a, b = f();` where f provably returns ONE
# value is a compile error naming f and its arity, at fn scope and at top level (both zones); the
# declaration-zone top-level destructure gets the whole destructure contract fn scope has.
#
# WHY. The second name took whatever rdx held, silently: `fn one(x) { return x + 5; }` then
# `var a, b = one(1);` built clean on every release through 6.6.16, inside a fn and at top level.
# Before the first top-level statement the destructure is replayed by EMIT_GVAR_INITS, which had no
# contract at all: `var a, b = 42;`, a call followed by arithmetic and a declared-arity mismatch
# compiled there too. Pass 1 records "returns one value" per fn (`_prescan_ret_single`, GFLG bit
# 1024), so a call to a fn defined LATER is judged the same.
#
#   axis 1  refused, exit 1, the message names the callee, no binary: fn scope, a forward-declared
#           callee, both top-level zones, three names, a method, a generic instance; the
#           declaration zone's non-call / partial-call / declared-arity rows; each bad declaration
#           of a file reported (no panic swallow).
#   axis 2  ANTI-VACUOUS: every shape that CAN carry a second value still compiles and runs right —
#           a tuple return, `ret2`, a declared `: (i64, i64)`, a forwarding wrapper, a Result value
#           form, a `: stack` enum, a 16 B struct, a body that falls off its end after a pair call.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: destructure_one_value_refused: cannot cd to $ROOT"; exit 1; }
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: destructure_one_value_refused: $CC not built"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: destructure_one_value_refused: mktemp -d failed"; exit 1; }
trap 'rm -rf "$T"' EXIT
fails=0
rows=0
check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 - expected $2, got $3"; fails=$((fails + 1)); fi
}
# refused <name> <source> <fragment> [<error lines, default 1>]
refused() {
    rows=$((rows + 1))
    printf '%b' "$2" > "$T/$1.cyr"
    want=1
    if [ $# -ge 4 ]; then want=$4; fi
    rc=0
    "$CC" < "$T/$1.cyr" > "$T/$1.out" 2> "$T/$1.err" || rc=$?
    check "$1: exits 1" 1 "$rc"
    check "$1: names it" yes "$(grep -qF -- "$3" "$T/$1.err" && echo yes || echo no)"
    check "$1: error lines" "$want" "$(grep -c '^error' "$T/$1.err")"
    check "$1: emits no binary" 0 "$(wc -c < "$T/$1.out" | tr -d ' ')"
}
# runs <name> <source> <exit>
runs() {
    rows=$((rows + 1))
    printf '%b' "$2" > "$T/$1.cyr"
    rc=0
    "$CC" < "$T/$1.cyr" > "$T/$1.bin" 2> "$T/$1.err" || rc=$?
    check "$1: compiles" 0 "$rc"
    if [ "$rc" -ne 0 ]; then echo "       $(grep '^error' "$T/$1.err" | head -2)"; return 0; fi
    chmod +x "$T/$1.bin" 2>/dev/null
    rc=0; "$T/$1.bin" > /dev/null 2>&1 || rc=$?
    check "$1: exits $3" "$3" "$rc"
}

ONE='fn one(x) { return x + 5; }\n'
M2="binds 2 names, but 'one' returns 1 value"
echo "axis 1 - a one-value callee is refused by name:"
refused fn_scope   "${ONE}fn f(): i64 {\n    var a, b = one(1);\n    return a + b;\n}\nsyscall(60, f());\n" "$M2"
refused forward    "fn f(): i64 {\n    var a, b = later(1);\n    return a + b;\n}\nsyscall(60, f());\nfn later(x) { var y = x * 2; return y; }\n" "but 'later' returns 1 value"
refused top_decl   "${ONE}var a, b = one(1);\nsyscall(60, a + b);\n" "$M2"
refused top_late   "${ONE}syscall(39);\nvar a, b = one(1);\nsyscall(60, a + b);\n" "$M2"
refused three      "${ONE}fn f(): i64 {\n    var a, b, c = one(1);\n    return a;\n}\nsyscall(60, f());\n" "binds 3 names, but 'one' returns 1 value"
refused method     'struct P { x; }\nfn P_get(self: P) { return self.x; }\nfn f(): i64 {\n    var p = P { 4 };\n    var a, b = p.get();\n    return a;\n}\nsyscall(60, f());\n' "but 'P_get' returns 1 value"
refused generic    'fn g<T>(x: T) { return x; }\nfn f(): i64 {\n    var a, b = g<i32>(4);\n    return a;\n}\nsyscall(60, f());\n' "returns 1 value"
refused zone_each  "${ONE}var a, b = one(1);\nvar c, d = one(2);\nsyscall(60, a);\n" "$M2" 2
refused zone_nocall 'var a, b = 42;\nsyscall(60, a);\n' "multi-value destructure needs a call on the right-hand side"
refused zone_partial 'fn two(x) { return (x, x + 1); }\nvar a, b = two(1) + 3;\nsyscall(60, a);\n' "multi-value destructure needs a call on the right-hand side"
refused zone_decl  'fn two(): (i64, i64) { return (1, 2); }\nvar a, b, c = two();\nsyscall(60, a);\n' "count does not match the fn's declared return arity"

echo "axis 2 - every callee that can carry a second value still destructures:"
runs tuple    'fn two(x) { return (x, x + 1); }\nfn f(): i64 {\n    var a, b = two(3);\n    return a * 10 + b;\n}\nsyscall(60, f());\n' 34
runs tuple_top 'fn two(x) { return (x, x + 1); }\nvar a, b = two(5);\nsyscall(60, a * 10 + b);\n' 56
runs ret2     'fn two(x) { ret2(x, x * 2); }\nfn f(): i64 {\n    var a, b = two(3);\n    return a * 10 + b;\n}\nsyscall(60, f());\n' 36
runs declared 'fn two(): (i64, i64) { return (4, 2); }\nvar a, b = two();\nfn f(): i64 { var c, d = two(); return c + d; }\nsyscall(60, a * 10 + b + f());\n' 48
runs forward_wrap 'fn w(x) { return two(x); }\nfn f(): i64 {\n    var a, b = w(2);\n    return a * 10 + b;\n}\nsyscall(60, f());\nfn two(x) { return (x, x + 5); }\n' 27
runs result   'include "lib/result.cyr"\nfn mk(x): Result { if (x > 0) { return Ok(x); } return Err(1); }\nfn f(): i64 {\n    var t, v = mk(9);\n    return t * 10 + v;\n}\nsyscall(60, f());\n' 9
runs stack_enum 'enum E: stack { A(v); B(v); }\nfn mk(x) { return A(x); }\nfn f(): i64 {\n    var t, v = mk(7);\n    return t * 10 + v;\n}\nsyscall(60, f());\n' 7
# A body that falls off its end returns what its last statement left: here two()'s pair.
runs falls_off 'fn two(x) { return (x, x + 5); }\nfn w(x) { var k = x; two(k); }\nfn f(): i64 {\n    var a, b = w(2);\n    return a * 10 + b;\n}\nsyscall(60, f());\n' 27
runs pair_struct 'struct Q { a; b; }\nfn mq(x): Q { var q: Q; q.a = x; q.b = x + 1; return q; }\nfn f(): i64 {\n    var a, b = mq(3);\n    return a * 10 + b;\n}\nsyscall(60, f());\n' 34

if [ "$rows" -lt 20 ]; then echo "FAIL: destructure_one_value_refused: only $rows rows ran (floor 20)"; exit 1; fi
if [ "$fails" -ne 0 ]; then echo "FAIL: destructure_one_value_refused: $fails check(s) failed"; exit 1; fi
echo "PASS: destructure_one_value_refused ($rows rows)"
exit 0

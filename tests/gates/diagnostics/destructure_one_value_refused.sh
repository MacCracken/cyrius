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
#   axis 3  6.7.11 — a body that ENDS in an infinite loop leaves only through its `return`s: `loop { }`,
#           `while (1) { }` and `do { } while (1);` are proved one value as a final `return` is, at fn
#           scope and at top level; a `break` only in a nested loop / switch, or a closure's `return`,
#           does not unprove it. A loop a `break` can leave stays silent (the body falls off its end),
#           and so does a non-literal-1 condition. (6.7.13, D27 A, the user's decision, 2026-10-15) `while (true)
#           { }` and `do { } while (true);` are proved as their `1` spellings are (the bool literal 1; both
#           repros of issues/archived/2026-10-13-while-true-ending-fn-not-provably-single-return.md read the seeded 77
#           on every target), and pass 1's arity record sees them (cnt_while_true).
#   axis 4  6.7.11 — an UNDECLARED fn whose every `return` is `(..)` of one arity, and whose body is
#           left only through them, returns that many values (pass 1, `_prescan_ret_arity`): a
#           destructure binding another count is refused by name (`var q, r, z = dm(17, 5);` bound z
#           to whatever r8 held) — fn scope, both top-level zones, a forward callee, a method, a
#           generic, a loop-ending body, `q, r, z = dm(..)`. The matching counts, a fn mixing
#           arities and a fn that can fall off its end stay silent.
#   axis 5  6.7.11 — THE PRODUCER: a fn declared `: (T1, T2[, T3])` returns its values. Only `return
#           (a, b[, c]);` of the declared arity, `return t;` of a tuple and a whole forwarded call whose
#           callee returns as many values (or cannot be judged) write every return register; anything
#           else — `return 5;` (d4), `return p;` of a struct local (v1), a bare `return;`, a literal of
#           another arity, a call to a one-value / struct / other-arity callee, the tail-call arm
#           included — is refused at the fn, so the caller's `b` cannot read a stale rdx (77 seeded, on
#           every target). The controls compile and run: a forwarded call of the same arity (56), a
#           wrapped one, an undeclared callee of that arity, a recursive one, a method and a generic,
#           a tuple local, a closure's and an #inline callee's own returns inside the fn. (6.7.13) `ret2(a, b)` in
#           a fn declared with three values is refused the same way (D21 A); in a 2-value fn it runs.
#           (6.7.13, D28 C, the user's decision, 2026-10-15) A body that reaches its `}` returns 0 for every
#           value, nothing refused (issues/archived/2026-10-13-declared-multi-value-fn-falls-off-its-end.md: the repro
#           read the seeded 77 on every target): the repro verbatim (0), three values, a defer (it runs, the
#           values stay 0), an f64 pair, an #inline replay; the return taken, an if / else whose arms both
#           return (34) and a `while (1)` end (42) are unchanged.
#           (6.7.13, D23 B, the user's decision, 2026-10-15) A sync fn declared ONE type may return several
#           values — kept and documented (issues/archived/2026-10-14-scalar-declared-fn-returning-multi-value-literal.md):
#           the issue's two programs verbatim (1: a one-name bind keeps the first value; 12) and its ret2 form
#           (1) run; pass 1 counts a `return (a, b);` body, so three names from `: i64` / `: f64` and a 3-tuple
#           capture are refused; a `: f64` fn's values are each an f64 (3.0); a `: bool` fn's first value is
#           checked as its bool.
#   axis 6  6.7.13 — `callptr(fp, ..)` is a call (issues/archived/2026-10-13-destructure-of-callptr-refused.md): `var c, d =
#           callptr(fp, 5);` was refused "needs a call on the right-hand side" where `fncall1(fp, 5)` destructures.
#           Accepted in a fn (the repro verbatim, 22), as an assignment and a for step, in both top-level zones;
#           three names are accepted as `fncall1`'s are (an unknown callee is not judged, D31); `callptr(..) + 1`
#           is still refused. MUTATION: `_dt_rhs_check_t` without its `callptr` line -> cp_repro, cp_assign,
#           cp_for, cp_zone, cp_top, cp_three refused.
#   axis 7  6.7.14 (D42, the user's decision, 2026-10-16) — `ret2(a, b)` is two values to pass 1's count
#           (issues/2026-10-15-ret2-body-not-counted-three-names-read-stale-register.md: every filed shape read the
#           seeded 88 on x86_64 / aarch64 / cx / PE). A `ret2(..);` statement and `return ret2(..);` are two-value
#           exits, and a body may end in `ret2(..);` or in an if / elif / else whose every arm ends in an exit, so
#           `var a, b, c = g2();` and a 3-tuple capture are refused by the existing text — the five filed shapes,
#           a `ret2` beside a `return (a, b);`, an elif chain, an if / else of `return (a, b);` arms (left only
#           through them: the same rule), both top-level zones, a forward callee, a method, a generic, `a, b, c =`;
#           the count is read wherever a `return (a, b);` fn's is (a struct argument, a 3-value forward). The
#           two-name bind (the guide's `divmod_old`), a one-name bind + `rethi()`, a `ret2` inside an expression
#           and a body that can fall off its end stay as they were. Every row on x86_64, aarch64 (cross; qemu),
#           cx (cxvm) and PE (wine, a private prefix); a missing tool is a SKIP that names it.
#           MUTATIONS (scratch trees, run 2026-10-17, CYCC= the mutant): the tree before (c4930b46) -> every r2_
#           refusal but the r2_control BUILDS (16); `_prescan_ret_arity`'s ret2 arm back to the bail -> the same less
#           r2_ret and r2_ifelse_ret (14); `_ret_stmt_arity` without its ret2 arm -> r2_ret; `_ar_exits` without its
#           `ret2(..);` tail -> the bail's 14 less r2_mid; without its if / else arm -> r2_mixed r2_elif
#           r2_ifelse_ret; `_ret2_stmt` accepting any ret2 -> r2_expr refused.
#   axis 8  6.7.14 (D45, the user's decision, 2026-10-16) — PARENTHESES AROUND THE WHOLE CALL ARE TRANSPARENT to
#           the destructure (issues/2026-10-15-paren-wrapped-call-destructure-refused.md: the filed program was "needs a
#           call on the right-hand side" twice on x86_64 / aarch64 / cx / PE; unwrapped it exits 41). `_dt_wrap_k` (k `(`,
#           one call, k `)`, then the terminator): the issue's program verbatim (41), `((..))`, the assignment `c, d =
#           (..);`, a for step, both top-level zones, `callptr`, a method and an explicit generic, f64 bindings typed
#           through the wrap, a wrapped destructure inside a closure among the wrapped call's arguments (each wrap's
#           count is its own). Still refused, by the same text at the call: `(f(7)) + 1` and `(two(7) + 1)` ("needs a
#           call", in a fn and in the zone), a declared-arity mismatch, an undeclared count, a one-value callee and a
#           struct callee of `a, b = (..)`. Every row on x86_64, aarch64 (qemu), cx (cxvm) and PE (wine).
#           MUTATIONS (scratch trees, run 2026-10-17, CYCC= the mutant, every leg): the tree before (79b72c77) -> every
#           pw_ run row refused ("needs a call"), and pw_arity3 pw_count3 pw_one pw_zone_arity pw_masg_arity
#           pw_masg_struct by that text, not their own; `_dt_wrap_k` answering 0 -> the same; PARSE_VAR without its
#           `_pw_close` -> pw_repro pw_double pw_top pw_callptr pw_method pw_f64 pw_nested; `_masg_stmt` without it ->
#           pw_assign (a for step's replay ends at its own `)`, so pw_for holds either way); the zone replay without it
#           -> pw_zone; `_dt_wterm` answering `term` -> the before-tree's rows less pw_for (a for step's terminator is
#           `)` already).
#
# MUTATIONS (6.7.11, each run against this gate): `_body_ends_in_loop` returning 0 -> loop_end,
# while1_end, dowhile1_end, loop_top, loop_nested_brk, loop_switch_brk build; its `loop` arm dropped
# -> loop_end, loop_top, loop_nested_brk build; its `while (1) {` arm dropped -> while1_end,
# loop_switch_brk build; its do-tail arm dropped -> dowhile1_end builds; `_brk_inner_end` returning
# -1 (no nested construct stepped) -> loop_nested_brk, loop_switch_brk build; `_loop_exits_by_return`
# blind to `break` -> loop_brk, do_brk, while_do_brk refused; `_brk_inner_end` not stopping at a `;`
# (a do-while's tail `while (c);` taken to own the next block) -> while_do_brk refused.
# Axis 4: `_prescan_ret_arity` recording nothing -> every cnt_ refusal builds; `_dt_arity_check`
# without its count arm -> the same; `_ret_stmt_arity` answering 2 for any tuple -> cnt_two_of_three
# builds, cnt_three refused; the mixed-arity guard dropped (the last return's count kept) ->
# cnt_mixed refused; the `_body_ends_in_return` test dropped from the arity proof -> cnt_falls_off
# refused; a generic instance not inheriting the base's record (`_gen_inst_record`) -> cnt_generic
# builds (`g<i32>` mints `g$i32`).
# Axis 5: `_mret_ret_check` answering 0 -> every ret_ refusal builds; `_mret_fwd_ok` answering 1 ->
# ret_tail_one, ret_tail_fwd, ret_fwd_arity3, ret_fwd_undecl3, ret_fwd_struct, ret_fwd_struct_tup
# build; its struct arm dropped -> ret_fwd_struct_tup builds; its one-value arm dropped ->
# ret_tail_one, ret_tail_fwd build; the literal's count not compared -> ret_lit3, ret_lit2 build;
# the call not looked for inside parentheses -> ret_fwd_wrap refused; `callptr` not taken for a call
# of an unknown callee -> ret_fwd_callptr refused; the #inline-replay guard
# dropped -> ret_inline_one, ret_inline_two refused; the tuple-local arm dropped -> ret_tuple
# refused (and tuple_checked.sh's A rows); the late report not yielding to the arms' own refusal ->
# tuple_checked.sh R9n, R9s, R9t, R14n give two errors.
# 6.7.13 (run 2026-10-15): `_cond_is_one` without its `true` arm -> while_true_end, dowhile_true_end,
# while_true_top and cnt_while_true build (tuple_checked.sh R16x-true too).
# 6.7.13 (run 2026-10-15): `_mret_falloff` answering 0 -> fall_off_2, fall_off_3, fall_off_defer, fall_off_f64
# read the stale registers (77, 9, 9, 9); `_mret_falloff_fi` answering 0 -> fall_off_inline (117: 40 + 77).
# 6.7.13 (run 2026-10-15): `_prescan_ret_arity` recording nothing for a scalar-declared fn -> sc_count3,
# sc_f64_count3, sc_tup3 build (the rows pin D23 B's count, which that record carries).
# 6.7.13 (run 2026-10-15): `_ret2_in3` answering 0 at once -> ret2_in_3, ret2_in_3_gen build, ret2_in_3_next
# one error line (return_ret2_in_3 stays refused, by the return check); its `_tn_once` dropped -> ret2_in_3_gen
# two error lines; the latch left set -> ret2_in_3_next one error line (the next statement's lost).
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

echo "axis 3 - a body ending in an infinite loop is proved one value:"
refused loop_end   "fn one(x) { loop { return x + 1; } }\nfn f(): i64 {\n    var a, b = one(1);\n    return b;\n}\nsyscall(60, f());\n" "$M2"
refused while1_end "fn one(x) { while (1) { return x + 1; } }\nfn f(): i64 {\n    var a, b = one(1);\n    return b;\n}\nsyscall(60, f());\n" "$M2"
refused dowhile1_end "fn one(x) { var i = 0; do { i = i + 1; if (i > x) { return i; } } while (1); }\nfn f(): i64 {\n    var a, b = one(1);\n    return b;\n}\nsyscall(60, f());\n" "$M2"
refused loop_top   "fn one(x) { loop { if (x > 2) { return x; } x = x + 1; } }\nvar a, b = one(1);\nsyscall(60, a + b);\n" "$M2"
refused loop_nested_brk "fn one(x) { var i = 0; loop { while (i < 3) { i = i + 1; if (i == 2) { break; } } for (var k = 0; k < 3; k = k + 1) { if (k == 1) { break; } } return i + x; } }\nfn f(): i64 {\n    var a, b = one(1);\n    return b;\n}\nsyscall(60, f());\n" "$M2"
refused loop_switch_brk "fn one(x) { var i = 0; while (1) { switch (x) { case 1: break; default: i = 1; } return i; } }\nfn f(): i64 {\n    var a, b = one(1);\n    return b;\n}\nsyscall(60, f());\n" "$M2"
TWO5='fn two(x) { return (x, x + 5); }\n'
# A loop a `break` leaves, as the body's last statement: the body falls off its end with the pair
# two() left (each loop also holds a `return`, so only the break keeps it unproved).
runs loop_brk  "${TWO5}fn w(x) { loop { if (x > 0) { two(x); break; } return x; } }\nfn f(): i64 {\n    var a, b = w(2);\n    return a * 10 + b;\n}\nsyscall(60, f());\n" 27
runs do_brk    "${TWO5}fn w(x) { var i = 0; do { i = i + 1; if (i > 50) { return i; } if (i > 2) { two(x); break; } } while (1); }\nfn f(): i64 {\n    var a, b = w(2);\n    return a * 10 + b;\n}\nsyscall(60, f());\n" 27
runs while_do_brk "${TWO5}fn w(x) { var i = 0; while (1) { do { i = i + 1; } while (i < 3); if (i > x) { two(x); break; } return i; } }\nfn f(): i64 {\n    var a, b = w(2);\n    return a * 10 + b;\n}\nsyscall(60, f());\n"  27
runs loop_fwd  "${TWO5}fn w(x) { loop { return two(x); } }\nfn f(): i64 {\n    var a, b = w(2);\n    return a * 10 + b;\n}\nsyscall(60, f());\n" 27
# 6.7.13 (D27 A): the `true` spellings — both repros verbatim (seeded: they read h's 77), top level, and a loop
# a `break` leaves (still silent).
refused while_true_end "fn h(): (i64, i64, i64) { return (1, 77, 88); }\nfn one(x) { while (true) { return x + 1; } }\nfn main(): i64 { var x, y, w = h(); var a, b = one(1); return b; }\nvar r = main(); syscall(60, r);\n" "3:48: multi-value destructure $M2"
refused dowhile_true_end "fn h(): (i64, i64, i64) { return (1, 77, 88); }\nfn one(x) { do { if (x > 0) { return x + 1; } x = x + 1; } while (true); }\nfn main(): i64 { var x, y, w = h(); var a, b = one(1); return b; }\nvar r = main(); syscall(60, r);\n" "3:48: multi-value destructure $M2"
refused while_true_top "fn one(x) { while (true) { if (x > 2) { return x; } x = x + 1; } }\nvar a, b = one(1);\nsyscall(60, a + b);\n" "$M2"
runs while_true_brk "${TWO5}fn w(x) { while (true) { if (x > 0) { two(x); break; } return x; } }\nfn f(): i64 {\n    var a, b = w(2);\n    return a * 10 + b;\n}\nsyscall(60, f());\n" 27
runs dowhile_true_brk "${TWO5}fn w(x) { do { if (x > 0) { two(x); break; } return x; } while (true); }\nfn f(): i64 {\n    var a, b = w(2);\n    return a * 10 + b;\n}\nsyscall(60, f());\n" 27

echo "axis 4 - an undeclared fn's provable count is checked as a declared one:"
DM='fn dm(a, b) { return (a / b, a % b); }\n'
H3='fn h3(a) { return (a, a + 1, a + 2); }\n'
C32="binds 3 names, but 'dm' returns 2 values"
# t7 verbatim (the 6.7.7 B4 planners' probe), then seeded: an earlier 3-value call leaves 88 in r8.
refused cnt_t7     "${DM}fn main(): i64 { var q, r, z = dm(17, 5); return q * 10 + r; }\nvar r = main(); syscall(60, r);\n" "$C32"
refused cnt_seeded "fn h(): (i64, i64, i64) { return (1, 77, 88); }\n${DM}fn main(): i64 { var x, y, w = h(); var q, r, z = dm(17, 5); return z; }\nvar r = main(); syscall(60, r);\n" "$C32"
refused cnt_two_of_three "${H3}fn f(): i64 {\n    var q, r = h3(1);\n    return q * 10 + r;\n}\nsyscall(60, f());\n" "binds 2 names, but 'h3' returns 3 values"
refused cnt_top_decl "${DM}var q, r, z = dm(17, 5);\nsyscall(60, q);\n" "$C32"
refused cnt_top_late "${DM}syscall(39);\nvar q, r, z = dm(17, 5);\nsyscall(60, q);\n" "$C32"
refused cnt_forward "fn f(): i64 {\n    var q, r, z = later(17, 5);\n    return q;\n}\nsyscall(60, f());\nfn later(a, b) { return (a / b, a % b); }\n" "binds 3 names, but 'later' returns 2 values"
refused cnt_method 'struct P { x; }\nimpl P { fn dm(self, b) { return (self.x / b, self.x % b); } }\nfn f(): i64 {\n    var p = P { 17 };\n    var q, r, z = p.dm(5);\n    return q;\n}\nsyscall(60, f());\n' "binds 3 names, but 'P.dm' returns 2 values"
refused cnt_generic 'fn g<T>(a: T) { return (a, a + 1); }\nfn f(): i64 {\n    var q, r, z = g<i32>(5);\n    return q;\n}\nsyscall(60, f());\n' "binds 3 names, but 'g<i32>' returns 2 values"
refused cnt_loop   "fn dm(a, b) { loop { if (b > 0) { return (a / b, a % b); } b = b + 1; } }\nfn f(): i64 {\n    var q, r, z = dm(17, 5);\n    return q;\n}\nsyscall(60, f());\n" "$C32"
refused cnt_while_true "fn dm(a, b) { while (true) { if (b > 0) { return (a / b, a % b); } b = b + 1; } }\nfn f(): i64 {\n    var q, r, z = dm(17, 5);\n    return q;\n}\nsyscall(60, f());\n" "$C32"
refused cnt_reassign "${DM}fn f(): i64 {\n    var q = 0;\n    var r = 0;\n    var z = 0;\n    q, r, z = dm(17, 5);\n    return q;\n}\nsyscall(60, f());\n" "$C32"
runs cnt_two      "${DM}fn f(): i64 {\n    var q, r = dm(17, 5);\n    return q * 10 + r;\n}\nsyscall(60, f());\n" 32
runs cnt_three    "${H3}fn f(): i64 {\n    var q, r, s = h3(1);\n    return q * 100 + r * 10 + s;\n}\nsyscall(60, f());\n" 123
runs cnt_top      "${DM}var q, r = dm(17, 5);\nsyscall(60, q * 10 + r);\n" 32
# Mixed arities and a body that can fall off its end (here with h3's three values) record nothing.
runs cnt_mixed    "fn mix(a) { if (a > 0) { return (a, 1); } return (a, 2, 3); }\nfn f(): i64 {\n    var q, r = mix(4);\n    return q * 10 + r;\n}\nsyscall(60, f());\n" 41
runs cnt_falls_off "${H3}fn w(x) { if (x > 5) { return (x, 1); } h3(x); }\nfn f(): i64 {\n    var q, r, s = w(1);\n    return q * 100 + r * 10 + s;\n}\nsyscall(60, f());\n" 123

echo "axis 5 - a fn declared with its values returns them:"
R2="'f' returns 2 values - return (a, b)"
G56='fn g(x): (i64, i64) { return (x, x + 1); }\n'
SEED='fn h(): (i64, i64, i64) { return (1, 77, 88); }\n'
# d4 and v1 verbatim (the 6.7.7 B4 planners' probes), then the seeded shapes 2 and 3 verbatim.
refused ret_d4     'fn f(): (i64, i64) { return 5; }\nfn main(): i64 { var a, b = f(); return a; }\nvar r = main(); syscall(60, r);\n' "$R2"
refused ret_v1     'struct P { a; b; }\nfn f(): (i64, i64) { var p = P { 3, 4 }; return p; }\nfn main(): i64 { var a, b = f(); return a * 10 + b; }\nvar r = main(); syscall(60, r);\n' "$R2"
refused ret_s2     "${SEED}fn f(): (i64, i64) { return 5; }\nfn main(): i64 { var x, y, w = h(); var a, b = f(); return b; }\nvar r = main(); syscall(60, r);\n" "$R2"
refused ret_s3     "struct P { a; b; }\n${SEED}fn f(): (i64, i64) { var p = P { 3, 4 }; return p; }\nfn main(): i64 { var x, y, w = h(); var a, b = f(); return b; }\nvar r = main(); syscall(60, r);\n" "$R2"
refused ret_top_decl 'fn f(): (i64, i64) { return 5; }\nvar a, b = f();\nsyscall(60, a + b);\n' "$R2"
refused ret_top_late 'struct P { a; b; }\nfn f(): (i64, i64) { var p = P { 3, 4 }; return p; }\nsyscall(39);\nvar a, b = f();\nsyscall(60, a + b);\n' "$R2"
refused ret_bare   'fn f(): (i64, i64) { return; }\nvar a, b = f();\nsyscall(60, a);\n' "$R2"
refused ret_paren  'fn f(): (i64, i64) { return (5); }\nvar a, b = f();\nsyscall(60, a);\n' "$R2"
refused ret_lit3   'fn f(): (i64, i64) { return (1, 2, 3); }\nvar a, b = f();\nsyscall(60, a);\n' "$R2"
refused ret_lit2   'fn f(): (i64, i64, i64) { return (1, 2); }\nvar a, b, c = f();\nsyscall(60, a);\n' "'f' returns 3 values - return (a, b, c)"
refused ret_tail_one "fn one(x) { return x + 1; }\nfn f(x): (i64, i64) { return one(x); }\nfn main(): i64 { var a, b = f(3); return b; }\nsyscall(60, main());\n" "$R2"
refused ret_tail_fwd "fn f(x): (i64, i64) { return later(x); }\nfn main(): i64 { var a, b = f(3); return b; }\nsyscall(60, main());\nfn later(x) { var y = x * 2; return y; }\n" "$R2"
refused ret_fwd_arity3 "fn g3(x): (i64, i64, i64) { return (x, 1, 2); }\nfn f(x): (i64, i64) { return g3(x); }\nvar a, b = f(3);\nsyscall(60, a);\n" "$R2"
refused ret_fwd_undecl3 "fn h3(a) { return (a, a + 1, a + 2); }\nfn f(): (i64, i64) { return h3(1); }\nvar a, b = f();\nsyscall(60, a);\n" "$R2"
refused ret_fwd_struct "struct P { a; b; }\nfn mk(): P { var p: P; p.a = 1; p.b = 2; return p; }\nfn f(): (i64, i64) { return mk(); }\nvar a, b = f();\nsyscall(60, a);\n" "$R2"
# A struct callee is no multiple values (the B4 rule) even when its own `ret2(1, 2);` fills rax:rdx (6.7.11: its
# `return (1, 2);` is refused, issues/archived/2026-10-08-struct-operator-results.md #4). 6.7.13: that `ret2` is
# refused too, at the producer (D22 A, 2026-10-15) — two mistakes, two lines; the forward's is still R2.
refused ret_fwd_struct_tup "struct P { a; b; }\nfn mk(): P { ret2(1, 2); }\nfn f(): (i64, i64) { return mk(); }\nvar a, b = f();\nsyscall(60, a);\n" "$R2" 2
check "ret_fwd_struct_tup: the producer's own ret2 refusal" yes "$(grep -qF "2:14: a fn returning the struct \`P\` returns that struct — \`ret2\` writes two values" "$T/ret_fwd_struct_tup.err" && echo yes || echo no)"
refused ret_method 'struct P { a; }\nimpl P { fn m(self): (i64, i64) { return self.a; } }\nfn main(): i64 { var p = P { 4 }; var a, b = p.m(); return a; }\nsyscall(60, main());\n' "'P_m' returns 2 values - return (a, b)"
runs ret_fwd      "${G56}fn f(x): (i64, i64) { return g(x); }\nfn main(): i64 { var a, b = f(5); return a * 10 + b; }\nvar r = main(); syscall(60, r);\n" 56
runs ret_fwd_callptr "${G56}fn f(x): (i64, i64) { var fp = &g; return callptr(fp, x); }\nfn main(): i64 { var a, b = f(5); return a * 10 + b; }\nvar r = main(); syscall(60, r);\n" 56
runs ret_fwd_wrap "${G56}fn f(x): (i64, i64) { return (g(x)); }\nfn main(): i64 { var a, b = f(5); return a * 10 + b; }\nvar r = main(); syscall(60, r);\n" 56
runs ret_fwd_undecl "${DM}fn f(): (i64, i64) { return dm(17, 5); }\nfn main(): i64 { var a, b = f(); return a * 10 + b; }\nvar r = main(); syscall(60, r);\n" 32
runs ret_fwd_mixed "fn mix(a) { if (a > 0) { return (a, 1); } return (a, 2, 3); }\nfn f(): (i64, i64) { return mix(4); }\nfn main(): i64 { var a, b = f(); return a * 10 + b; }\nvar r = main(); syscall(60, r);\n" 41
runs ret_recursive 'fn f(x): (i64, i64) { if (x == 0) { return (1, 2); } return f(x - 1); }\nfn main(): i64 { var a, b = f(3); return a * 10 + b; }\nvar r = main(); syscall(60, r);\n' 12
runs ret_fwd_method 'struct B { v; }\nimpl B { fn mk(self, a): (i64, i64) { return (a, self.v); } }\nfn f(x): (i64, i64) { var b = B { 7 }; return b.mk(x); }\nfn main(): i64 { var a, b = f(3); return a * 10 + b; }\nvar r = main(); syscall(60, r);\n' 37
runs ret_fwd_generic 'fn g2<T>(a: T): (i64, i64) { return (a, a + 1); }\nfn f(x): (i64, i64) { return g2<i64>(x); }\nfn main(): i64 { var a, b = f(5); return a * 10 + b; }\nvar r = main(); syscall(60, r);\n' 56
runs ret_tuple    'fn f(): (i64, i64) { var t = (3, 4); return t; }\nfn main(): i64 { var a, b = f(); return a * 10 + b; }\nvar r = main(); syscall(60, r);\n' 34
runs ret_closure  'include "lib/alloc.cyr"\nfn f(x): (i64, i64) { alloc_init(); var c = |y| { return y + 1; }; return (fncall1(c, x), 2); }\nfn main(): i64 { var a, b = f(3); return a * 10 + b; }\nvar r = main(); syscall(60, r);\n' 42
runs ret_inline_one '#inline\nfn one(x) { return x + 1; }\nfn f(x): (i64, i64) { return (one(x), 2); }\nfn main(): i64 { var a, b = f(3); return a * 10 + b; }\nvar r = main(); syscall(60, r);\n' 42
runs ret_inline_two '#inline\nfn two(x) { return (x, 1); }\nfn f(x): (i64, i64, i64) { var a, b = two(x); return (a, b, 3); }\nfn main(): i64 { var a, b, c = f(2); return a * 100 + b * 10 + c; }\nvar r = main(); syscall(60, r);\n' 213
# 6.7.13 (D21 A, 2026-10-15): `ret2(a, b)` writes two values, so in a fn declared with three it is refused as
# `return (a, b);` is (issues/archived/2026-10-13-ret2-in-three-value-fn-leaves-third-register-stale.md; the repro exited
# 88, the seeded r3, on every target). Once in a generic's instances, in sync; `return ret2(..)` once; a declared
# 2-value fn's ret2 and a closure's own ret2 inside a 3-value fn still run.
R3="'f' returns 3 values - return (a, b, c)"
refused ret2_in_3  "${SEED}fn f(x): (i64, i64, i64) { ret2(x, x + 1); }\nfn main(): i64 { var x, y, w = h(); var a, b, c = f(5); return c; }\nvar r = main(); syscall(60, r);\n" "2:28: $R3"
refused ret2_in_3_gen 'fn f<T>(x: T): (i64, i64, i64) { ret2(x, x + 1); }\nfn main(): i64 { var a, b, c = f<i64>(5); var d, e, g = f<i32>(5); return c; }\nsyscall(60, main());\n' "1:34: $R3"
refused ret2_in_3_next 'fn f(x): (i64, i64, i64) { ret2(x, x + 1); syscall(60, nosuch); return (1, 2, 3); }\nfn main(): i64 { var a, b, c = f(5); return c; }\nsyscall(60, main());\n' "1:28: $R3" 2
check "ret2_in_3_next: the next statement's own error" yes "$(grep -qF "1:62: undefined variable 'nosuch'" "$T/ret2_in_3_next.err" && echo yes || echo no)"
refused return_ret2_in_3 "${SEED}fn f(x): (i64, i64, i64) { return ret2(x, x + 1); }\nfn main(): i64 { var x, y, w = h(); var a, b, c = f(5); return c; }\nvar r = main(); syscall(60, r);\n" "2:35: $R3"
runs ret2_in_2    'fn f(x): (i64, i64) { ret2(x, x + 5); }\nfn main(): i64 { var a, b = f(5); return a + b; }\nsyscall(60, main());\n' 15
runs ret2_closure_in_3 'include "lib/fnptr.cyr"\nfn f(x): (i64, i64, i64) { var cl = |y| { ret2(y, y + 1); }; var p, q = fncall1(cl, x); return (p, q, 9); }\nfn main(): i64 { var a, b, c = f(5); return a * 100 + b * 10 + c; }\nsyscall(60, main() & 255);\n' 57
# 6.7.13 (D28 C, 2026-10-15): off the end every value is 0 — the repro verbatim, then three values (5 only when all
# three are 0), a defer whose own call writes the registers (6: it ran, the values stay 0), an f64 pair seeded with
# 7.0 (7), an #inline replay (0; it read 40 + 77); the bodies that never reach the `}` are unchanged.
runs fall_off_2   "${SEED}fn f(x): (i64, i64) { if (x > 0) { return (1, 2); } }\nfn main(): i64 { var x, y, w = h(); var a, b = f(0); return b; }\nvar r = main(); syscall(60, r);\n" 0
runs fall_off_3   "${SEED}fn g(x): (i64, i64, i64) { if (x > 0) { return (1, 2, 3); } }\nfn main(): i64 { var x, y, w = h(); var a, b, c = g(0); if (a == 0 && b == 0 && c == 0) { return 5; } return 9; }\nvar r = main(); syscall(60, r);\n" 5
runs fall_off_defer "${SEED}var G = 0;\nfn f(x): (i64, i64) { defer { var p, q, s = h(); G = q; } if (x > 0) { return (1, 2); } }\nfn main(): i64 { var x, y, w = h(); var a, b = f(0); if (a == 0 && b == 0 && G == 77) { return 6; } return 9; }\nvar r = main(); syscall(60, r);\n" 6
runs fall_off_f64 'fn h2(): (f64, f64) { return (3.5, 7.0); }\nfn f(x): (f64, f64) { if (x > 0) { return (1.5, 2.5); } }\nfn main(): i64 { var x, y = h2(); var a, b = f(0); if (f64_to(a) == 0 && f64_to(b) == 0) { return 7; } return 9; }\nvar r = main(); syscall(60, r);\n' 7
runs fall_off_inline "${SEED}fn k(x) { return x + 40; }\n#inline\nfn f(x): (i64, i64) { k(x); }\nfn main(): i64 { var x, y, w = h(); var a, b = f(0); return a + b; }\nvar r = main(); syscall(60, r);\n" 0
runs fall_off_taken "${SEED}fn f(x): (i64, i64) { if (x > 0) { return (1, 2); } }\nfn main(): i64 { var x, y, w = h(); var a, b = f(1); return a * 10 + b; }\nvar r = main(); syscall(60, r);\n" 12
runs ifelse_both_return "${SEED}fn f(x): (i64, i64) { if (x > 0) { return (1, 2); } else { return (3, 4); } }\nfn main(): i64 { var x, y, w = h(); var a, b = f(0); return a * 10 + b; }\nvar r = main(); syscall(60, r);\n" 34
runs loop_end_declared "${SEED}fn f(x): (i64, i64) { while (1) { if (x > 3) { return (x, 2); } x = x + 1; } }\nfn main(): i64 { var x, y, w = h(); var a, b = f(0); return a * 10 + b; }\nvar r = main(); syscall(60, r);\n" 42
# 6.7.13 (D23 B, 2026-10-15): a fn declared ONE type returning several values is kept — the issue's two programs
# verbatim and its ret2 form; the count pass 1 records (three names, a 3-tuple capture) refused; each value typed by
# the declared type.
SC='fn g2(): i64 { return (1, 2); }\n'
runs sc_one_bind  "${SC}fn main(): i64 { var a = g2(); return a; }\nsyscall(60, main());\n" 1
runs sc_two_bind  "${SC}fn main(): i64 { var a, b = g2(); return a * 10 + b; }\nsyscall(60, main());\n" 12
runs sc_ret2_one_bind 'fn g2(): i64 { ret2(1, 2); }\nfn main(): i64 { var a = g2(); return a; }\nsyscall(60, main());\n' 1
refused sc_count3 "${SC}fn main(): i64 { var a, b, c = g2(); return a; }\nsyscall(60, main());\n" "2:32: multi-value destructure binds 3 names, but 'g2' returns 2 values"
refused sc_f64_count3 'fn g2(x): f64 { return (f64_from(x), f64_from(x + 1)); }\nfn main(): i64 { var a, b, c = g2(1); return 0; }\nsyscall(60, main());\n' "binds 3 names, but 'g2' returns 2 values"
refused sc_tup3   "${SC}fn main(): i64 { var t: (i64, i64, i64) = g2(); return t.0; }\nsyscall(60, main());\n" "cannot capture 'g2' into tuple (i64, i64, i64) - it returns 2 values"
runs sc_f64_two   'fn g2(x): f64 { return (f64_from(x), f64_from(x + 1)); }\nfn main(): i64 { var a, b = g2(1); var s: f64 = a + b; return f64_to(s); }\nsyscall(60, main());\n' 3
refused sc_bool_first 'fn g2(x): bool { return (x, 5); }\nfn main(): i64 { var a, b = g2(1); return a * 10 + b; }\nsyscall(60, main());\n' "cannot return a value that is not a bool from bool fn 'g2'"
runs sc_bool_two  'fn g2(x): bool { return (x > 0, 5); }\nfn main(): i64 { var a, b = g2(1); return a * 10 + b; }\nsyscall(60, main());\n' 15

echo "axis 6 - \`callptr(fp, ..)\` destructures as \`fncallN\` does:"
TWO='fn two(a): (i64, i64) { return (a, a + 1); }\n'
runs cp_repro  'include "lib/fnptr.cyr"\nfn two(a): (i64, i64) { return (a, a + 1); }\nfn main(): i64 {\n    var fp = &two;\n    var a, b = fncall1(fp, 5);\n    var c, d = callptr(fp, 5);\n    return a + b + c + d;\n}\nsyscall(60, main());\n' 22
runs cp_assign "${TWO}fn main(): i64 {\n    var fp = &two;\n    var c = 0;\n    var d = 0;\n    c, d = callptr(fp, 5);\n    return c + d;\n}\nsyscall(60, main());\n" 11
runs cp_for    "${TWO}fn main(): i64 {\n    var fp = &two;\n    var c = 0;\n    var d = 0;\n    var s = 0;\n    for (var i = 0; i < 3; c, d = callptr(fp, i)) { s = s + c + d; i = i + 1; }\n    return s;\n}\nsyscall(60, main());\n" 8
runs cp_zone   "${TWO}var fp = &two;\nvar c, d = callptr(fp, 5);\nsyscall(60, c + d);\n" 11
runs cp_top    "${TWO}var fp = 0;\nfp = &two;\nvar c, d = callptr(fp, 5);\nsyscall(60, c + d);\n" 11
runs cp_three  'include "lib/fnptr.cyr"\nfn three(a): (i64, i64, i64) { return (a, a + 1, a + 2); }\nfn main(): i64 {\n    var fp = &three;\n    var a, b, c = fncall1(fp, 5);\n    var x, y, z = callptr(fp, 5);\n    return a + b + c + x + y + z;\n}\nsyscall(60, main());\n' 36
refused cp_arith "${TWO}fn main(): i64 {\n    var fp = &two;\n    var c, d = callptr(fp, 5) + 1;\n    return c + d;\n}\nsyscall(60, main());\n" "multi-value destructure needs a call on the right-hand side"

echo "axis 7 - \`ret2(a, b)\` is two values to pass 1's count (D42), on every target:"
WP="$T/wine"
WHM="$T/whome"
_wine_down() {
    [ -d "$WP" ] || return 0
    _ws="/tmp/.wine-$(id -u)/server-$(stat -c '%D' "$WP" 2>/dev/null)-$(printf '%x' "$(stat -c '%i' "$WP" 2>/dev/null || echo 0)")"
    WINEPREFIX="$WP" wineserver -k >/dev/null 2>&1 || true
    WINEPREFIX="$WP" wineserver -w >/dev/null 2>&1 || true
    rm -rf "$_ws" || true
}
trap '_wine_down; rm -rf "$T"' EXIT
skips=0
LG7="x86_64 pe"
if command -v qemu-aarch64 > /dev/null 2>&1; then
    if "$CC" < src/main_aarch64.cyr > "$T/x_a64" 2> /dev/null && [ -s "$T/x_a64" ]; then chmod +x "$T/x_a64"; LG7="$LG7 aarch64"
    else check "axis 7: src/main_aarch64.cyr builds" 0 1; fi
else echo "  SKIP axis 7's aarch64 leg — qemu-aarch64 not installed"; skips=$((skips + 1)); fi
if "$CC" < src/main_cx.cyr > "$T/x_cx" 2> /dev/null && [ -s "$T/x_cx" ] && "$CC" < programs/cxvm.cyr > "$T/x_vm" 2> /dev/null && [ -s "$T/x_vm" ]; then
    chmod +x "$T/x_cx" "$T/x_vm"; LG7="$LG7 cx"
else check "axis 7: src/main_cx.cyr and programs/cxvm.cyr build" 0 1; fi
WINE7=0
if command -v wine > /dev/null 2>&1; then WINE7=1
else echo "  SKIP axis 7's PE run leg — wine not installed (the PE refusals still run)"; skips=$((skips + 1)); fi
_cc7() {   # <leg> <name>: $T/<name>.<leg> (+ .err); rc in $rc
    rc=0
    case $1 in
        x86_64)  "$CC" < "$T/$2.cyr" > "$T/$2.$1" 2> "$T/$2.$1.err" || rc=$? ;;
        aarch64) "$T/x_a64" < "$T/$2.cyr" > "$T/$2.$1" 2> "$T/$2.$1.err" || rc=$? ;;
        cx)      "$T/x_cx" < "$T/$2.cyr" > "$T/$2.$1" 2> "$T/$2.$1.err" || rc=$? ;;
        pe)      CYRIUS_TARGET_WIN=1 "$CC" < "$T/$2.cyr" > "$T/$2.$1" 2> "$T/$2.$1.err" || rc=$? ;;
    esac
}
# refused7 <name> <source> <fragment>: refused once on every leg, naming <fragment>, no binary
refused7() {
    rows=$((rows + 1))
    printf '%b' "$2" > "$T/$1.cyr"
    for leg in $LG7; do
        _cc7 "$leg" "$1"
        check "$1 ($leg): exits 1" 1 "$rc"
        check "$1 ($leg): names it" yes "$(grep -qF -- "$3" "$T/$1.$leg.err" && echo yes || echo no)"
        check "$1 ($leg): error lines" 1 "$(grep -c '^error' "$T/$1.$leg.err")"
        check "$1 ($leg): emits no binary" 0 "$(wc -c < "$T/$1.$leg" | tr -d ' ')"
    done
}
# runs7 <name> <source> <exit>: compiles and exits <exit> on every leg
runs7() {
    rows=$((rows + 1))
    printf '%b' "$2" > "$T/$1.cyr"
    for leg in $LG7; do
        _cc7 "$leg" "$1"
        check "$1 ($leg): compiles" 0 "$rc"
        [ "$rc" -eq 0 ] || continue
        chmod +x "$T/$1.$leg"; got=0
        case $leg in
            x86_64)  timeout 30 "$T/$1.$leg" > /dev/null 2>&1 || got=$? ;;
            aarch64) timeout 60 qemu-aarch64 "$T/$1.$leg" > /dev/null 2>&1 || got=$? ;;
            cx)      timeout 60 "$T/x_vm" < "$T/$1.$leg" > /dev/null 2>&1 || got=$? ;;
            pe)      [ "$WINE7" -eq 1 ] || continue
                     mkdir -p "$WHM"; cp "$T/$1.$leg" "$T/$1.exe"
                     (cd "$T" && WINEPREFIX="$WP" HOME="$WHM" XDG_CACHE_HOME="$WHM/.cache" WINEDEBUG=-all \
                         WINEDLLOVERRIDES='winemenubuilder.exe=d;mscoree=d;mshtml=d' timeout 180 wine "./$1.exe" > /dev/null 2>&1) || got=$? ;;
        esac
        check "$1 ($leg): exits $3" "$3" "$got"
    done
}
H88='fn h(): (i64, i64, i64) { return (1, 77, 88); }\n'
G32="multi-value destructure binds 3 names, but 'g2' returns 2 values"
# The issue's repro verbatim, then its table's rows (each seeded: h leaves 88 in the third register).
refused7 r2_repro  "${H88}fn g2() { ret2(1, 2); }\nfn main(): i64 { var x, y, w = h(); var a, b, c = g2(); return c; }\nsyscall(60, main());\n" "3:51: $G32"
refused7 r2_i64    "${H88}fn g2(): i64 { ret2(1, 2); }\nfn main(): i64 { var x, y, w = h(); var a, b, c = g2(); return c; }\nsyscall(60, main());\n" "3:51: $G32"
refused7 r2_ret    "${H88}fn g2(): i64 { return ret2(1, 2); }\nfn main(): i64 { var x, y, w = h(); var a, b, c = g2(); return c; }\nsyscall(60, main());\n" "3:51: $G32"
refused7 r2_tup3   "${H88}fn g2() { ret2(1, 2); }\nfn main(): i64 { var x, y, w = h(); var t: (i64, i64, i64) = g2(); return t.2; }\nsyscall(60, main());\n" "3:62: cannot capture 'g2' into tuple (i64, i64, i64) - it returns 2 values"
refused7 r2_mixed  "${H88}fn g2(x) { if (x > 0) { ret2(1, 2); } else { return (3, 4); } }\nfn main(): i64 { var x, y, w = h(); var a, b, c = g2(1); return c; }\nsyscall(60, main());\n" "3:51: $G32"
refused7 r2_control "${H88}fn g2() { return (1, 2); }\nfn main(): i64 { var x, y, w = h(); var a, b, c = g2(); return c; }\nsyscall(60, main());\n" "3:51: $G32"
refused7 r2_mid    "fn g2(x) { if (x > 0) { ret2(x, 1); } return (x, 2); }\nfn main(): i64 { var a, b, c = g2(1); return a; }\nsyscall(60, main());\n" "$G32"
refused7 r2_elif   "fn g2(x) { if (x > 1) { ret2(x, 1); } elif (x > 0) { return (x, 2); } else { ret2(x, 3); } }\nfn main(): i64 { var a, b, c = g2(1); return a; }\nsyscall(60, main());\n" "$G32"
refused7 r2_ifelse_ret "fn g2(x) { if (x > 0) { return (x, 1); } else { return (x, 2); } }\nfn main(): i64 { var a, b, c = g2(1); return a; }\nsyscall(60, main());\n" "$G32"
refused7 r2_top_decl "fn g2(x) { ret2(x, 1); }\nvar a, b, c = g2(5);\nsyscall(60, a);\n" "2:15: $G32"
refused7 r2_top_late "fn g2(x) { ret2(x, 1); }\nvar z = 0;\nz = 1;\nvar a, b, c = g2(5);\nsyscall(60, a);\n" "4:15: $G32"
refused7 r2_forward "fn main(): i64 { var a, b, c = later(5); return a; }\nsyscall(60, main());\nfn later(x) { ret2(x, 1); }\n" "binds 3 names, but 'later' returns 2 values"
refused7 r2_method "struct P { x; }\nimpl P { fn dm(self) { ret2(self.x, 1); } }\nfn main(): i64 { var p = P { 4 }; var a, b, c = p.dm(); return a; }\nsyscall(60, main());\n" "binds 3 names, but 'P.dm' returns 2 values"
refused7 r2_generic "fn g<T>(a: T) { ret2(a, a + 1); }\nfn main(): i64 { var a, b, c = g<i32>(5); return a; }\nsyscall(60, main());\n" "binds 3 names, but 'g<i32>' returns 2 values"
refused7 r2_reassign "fn g2(x) { ret2(x, 1); }\nfn main(): i64 { var a = 0; var b = 0; var c = 0; a, b, c = g2(5); return a; }\nsyscall(60, main());\n" "$G32"
# Read wherever a `return (a, b);` fn's count is: a struct argument (it faulted: the first value taken as the
# struct's address) and a 3-value fn forwarding it (its third value was stale).
refused7 r2_struct_arg "struct P { a; b; }\nfn take(p: P): i64 { return p.a * 10 + p.b; }\nfn g2(x) { ret2(x, 1); }\nfn main(): i64 { return take(g2(4)); }\nsyscall(60, main());\n" "a multi-value call 'g2' is not a struct 'P' argument"
refused7 r2_fwd3 "fn g2(x) { ret2(x, 1); }\nfn f(x): (i64, i64, i64) { return g2(x); }\nfn main(): i64 { var a, b, c = f(4); return a; }\nsyscall(60, main());\n" "'f' returns 3 values - return (a, b, c)"
# Unchanged: two names, one name + rethi() and the 2-tuple capture (the guide's divmod_old; 123132 % 256),
# a `ret2` inside an expression, a body that can fall off its end (no else), a 2-value forward.
runs7 r2_two "fn divmod_old(a, b) { ret2(a / b, a % b); }\nfn main(): i64 { var q, r = divmod_old(17, 5); var q2 = divmod_old(10, 3); var r2 = rethi(); var t: (i64, i64) = divmod_old(9, 4); return q * 10 + r + q2 * 1000 + r2 * 100 + t.0 * 10000 + t.1 * 100000; }\nsyscall(60, main() % 256);\n" 252
runs7 r2_expr "fn g2() { var z = ret2(1, 2); }\nfn main(): i64 { var a, b, c = g2(); return a * 10 + b; }\nsyscall(60, main());\n" 12
runs7 r2_noelse "fn g2(x) { if (x > 0) { ret2(x, 1); } }\nfn main(): i64 { var a, b, c = g2(1); return a * 10 + b; }\nsyscall(60, main());\n" 11
runs7 r2_fwd2 "fn g2(x) { ret2(x, 1); }\nfn f(x): (i64, i64) { return g2(x); }\nfn main(): i64 { var a, b = f(4); return a * 10 + b; }\nsyscall(60, main());\n" 41

echo "axis 8 - parentheses around the whole call are transparent to the destructure (D45), on every target:"
TWO8='fn two(x): (i64, i64) { return (x, x + 1); }\n'
NC8="multi-value destructure needs a call on the right-hand side"
# The issue's program verbatim (a \`: stack\` pair and a declared pair, each wrapped: 17 + 34 - 10 = 41).
runs7 pw_repro "enum Res: stack { ROk(v); RErr(e); }\nfn f(x) { return ROk(x); }\nfn two(x): (i64, i64) { return (x, x + 1); }\nfn t1(): i64 { var a, b = (f(7)); return a * 10 + b; }\nfn t2(): i64 { var c, d = (two(3)); return c * 10 + d; }\nsyscall(60, t1() + t2());\n" 41
runs7 pw_double "${TWO8}fn t(): i64 { var c, d = ((two(3))); return c * 10 + d; }\nsyscall(60, t());\n" 34
runs7 pw_assign "${TWO8}fn t(): i64 { var c = 0; var d = 0; c, d = (two(3)); return c * 10 + d; }\nsyscall(60, t());\n" 34
runs7 pw_for "${TWO8}fn t(): i64 { var c = 0; var d = 0; for (var i = 0; i < 2; c, d = (two(i))) { i = i + 1; } return c * 10 + d; }\nsyscall(60, t());\n" 23
runs7 pw_zone "${TWO8}var a, b = (two(3));\nsyscall(60, a * 10 + b);\n" 34
runs7 pw_top "${TWO8}syscall(1, 1, \"\", 0);\nvar a, b = ((two(3)));\nsyscall(60, a * 10 + b);\n" 34
runs7 pw_callptr "${TWO8}fn t(): i64 { var fp = &two; var a, b = (callptr(fp, 5)); return a * 10 + b; }\nsyscall(60, t());\n" 56
runs7 pw_method "struct B { v; }\nimpl B { fn mk(self, a): (i64, i64) { return (a, a + self.v); } }\nfn g<T>(a: T): (i64, i64) { return (a, a + 1); }\nfn t(): i64 { var b: B; b.v = 3; var c, d = (b.mk(4)); var e, f = (g<i64>(5)); return c * 10 + d + e * 100 + f * 1000; }\nsyscall(60, t() % 256);\n" 147
runs7 pw_f64 "fn ff(x): (f64, f64) { return (1.5, 2.25); }\nfn t(): i64 { var a, b = (ff(1)); var s: f64 = a + b; if (s == 3.75) { return 7; } return 1; }\nsyscall(60, t());\n" 7
runs7 pw_nested "include \"lib/fnptr.cyr\"\n${TWO8}fn t(): i64 { var a, b = (two(fncall0(|| { var c, d = (two(1)); return c * 10 + d; }))); return a + b; }\nsyscall(60, t());\n" 25
refused7 pw_operand "enum Res: stack { ROk(v); RErr(e); }\nfn f(x) { return ROk(x); }\nfn t(): i64 { var a, b = (f(7)) + 1; return a * 10 + b; }\nsyscall(60, t());\n" "3:26: $NC8"
refused7 pw_inner_op "${TWO8}fn t(): i64 { var a, b = (two(7) + 1); return a * 10 + b; }\nsyscall(60, t());\n" "2:26: $NC8"
refused7 pw_zone_op "${TWO8}var a, b = (two(7)) + 1;\nsyscall(60, a);\n" "2:12: $NC8"
refused7 pw_arity3 "fn three(x): (i64, i64, i64) { return (x, x, x); }\nfn t(): i64 { var a, b = (three(7)); return a * 10 + b; }\nsyscall(60, t());\n" "2:27: multi-value destructure count does not match the fn's declared return arity"
refused7 pw_count3 "fn dm(a, b) { return (a / b, a % b); }\nfn t(): i64 { var a, b, c = (dm(7, 2)); return a; }\nsyscall(60, t());\n" "2:30: multi-value destructure binds 3 names, but 'dm' returns 2 values"
refused7 pw_one "fn one(x) { return x; }\nfn t(): i64 { var a, b = ((one(7))); return a; }\nsyscall(60, t());\n" "binds 2 names, but 'one' returns 1 value"
refused7 pw_zone_arity "fn three(x): (i64, i64, i64) { return (x, x, x); }\nvar a, b = (three(7));\nsyscall(60, a);\n" "2:13: multi-value destructure count does not match the fn's declared return arity"
refused7 pw_masg_arity "fn three(x): (i64, i64, i64) { return (x, x, x); }\nfn t(): i64 { var a = 0; var b = 0; a, b = (three(1)); return a; }\nsyscall(60, t());\n" "multi-value destructure count does not match the fn's declared return arity"
refused7 pw_masg_struct "struct P { a; b; c; }\nfn mkp(): P { var p: P; p.a = 5; return p; }\nfn t(): i64 { var a = 0; var b = 0; a, b = (mkp()); return a; }\nsyscall(60, t());\n" "cannot re-assign from 'mkp' - it returns struct 'P', not multiple values"

if [ "$rows" -lt 150 ]; then echo "FAIL: destructure_one_value_refused: only $rows rows ran (floor 150)"; exit 1; fi
if [ "$fails" -ne 0 ]; then echo "FAIL: destructure_one_value_refused: $fails check(s) failed"; exit 1; fi
if [ "$skips" -gt 0 ]; then echo "SKIP: destructure_one_value_refused - $skips leg(s) of axis 7 could not run; every row that ran passed (exit 77: a SKIP, not a PASS)"; exit 77; fi
echo "PASS: destructure_one_value_refused ($rows rows)"
exit 0

#!/bin/sh
# 6.6.8 — an INT-left arithmetic op with an f64 right operand WARNS (kind 2 of
# _FLT_TYPE_WARN, src/frontend/parse_expr.cyr).
#
# ⛔ THE DEFECT. Binary-op typing is left-operand driven. An f64 LEFT operand routes to the
# SSE/FP emitters, and v6.4.56's kind-1 warning catches an f64-left op with a non-f64 right.
# The mirror case had nothing: `0 - 1.5` is an INTEGER subtraction of 1.5's bit pattern
# (it evaluates to -3.0), `2 * x` with `x: f64` is an integer multiply of x's bits (+inf for
# x = 1.5) and `1 - x` is garbage — all silent. docs/guides/faq.md even prescribed `(0 - N)`
# for a negative literal, which is exactly this trap for a float N.
#
# WARN, not an error or a promotion: the same ADR-002 posture as kind 1 (the i64-boxed float
# idiom is legal, and a promotion would change what existing code computes).
#
# No .tcyr can see a warning (it does not change the exit code) — hence a gate.
#   axis 1  every int-left op (+ - * /) with an f64 right operand warns, once, as kind 2
#   axis 2  ANTI-FALSE-POSITIVE: int/int, f64/f64, f64-left mixes (kind 1), folded literals
#           and unary minus on an f64 do NOT raise kind 2
#   axis 3  kind 1 still fires (the extension did not replace it)
#   axis 4  CYRIUS_TYPE_CHECK=0 silences kind 2 like every other type-check warning
#   axis 5  (6.6.10) an f64 struct/union FIELD is an f64 operand: no false positive on either
#           side, and `p.x + 1` is a kind-1 mix. Red on 6.6.9 (2 kind-1, 2 kind-2, then 0).
#   axis 6  (6.6.10) a float BUILTIN's result is an f64 operand (option D): `f64_add(u, v) * 2.0`
#           and `2.0 * f64_add(u, v)` are clean, `2 * f64_add(u, u)` is kind 2 (once, also
#           nested under an outer `+`), `f64_add(u, u) * 3` kind 1. Red on 6.6.9.
#   axis 7  (6.6.10) kind 3: unary minus on an UNTYPED variable initialised from a float —
#           a local, a copy of one, ±0, a negative literal, a float builtin, a global, a
#           parenthesised one — warns once each; an integer, a typed f64, a parameter do not,
#           and a closure's own declarations leave the enclosing fn's flags as they were;
#           a later fn's parameter that reuses a flagged slot 0 (neg2 after clos) does not warn.
#   axis 8  (6.6.10) kind 4: an integer CONSTANT stored into an f64 / f32 slot (declaration,
#           assignment, field store, struct literal, global) warns once each; 0, an IEEE bit
#           pattern in hex (>= 2^52), a float literal and a runtime value do not.
#   axis 9  CYRIUS_TYPE_CHECK=0 silences kinds 3 and 4.
#   axis 10 (6.6.11) kind 5: an f32 `+ - * /` whose right operand is not f32 (an f64 literal, an
#           integer) warns once each — EMIT_F32_BINOP takes its LOW 32 BITS, so `x * 2.0` was 0,
#           silently; f32/f32, an f32_from(..) right and a typed f32 field are clean, and
#           CYRIUS_TYPE_CHECK=0 silences it. Red on 6.6.10 (0 of 9).
#   axis 11 (6.6.11) compound assignment checks its right operand like `x = x op y`: `t += 1` on
#           an f64 local, `G -= 2` on an f64 global and `x += 1` in a for step warn kind 1,
#           `h *= 2.0` on an f32 kind 5; `+= 1.0`, `-= f64_sqrt(u)`, `+= f32_from(..)` and `%=`
#           do not. Red on 6.6.10 (0 of 3 kind 1, 0 of 1 kind 5).
#   axis 12 (6.6.11) a plain assignment RE-JUDGES an untyped variable's kind-3 flag: `g = 0;
#           g = 1.5; -g` warns and `h = 1.5; h = 7; -h` does not, for locals and globals; a
#           compound assignment keeps the flag, even when a closure in its right operand
#           assigns a float to one of its own variables; a plain for STEP (`g = 1.5`, `G4 = 7`)
#           re-judges like the statement. Red on 6.6.10 (3 warnings, two on the wrong lines).
#   axis 13 (6.6.11) `var t = p.y;` / `var u = y;` (a declared f64 field / local) are typed, so
#           `-t` / `-u` are float negations and draw no kind 3; `var c = 1.5; -c` still does.
#           Red on 6.6.10 (3 warnings, want 1).
#   axis 14 (6.7.7) kind 2 for a compound assignment: `x += 1.5` on an INTEGER place is `x = x + 1.5`
#           and warns as it does — a local, a global, a field (word and i32), `*p`, `a[i]`, `s.len`, a
#           `*T` (also with a builtin result, read before the pointer step emits) and a classic-for
#           step, once each; `f += 1.5` on an f64 local / global / field, `x += 1`, `x %= 1.5` (as
#           `x % 1.5` is silent), an f32 right operand and an untyped float right operand do not, and
#           CYRIUS_TYPE_CHECK=0 silences it. Red on 6.7.6 (0 of 12).
# Mutation-proven: with the four `_INT_F64_MIX` calls removed, axis 1 reads 0 of 4 and fails.
# (6.6.10) with PARSE_INTRIN's `_FBR_MARK` call removed axis 6 fails; with the unary-minus
# `_FLT_TYPE_WARN(S, 3)` removed, or _cl_restore_locals' flag copy removed, axis 7 fails; with SFLC's `_lfi_clear` call removed
# axis 7 reads 9 (neg2's `-a` inherits clos()'s slot-0 flag) and fails; with `_IFS_CHECK`
# returning early axis 8 fails.
# (6.6.11) with the four `_FLT_TYPE_WARN(S, 5)` calls in the f32 arms removed axis 10 fails;
# with _asg_compound_float's two checks removed axis 11 fails; with `_asg_rejudge` returning
# early axis 12 fails; with the for step's two `_asg_rejudge` calls removed axis 12's step
# program fails (it misses -g / -G3 and flags -h / -G4); with `_decl_float_copy` returning 0
# axis 13 fails (the SLTYPE stamp itself is pinned by tests/tcyr/crossos/f64_struct_fields.tcyr).
# (6.7.7) with _asg_compound_op's `_FLT_TYPE_WARN(S, 2)` removed axis 14 reads 0 and fails; with its
# `rt` read moved after EPTR_SCALE the `q += f64_sqrt(u)` row is missed and axis 14 fails.
#   axis 15 (6.7.11) kind 4 for an ARGUMENT: an integer constant passed to an `f64` / `f32` parameter
#           warns once at its line — a call, a tail call, an f32 parameter, a method, the #inline
#           replay, a forward call (pass 1's parameter class), an operator fn's right operand (+ and
#           -), a negated literal, an enum constant, a named argument; 0, a hex IEEE pattern, a float
#           literal, a runtime value, `(3)`, `3 + 1` and an untyped parameter do not; the filed repro
#           (issues/archived/2026-10-09-int-argument-to-f64-param-silent.md) warns at lines 11 15 16 17 and
#           still exits 15. Mutations (measured): the fix reverted -> axis 15 reads 0 warnings and
#           fails; pass 1 without the f64 class (`_bx_pscan`) -> line 18 (the forward call) missed;
#           `_bx_op_rhs` without the f64 check -> line 19 reads 4; the f32 argument arm without
#           `_IFS_CHECK` -> line 15 and the repro's line 16 missed.
#   axis 16 (6.7.11) ONE integer + f64 mix warns ONCE: kind 2 leaves the result f64-typed (ADR-002), so an
#           enclosing integer operator warned again for the same mix — `x = x + (x + 1.5)` (the filed repro,
#           issues/archived/2026-10-08-int-f64-mix-warns-twice-in-a-chain.md) and `2 * (x + 1.5)` twice, `x += x + 1.5`
#           twice at one column, `x - (x * (x + 1.5))` three times. Now once each; two mixes still warn twice
#           (`(x + 1.5) + (x + 2.5)`), and `x + 1.5 + 2` still adds its kind 1 for the `+ 2`. The binary is
#           byte-identical to the CYRIUS_TYPE_CHECK=0 one (diagnostic only). Mutations (2026-10-14): never
#           stamping `_ifm_cp` -> every one-mix row reads 2 or 3 (RED); `_ifm_warn` stamping only when it
#           warns -> `k` and `cc` read 2 (RED); `_asg_compound_op` without its `_ifm_at` test -> `c` and `cc`
#           read 2 (RED).
#   axis 17 (6.7.13) a comparison, an `&&` / `||` link and `& | ^ % << >> >>>` (D12 (a), 2026-10-15) with an f64
#           right operand give an integer (`_int_resb`, `_int_rest`): `(n < x) * 3` is 3 with only the kind-0
#           warning (the repro, verbatim: 0 and a false kind-1 before); `n + x` keeps kind 2 (D41). Mutations
#           (2026-10-16, a scratch tree each): `_int_resb` as `_int_res` -> RED the repro and every row but
#           `add` (exit 0 / wrong, kind 1); `_int_rest` always `_int_res` -> RED mod shl shr sar only.
#   axis 18 (6.7.13) `var c = f() < 1.0;` with a `: f64` leading call is an integer binding (`_var_rhs_post`): the
#           repro verbatim exits 1 (3 before: `-c` flipped the sign bit), `0 - c` draws no kind 2, `var x = f() *
#           2.0;` keeps its f64. The fix reverted (a scratch tree): RED the repro (3), `sub` / `and` (kind 2: 1).
set -eu
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "FAIL: f64_int_mix_warn: no build/cycc"; exit 1; }
cd "$ROOT"
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: f64_int_mix_warn: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT

K2="integer arithmetic with an f64 right operand"
K1="f64 arithmetic with a non-f64 right operand"
fail=0
bad() { echo "  FAIL: f64_int_mix_warn: $*"; fail=1; }

# Compile $1 (a source file); stderr to $W/e. The binary is discarded.
build() { "$CC" < "$1" > "$W/o" 2> "$W/e" || true; }
count() { grep -c "$1" "$W/e" || true; }

# --- axis 1: each int-left op with an f64 right operand warns exactly once ---
for spec in 'sub|var a = 0 - 1.5;' 'mul|var a = 2 * one;' 'div|var a = 3 / one;' 'add|var a = 4 + one;'; do
    id=${spec%%|*}; stmt=${spec#*|}
    printf 'include "lib/syscalls.cyr"\nfn main(): i64 {\n    var one: f64 = 1.5;\n    %s\n    return 0;\n}\nvar r = main();\nsyscall(60, r);\n' "$stmt" > "$W/a1_$id.cyr"
    build "$W/a1_$id.cyr"
    n=$(count "$K2")
    [ "$n" = 1 ] || bad "axis 1 ($id: '$stmt'): kind-2 warning count $n, want 1"
done

# --- axis 2: no kind-2 warning where the operation is not an int-left/f64-right mix ---
cat > "$W/a2.cyr" <<'EOF'
include "lib/syscalls.cyr"
fn main(): i64 {
    var one: f64 = 1.5;
    var two: f64 = 2.0;
    var i = 3;
    var j = 4;
    var a = i + j;
    var b = i * 8 - j / 2;
    var c: f64 = one + two;
    var d: f64 = one * two - two / one;
    var e: f64 = 0.0 - 1.5;
    var f: f64 = -one;
    var g: f64 = -1.5;
    var h: f64 = two * -one;
    var k = 2 + 3 * 4;
    return a + b + k + f64_to(c) + f64_to(d) + f64_to(e) + f64_to(f) + f64_to(g) + f64_to(h);
}
var r = main();
syscall(60, r & 255);
EOF
build "$W/a2.cyr"
n=$(count "$K2"); [ "$n" = 0 ] || { bad "axis 2: $n kind-2 warning(s) on code with no int-left/f64-right mix"; sed -n 1,5p "$W/e"; }
n=$(count "$K1"); [ "$n" = 0 ] || { bad "axis 2: $n kind-1 warning(s) on code with no f64-left mix"; sed -n 1,5p "$W/e"; }

# --- axis 3: kind 1 is still live ---
printf 'include "lib/syscalls.cyr"\nfn main(): i64 {\n    var one: f64 = 1.5;\n    var a: f64 = one + 1;\n    return 0;\n}\nvar r = main();\nsyscall(60, r);\n' > "$W/a3.cyr"
build "$W/a3.cyr"
n=$(count "$K1"); [ "$n" = 1 ] || bad "axis 3: kind-1 warning count $n on 'one + 1', want 1"
n=$(count "$K2"); [ "$n" = 0 ] || bad "axis 3: kind 2 fired on an f64-LEFT mix"

# --- axis 4: CYRIUS_TYPE_CHECK=0 silences it ---
CYRIUS_TYPE_CHECK=0 "$CC" < "$W/a1_sub.cyr" > "$W/o" 2> "$W/e" || true
n=$(count "$K2"); [ "$n" = 0 ] || bad "axis 4: CYRIUS_TYPE_CHECK=0 still printed $n kind-2 warning(s)"

# --- axis 5 (6.6.10): an f64 STRUCT FIELD is an f64 operand, on either side ---
# Before 6.6.10 a field loaded untyped, so `2.0 * p.x` and `t + p.y` (correct code) drew a
# false kind-1 warning and `p.x * 2.0` / `p.x + t` a kind-2 one while computing garbage.
# The last row is the converse: a field LEFT with an integer right is a real kind-1 mix.
cat > "$W/a5.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct P { x: f64; y: f64; }
union U { f: f64; b: i64; }
fn main(): i64 {
    var p: P;
    p.x = 1.5; p.y = 2.0;
    var t: f64 = 4.0;
    var u: U;
    u.f = 0.5;
    var a: f64 = 2.0 * p.x;
    var b: f64 = t + p.y;
    var c: f64 = p.x * 2.0;
    var d: f64 = p.x + t;
    var e: f64 = p.x + p.y - p.x / p.y;
    var f: f64 = -p.x;
    var g: f64 = u.f + u.f;
    return f64_to(a) + f64_to(b) + f64_to(c) + f64_to(d) + f64_to(e) + f64_to(f) + f64_to(g);
}
var r = main();
syscall(60, r & 255);
EOF
build "$W/a5.cyr"
n=$(count "$K2"); [ "$n" = 0 ] || { bad "axis 5: $n kind-2 warning(s) on f64-field arithmetic"; sed -n 1,5p "$W/e"; }
n=$(count "$K1"); [ "$n" = 0 ] || { bad "axis 5: $n kind-1 warning(s) on f64-field arithmetic"; sed -n 1,5p "$W/e"; }
printf 'include "lib/syscalls.cyr"\nstruct P { x: f64; }\nfn main(): i64 {\n    var p: P;\n    p.x = 1.5;\n    var a: f64 = p.x + 1;\n    return 0;\n}\nvar r = main();\nsyscall(60, r);\n' > "$W/a5b.cyr"
build "$W/a5b.cyr"
n=$(count "$K1"); [ "$n" = 1 ] || bad "axis 5: kind-1 warning count $n on 'p.x + 1' (an f64 field left), want 1"

# --- axis 6 (6.6.10): a float builtin's RESULT is an f64 operand (option D) ---
K3="unary minus on an untyped variable holding a float"
K4="an integer stored into an f64/f32 slot"
cat > "$W/a6.cyr" <<'EOF'
include "lib/syscalls.cyr"
fn main(): i64 {
    var u = 4.0;
    var v = 2.0;
    var p: f64 = 3.0;
    var a: f64 = f64_add(u, v) * 2.0;
    var b: f64 = 2.0 * f64_add(u, v);
    var c: f64 = p + f64_mul(u, v);
    var d: f64 = -f64_add(u, v) * 2.0;
    var e: f64 = (f64_add(u, v)) - 1.0;
    return f64_to(a) + f64_to(b) + f64_to(c) + f64_to(d) + f64_to(e);
}
var r = main();
syscall(60, r & 255);
EOF
build "$W/a6.cyr"
n=$(count "$K2"); [ "$n" = 0 ] || { bad "axis 6: $n kind-2 warning(s) on builtin-result float arithmetic"; sed -n 1,5p "$W/e"; }
n=$(count "$K1"); [ "$n" = 0 ] || { bad "axis 6: $n kind-1 warning(s) on builtin-result float arithmetic"; sed -n 1,5p "$W/e"; }
printf 'include "lib/syscalls.cyr"\nfn main(): i64 {\n    var u = 4.0;\n    var a = 2 * f64_add(u, u);\n    var b = 1 + 2 * f64_add(u, u);\n    return a + b;\n}\nvar r = main();\nsyscall(60, r & 255);\n' > "$W/a6b.cyr"
build "$W/a6b.cyr"
n=$(count "$K2"); [ "$n" = 2 ] || bad "axis 6: kind-2 count $n on '2 * f64_add(u, u)' and '1 + 2 * f64_add(u, u)', want 2 (one each)"
printf 'include "lib/syscalls.cyr"\nfn main(): i64 {\n    var u = 4.0;\n    var a: f64 = f64_add(u, u) * 3;\n    return 0;\n}\nvar r = main();\nsyscall(60, r);\n' > "$W/a6c.cyr"
build "$W/a6c.cyr"
n=$(count "$K1"); [ "$n" = 1 ] || bad "axis 6: kind-1 count $n on 'f64_add(u, u) * 3' (a builtin result left, an int right), want 1"

# --- axis 7 (6.6.10): kind 3, unary minus on an untyped float-initialised variable ---
cat > "$W/a7.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/fnptr.cyr"
var G = 1.5;
var GT: f64 = 1.5;
var GI = 3;
fn neg(a): i64 { return -a; }
# The closure's own slots start again at 0 (its param clears slot 0's flag as it is handed
# out); the enclosing fn's flags must come back with the rest of its local table.
fn clos(): i64 {
    var c = 1.5;
    var n = 3;
    var f = |x| { var w = 7; return x + w; };
    var a = -n;
    var b = -c;
    return a + b + fncall1(f, 1);
}
# Compiled AFTER clos(), whose slot 0 (`c`) is flagged: the parameter handed slot 0 here
# must not inherit that flag (SFLC clears it as it hands the slot out).
fn neg2(a): i64 { return -a; }
fn main(): i64 {
    var c = 1.5;
    var r1 = -c;
    var e = c;
    var r2 = -e;
    var z = 0.0;
    var r3 = -z;
    var n = -2.5;
    var r4 = -n;
    var x = f64_add(c, c);
    var r5 = -x;
    var r6 = -G;
    var r7 = -(c);
    var i = 5;
    var q: f64 = 2.0;
    var k1 = -i;
    var k2 = -GT;
    var k3 = -GI;
    var k4 = -q;
    return r1 + r2 + r3 + r4 + r5 + r6 + r7 + k1 + k3 + neg(1) + clos() + neg2(1);
}
var r = main();
syscall(60, r & 255);
EOF
build "$W/a7.cyr"
n=$(count "$K3"); [ "$n" = 8 ] || { bad "axis 7: kind-3 warning count $n, want 8 (-c -e -z -n -x -G -(c), and clos()'s -c across a closure; not -i -GT -GI -q, clos()'s -n or a parameter, including neg2's which reuses clos()'s flagged slot 0)"; sed -n 1,12p "$W/e"; }

# --- axis 8 (6.6.10): kind 4, an integer constant stored into an f64 / f32 slot ---
cat > "$W/a8.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct P { x: f64; y: f64; }
struct Q { a: f32; n; }
enum E { ONE = 1, BIG = 0x3FF0000000000000 }
var G: f64 = 1;
var G0: f64 = 0;
var GH: f64 = 0x3FF0000000000000;
fn main(): i64 {
    var t: f64 = 1;
    var tn: f64 = -1;
    var te: f64 = ONE;
    var s: f32 = 3;
    t = 2;
    G = 3;
    var p: P;
    p.x = 1;
    var q: Q;
    q.a = 2;
    var pp = P { 1, 2.0 };
    var pn = P { x: 1.0, y: 5 };
    var t0: f64 = 0;
    var th: f64 = 0x3FF0000000000000;
    var tb: f64 = BIG;
    var tf: f64 = 1.5;
    var i = 1;
    var ti: f64 = i;
    t = 2.0;
    p.y = 0;
    q.n = 2;
    var pf = P { 1.0, 2.0 };
    return 0;
}
var r = main();
syscall(60, r);
EOF
build "$W/a8.cyr"
n=$(count "$K4"); [ "$n" = 11 ] || { bad "axis 8: kind-4 warning count $n, want 11 (G, t, tn, te, s, t=2, G=3, p.x, q.a, P{1,..}, P{..y:5})"; sed -n 1,14p "$W/e"; }

# --- axis 9: CYRIUS_TYPE_CHECK=0 silences kinds 3 and 4 ---
CYRIUS_TYPE_CHECK=0 "$CC" < "$W/a7.cyr" > "$W/o" 2> "$W/e" || true
n=$(count "$K3"); [ "$n" = 0 ] || bad "axis 9: CYRIUS_TYPE_CHECK=0 still printed $n kind-3 warning(s)"
CYRIUS_TYPE_CHECK=0 "$CC" < "$W/a8.cyr" > "$W/o" 2> "$W/e" || true
n=$(count "$K4"); [ "$n" = 0 ] || bad "axis 9: CYRIUS_TYPE_CHECK=0 still printed $n kind-4 warning(s)"

# --- axis 10 (6.6.11): kind 5, an f32 arm with a non-f32 right operand ---
K5="f32 arithmetic with a non-f32 right operand"
cat > "$W/a10.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct F { a: f32; }
fn main(): i64 {
    var u = 2.5;
    var x: f32 = f32_from(2.5);
    var y: f32 = f32_from(0.5);
    var f: F;
    f.a = f32_from(1.0);
    var w1 = f32_from(u) + 1.0;
    var w2 = x + 1.0;
    var w3 = x - 1;
    var w4 = x * 2.0;
    var w5 = x / 2;
    var w6 = x + 1;
    var w7 = x - 0.5;
    var w8 = x * 3;
    var w9 = x / 4.0;
    var c1 = x + y;
    var c2 = x - f32_from(1.0);
    var c3 = x * f.a;
    var c4 = x / y + y * x - y;
    var c5 = f.a + x;
    return 0;
}
var r = main();
syscall(60, r);
EOF
build "$W/a10.cyr"
n=$(count "$K5"); [ "$n" = 9 ] || { bad "axis 10: kind-5 warning count $n, want 9 (w1..w9; not c1..c5)"; sed -n 1,12p "$W/e"; }
if grep "$K5" "$W/e" | grep -q ">:1[89]:\|>:2[0-2]:"; then bad "axis 10: kind 5 fired on an f32/f32 row (c1..c5)"; fi
n=$(count "$K1"); [ "$n" = 0 ] || bad "axis 10: $n kind-1 warning(s) on f32 arithmetic (the f32 arms are kind 5)"
CYRIUS_TYPE_CHECK=0 "$CC" < "$W/a10.cyr" > "$W/o" 2> "$W/e" || true
n=$(count "$K5"); [ "$n" = 0 ] || bad "axis 10: CYRIUS_TYPE_CHECK=0 still printed $n kind-5 warning(s)"

# --- axis 11 (6.6.11): compound assignment checks its right operand ---
cat > "$W/a11.cyr" <<'EOF'
include "lib/syscalls.cyr"
var G: f64 = 1.5;
fn main(): i64 {
    var t: f64 = 1.5;
    var h: f32 = f32_from(1.5);
    var u = 4.0;
    t += 1;
    G -= 2;
    h *= 2.0;
    for (var x: f64 = 0.0; x < 3.0; x += 1) { }
    t += 1.0;
    t -= f64_sqrt(u);
    G *= t;
    h += f32_from(1.0);
    h /= h;
    var i = 7;
    i %= 3;
    for (var z: f64 = 0.0; z < 1.0; z += 0.25) { }
    return i;
}
var r = main();
syscall(60, r);
EOF
build "$W/a11.cyr"
n=$(count "$K1"); [ "$n" = 3 ] || { bad "axis 11: kind-1 warning count $n, want 3 (t += 1, G -= 2, the step x += 1)"; sed -n 1,8p "$W/e"; }
n=$(count "$K5"); [ "$n" = 1 ] || { bad "axis 11: kind-5 warning count $n, want 1 (h *= 2.0)"; sed -n 1,8p "$W/e"; }
n=$(count "$K4"); [ "$n" = 0 ] || bad "axis 11: kind 4 fired on a compound assignment ($n); kind 1 is its warning"

# --- axis 12 (6.6.11): a plain assignment re-judges the kind-3 flag ---
cat > "$W/a12.cyr" <<'EOF'
include "lib/syscalls.cyr"
include "lib/fnptr.cyr"
var G1 = 0;
var G2 = 1.5;
fn main(): i64 {
    var g = 0;
    g = 1.5;
    var a = -g;
    var h = 1.5;
    h = 7;
    var b = -h;
    G1 = 1.5;
    var c = -G1;
    G2 = 7;
    var d = -G2;
    var k = 1.5;
    k += 1;
    var e = -k;
    var m = 1;
    m += fncall1(|v| { var q = 0; q = 1.5; return v; }, 2);
    var f = -m;
    return a + b + c + d + e + f;
}
var r = main();
syscall(60, r & 255);
EOF
build "$W/a12.cyr"
n=$(count "$K3"); [ "$n" = 3 ] || { bad "axis 12: kind-3 warning count $n, want 3 (-g, -G1, -k; not -h, -G2, -m)"; sed -n 1,8p "$W/e"; }
for want in 8 13 18; do
    grep "$K3" "$W/e" | grep -q ">:$want:" || bad "axis 12: no kind-3 warning at line $want"
done
# the for-step replay re-judges too (parse_ctrl.cyr's plain-step `_asg_rejudge` calls), for a
# local and a global: a float step flags `-g` / `-G3`, an int step clears `-h` / `-G4`.
cat > "$W/a12s.cyr" <<'EOF'
include "lib/syscalls.cyr"
var G3 = 0;
var G4 = 1.5;
fn main(): i64 {
    var g = 0;
    var h = 1.5;
    var i = 0;
    for (i = 0; i < 1; g = 1.5) { i = 1; }
    var a = -g;
    for (i = 0; i < 1; h = 7) { i = 1; }
    var b = -h;
    for (i = 0; i < 1; G3 = 1.5) { i = 1; }
    var c = -G3;
    for (i = 0; i < 1; G4 = 7) { i = 1; }
    var d = -G4;
    return a + b + c + d;
}
var r = main();
syscall(60, r & 255);
EOF
build "$W/a12s.cyr"
n=$(count "$K3"); [ "$n" = 2 ] || { bad "axis 12 (for step): kind-3 warning count $n, want 2 (-g, -G3; not -h, -G4)"; sed -n 1,8p "$W/e"; }
for want in 9 13; do
    grep "$K3" "$W/e" | grep -q ">:$want:" || bad "axis 12 (for step): no kind-3 warning at line $want"
done

# --- axis 13 (6.6.11): a copy of a declared f64 value is typed ---
cat > "$W/a13.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct P { x: f64; y: f64; }
fn main(): i64 {
    var p: P;
    p.y = 2.5;
    var y: f64 = 1.5;
    var t = p.y;
    var u = y;
    var c = 1.5;
    var a = -t;
    var b = -u;
    var d = -c;
    return a + b + d;
}
var r = main();
syscall(60, r & 255);
EOF
build "$W/a13.cyr"
n=$(count "$K3"); [ "$n" = 1 ] || { bad "axis 13: kind-3 warning count $n, want 1 (-c only; t and u are typed f64)"; sed -n 1,8p "$W/e"; }

# --- axis 14 (6.7.7): a compound assignment on an INTEGER place warns kind 2 ---
# Lines 15-26 warn (one each); lines 27-35 do not.
cat > "$W/a14.cyr" <<'EOF'
include "lib/syscalls.cyr"
struct H { n; m: i32; f: f64; }
var G = 3;
var GF: f64 = 1.0;
fn main(): i64 {
    var one: f64 = 1.5;
    var u = 4.0;
    var x = 1;
    var h: H;
    h.n = 1; h.m = 2; h.f = 0.5;
    var a: i64[4];
    var p = &x;
    var s: [i64] = 0;
    var q: *i64 = &x;
    x += 1.5;
    x -= one;
    x *= 2.0;
    x /= f64_sqrt(u);
    G += 1.5;
    h.n += 1.5;
    h.m -= one;
    *p += 1.5;
    a[1] += 1.5;
    s.len += 1.5;
    q += f64_sqrt(u);
    for (var i = 0; i < 3; i += 1.5) { }
    one += 1.5;
    GF -= 1.5;
    h.f *= 2.0;
    x += 1;
    x %= 1.5;
    x += u;
    var w: f32 = f32_from(1.5);
    x += w;
    x &= 7;
    return 0;
}
var r = main();
syscall(60, r);
EOF
build "$W/a14.cyr"
n=$(count "$K2"); [ "$n" = 12 ] || { bad "axis 14: kind-2 warning count $n, want 12 (lines 15-26)"; sed -n 1,16p "$W/e"; }
for want in 15 16 17 18 19 20 21 22 23 24 25 26; do
    grep "$K2" "$W/e" | grep -q ">:$want:" || bad "axis 14: no kind-2 warning at line $want"
done
if grep "$K2" "$W/e" | grep -q ">:2[7-9]:\|>:3[0-5]:"; then bad "axis 14: kind 2 fired on a no-warning row (lines 27-35)"; fi
n=$(count "$K1"); [ "$n" = 0 ] || { bad "axis 14: $n kind-1 warning(s); the f64 destinations take float right operands"; sed -n 1,16p "$W/e"; }
CYRIUS_TYPE_CHECK=0 "$CC" < "$W/a14.cyr" > "$W/o" 2> "$W/e" || true
n=$(count "$K2"); [ "$n" = 0 ] || bad "axis 14: CYRIUS_TYPE_CHECK=0 still printed $n kind-2 warning(s)"

# --- axis 15 (6.7.11): kind 4 for an ARGUMENT into an f64 / f32 parameter ---
# The filed repro, verbatim (issues/archived/2026-10-09-int-argument-to-f64-param-silent.md): no warning through
# 6.7.10; four now — the tail call (line 11), a call (15), an f32 parameter (16), a method (17) — and the
# exit code stays 15 (ADR-002: the integer's bits are passed, a warning, not a conversion).
RP15="docs/development/issues/repros/2026-10-09-int-argument-to-f64-param-silent.cyr"
"$CC" < "$RP15" > "$W/rp15" 2> "$W/e" || true
n=$(count "$K4"); [ "$n" = 4 ] || { bad "axis 15: the filed repro: kind-4 warning count $n, want 4 (lines 11 15 16 17)"; sed -n 1,6p "$W/e"; }
for want in 11 15 16 17; do
    grep "$K4" "$W/e" | grep -q ">:$want:" || bad "axis 15: the filed repro: no kind-4 warning at line $want"
done
if [ -s "$W/rp15" ]; then
    chmod +x "$W/rp15"; rc=0; "$W/rp15" || rc=$?
    [ "$rc" = 15 ] || bad "axis 15: the filed repro exits $rc, want 15 (the value is unchanged)"
else bad "axis 15: the filed repro did not build: $(grep '^error' "$W/e" | head -1)"; fi
# Every argument path, one warning each at its line (11, 14-19); none on lines 20-27: 0, an IEEE pattern
# in hex, a float literal, a runtime value, a parenthesised or computed constant, an untyped parameter.
cat > "$W/a15.cyr" <<'EOF'
struct P { x; }
enum E { THREE = 3 }
fn f(x: f64): i64 { return f64_to(x * 2.0); }
fn g(x: f32): i64 { var d: f64 = f32_to(x); return f64_to(d * 2.0); }
fn u(x): i64 { return x; }
#inline
fn fi(x: f64): i64 { return f64_to(x * 2.0); }
impl P { fn m(self, x: f64): i64 { return f64_to(x * 2.0); } }
fn P_add(a: P, b: f64): i64 { return f64_to(b * 2.0); }
fn P_sub(a: P, b: f32): i64 { var d: f64 = f32_to(b); return f64_to(d * 2.0); }
fn t(): i64 { return f(3); }
fn go(n): i64 {
    var p = P { 1 };
    var e = f(3);
    e = e + g(3);
    e = e + p.m(3);
    e = e + fi(3);
    e = e + fwd(3);
    e = e + (p + 3) + (p - 3) + f(-3) + f(THREE) + f(x: 3);
    e = e + f(0);
    e = e + f(0x3FF0000000000000);
    e = e + f(3.0);
    e = e + g(1.5);
    e = e + f(n);
    e = e + f((3));
    e = e + f(3 + 1);
    e = e + u(3) + t();
    return e;
}
fn fwd(x: f64): i64 { return f64_to(x * 2.0); }
syscall(60, go(2) & 255);
EOF
build "$W/a15.cyr"
n=$(count "$K4"); [ "$n" = 11 ] || { bad "axis 15: kind-4 warning count $n, want 11 (lines 11 14-19: a tail call, a call, f32, a method, #inline, a forward call, + / - operands, -3, an enum constant, a named argument)"; sed -n 1,14p "$W/e"; }
for want in 11 14 15 16 17 18 19; do
    grep "$K4" "$W/e" | grep -q ">:$want:" || bad "axis 15: no kind-4 warning at line $want"
done
n=$(grep "$K4" "$W/e" | grep -c ">:19:" || true); [ "$n" = 5 ] || bad "axis 15: line 19 (p + 3, p - 3, f(-3), f(THREE), f(x: 3)) has $n kind-4 warnings, want 5"
if grep "$K4" "$W/e" | grep -q ">:2[0-7]:"; then bad "axis 15: kind 4 fired on a no-warning row (lines 20-27)"; fi
CYRIUS_TYPE_CHECK=0 "$CC" < "$W/a15.cyr" > "$W/o" 2> "$W/e" || true
n=$(count "$K4"); [ "$n" = 0 ] || bad "axis 15: CYRIUS_TYPE_CHECK=0 still printed $n kind-4 warning(s)"

# --- axis 16 (6.7.11): ONE integer + f64 mix warns ONCE, however far its result is carried ---
# The filed repro (issues/archived/2026-10-08-int-f64-mix-warns-twice-in-a-chain.md), verbatim in a fn: two kind-2
# warnings through 6.7.10 (the enclosing `+` saw the inner mix's f64 type); one now. Each row is one
# statement in its own program: <id>|<statement>|<kind-2 count>|<kind-1 count>.
for spec in 'r|var x = 1; x = x + (x + 1.5);|1|0' 'c|var x = 1; x += x + 1.5;|1|0' \
            'm|var x = 1; var y = 2 * (x + 1.5);|1|0' 'k|var x = 1; var y = x - (x * (x + 1.5));|1|0' \
            'p|var x = 1; var y = x + ((x + 1.5));|1|0' 'b|var u = 1.5; var y = 1 + 2 * f64_add(u, 1.5);|1|0' \
            'cc|var x = 1; x += x - (x * (x + 1.5));|1|0' 't|var x = 1; x = (x + 1.5) + (x + 2.5);|2|0' \
            'k1|var x = 1; var y = x + 1.5 + 2;|1|1'; do
    id=${spec%%|*}; rest=${spec#*|}; stmt=${rest%%|*}; rest=${rest#*|}; w2=${rest%%|*}; w1=${rest#*|}
    printf 'fn main(): i64 {\n    %s\n    return 0;\n}\nsyscall(60, main());\n' "$stmt" > "$W/a16_$id.cyr"
    build "$W/a16_$id.cyr"
    n=$(count "$K2"); [ "$n" = "$w2" ] || { bad "axis 16 ($id: '$stmt'): kind-2 warning count $n, want $w2"; sed -n 1,4p "$W/e"; }
    n=$(count "$K1"); [ "$n" = "$w1" ] || bad "axis 16 ($id: '$stmt'): kind-1 warning count $n, want $w1"
done
# Diagnostic only: the binary is the one CYRIUS_TYPE_CHECK=0 (no warning at all) builds, byte for byte.
cat "$W"/a16_*.cyr | grep -v '^syscall' | sed 's/fn main()/fn m_/' > "$W/a16_all.cyr"
i=0; : > "$W/a16_all2.cyr"
while IFS= read -r line; do
    case "$line" in 'fn m_'*) i=$((i + 1)); echo "fn m$i(): i64 {" >> "$W/a16_all2.cyr" ;; *) echo "$line" >> "$W/a16_all2.cyr" ;; esac
done < "$W/a16_all.cyr"
echo 'syscall(60, m1() + m2());' >> "$W/a16_all2.cyr"
"$CC" < "$W/a16_all2.cyr" > "$W/a16_on" 2> "$W/e" || true
CYRIUS_TYPE_CHECK=0 "$CC" < "$W/a16_all2.cyr" > "$W/a16_off" 2> "$W/e0" || true
n=$(count "$K2")
if [ ! -s "$W/a16_on" ]; then bad "axis 16: the combined program did not build: $(grep '^error' "$W/e" | head -1)"
elif ! cmp -s "$W/a16_on" "$W/a16_off"; then bad "axis 16: the warned binary differs from the CYRIUS_TYPE_CHECK=0 one"
elif [ "$n" != 10 ]; then bad "axis 16: the combined program draws $n kind-2 warnings, want 10"; fi

# --- axis 17 (6.7.13): a comparison, `&&` / `||` and `& | ^ % << >> >>>` give an INTEGER — no f64 type left ---
# issues/archived/2026-10-14-integer-comparison-result-keeps-f64-right-operand-type.md; `& | ^ % << >> >>>` the user's
# decision D12 (a), 2026-10-15. With an f64 RIGHT operand the result kept the f64 type, so the next `*` took
# the f64 arm (the repro: exit 0, want 3) with a false kind-1 warning naming the wrong mix. Each row is one
# program, built and run on x86_64: <id>@<statements>@<exit>@<kind-0>@<kind-1>@<kind-2> warnings. `x` holds
# f64 bits whose low byte is 3 (a shift count of 3, a checkable `&`). `n + x` keeps kind 2's f64 (D41).
K0="comparison mixes f64 and integer operands"
printf 'fn main(): i64 { var n = 1; var x: f64 = 2.5; var c = (n < x) * 3; return c; }\nsyscall(60, main());\n' > "$W/a17_repro.cyr"
build "$W/a17_repro.cyr"; chmod +x "$W/o" 2>/dev/null || true
rc=0; [ -s "$W/o" ] && { "$W/o" || rc=$?; }
n0=$(count "$K0"); n1=$(count "$K1")
[ "$rc" = 3 ] || bad "axis 17 (the repro, verbatim): exit $rc, want 3"
[ "$n0" = 1 ] && [ "$n1" = 0 ] || bad "axis 17 (the repro): kind-0 $n0 / kind-1 $n1 warnings, want 1 / 0"
for spec in 'lt@var c = (n < x) * 3; return c;@3@1@0@0' 'and@var c = (n == 64 && x) * 3; return c;@3@0@0@0' \
            'or@var c = (n == 0 || x) * 3; return c;@3@0@0@0' 'band@var m = 7; var c = (m & x) * 3; return c;@9@0@0@0' \
            'bor@var m = 7; var c = (m | x) * 3; return c & 255;@21@0@0@0' 'bxor@var m = 7; var c = (m ^ x) * 3; return c & 255;@12@0@0@0' \
            'mod@var c = (n % x) * 3; return c;@192@0@0@0' 'shl@var m = 7; var c = (m << x) * 3; return c;@168@0@0@0' \
            'shr@var c = (n >> x) * 3; return c;@24@0@0@0' 'sar@var c = (n >>> x) * 3; return c;@24@0@0@0' \
            'add@var y = n + x; return 5;@5@0@0@1'; do
    id=${spec%%@*}; rest=${spec#*@}; stmt=${rest%%@*}; rest=${rest#*@}; want=${rest%%@*}; rest=${rest#*@}
    w0=${rest%%@*}; rest=${rest#*@}; w1=${rest%%@*}; w2=${rest#*@}
    printf 'fn main(): i64 {\n    var n = 64;\n    var x: f64 = 0.0;\n    store64(&x, 0x3FF0000000000003);\n    %s\n}\nsyscall(60, main());\n' "$stmt" > "$W/a17_$id.cyr"
    build "$W/a17_$id.cyr"; chmod +x "$W/o" 2>/dev/null || true
    rc=0; if [ -s "$W/o" ]; then "$W/o" || rc=$?; else rc=none; fi
    [ "$rc" = "$want" ] || bad "axis 17 ($id: '$stmt'): exit $rc, want $want"
    n=$(count "$K0"); [ "$n" = "$w0" ] || bad "axis 17 ($id): kind-0 warning count $n, want $w0"
    n=$(count "$K1"); [ "$n" = "$w1" ] || { bad "axis 17 ($id): kind-1 warning count $n, want $w1"; sed -n 1,3p "$W/e"; }
    n=$(count "$K2"); [ "$n" = "$w2" ] || bad "axis 17 ($id): kind-2 warning count $n, want $w2"
done

# --- axis 18 (6.7.13): a comparison bound from a `: f64` leading call is an integer — `0 - c` does not warn ---
# issues/archived/2026-10-14-f64-leading-call-types-comparison-binding-f64.md: `var c = f() < 1.0;` was typed f64 (the leading
# call's type), so `0 - c` warned kind 2 (and computed -1) and `-c` flipped the sign bit (the repro: exit 3, want 1).
printf 'fn f(): f64 { return 0.5; }\nfn main(): i64 { var c = f() < 1.0; var n = -c; return n + 2; }\nsyscall(60, main());\n' > "$W/a18_repro.cyr"
build "$W/a18_repro.cyr"; chmod +x "$W/o" 2>/dev/null || true
rc=0; if [ -s "$W/o" ]; then "$W/o" || rc=$?; else rc=none; fi
[ "$rc" = 1 ] || bad "axis 18 (the repro, verbatim): exit $rc, want 1"
for spec in 'sub@var c = f() < 1.0; var n = 0 - c; return n + 2;@1@0' 'and@var k = 1; var c = f() > 0.1 && k == 1; var n = 0 - c; return n + 2;@1@0' \
            'keep@var x = f() * 2.0; var y = x + x; return f64_to(y);@2@0'; do
    id=${spec%%@*}; rest=${spec#*@}; stmt=${rest%%@*}; rest=${rest#*@}; want=${rest%%@*}; w2=${rest#*@}
    printf 'fn f(): f64 { return 0.5; }\nfn main(): i64 { %s }\nsyscall(60, main());\n' "$stmt" > "$W/a18_$id.cyr"
    build "$W/a18_$id.cyr"; chmod +x "$W/o" 2>/dev/null || true
    rc=0; if [ -s "$W/o" ]; then "$W/o" || rc=$?; else rc=none; fi
    [ "$rc" = "$want" ] || bad "axis 18 ($id: '$stmt'): exit $rc, want $want"
    n=$(count "$K2"); [ "$n" = "$w2" ] || { bad "axis 18 ($id): kind-2 warning count $n, want $w2"; sed -n 1,3p "$W/e"; }
done

[ "$fail" = 0 ] || exit 1
echo "PASS: f64_int_mix_warn (4 int-left ops warn; no false positives; kind 1 intact; TYPE_CHECK=0 silences; f64 fields and builtin results typed; kinds 3 + 4; kind 5, compound operands, re-judged flags, typed copies, compound kind 2; kind 4 for an argument; one warning per mix; a comparison / bitwise result is an integer, a comparison bound from a : f64 call too)"

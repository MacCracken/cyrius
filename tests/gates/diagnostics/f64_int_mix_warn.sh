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
#           and a closure's own declarations leave the enclosing fn's flags as they were.
#   axis 8  (6.6.10) kind 4: an integer CONSTANT stored into an f64 / f32 slot (declaration,
#           assignment, field store, struct literal, global) warns once each; 0, an IEEE bit
#           pattern in hex (>= 2^52), a float literal and a runtime value do not.
#   axis 9  CYRIUS_TYPE_CHECK=0 silences kinds 3 and 4.
# Mutation-proven: with the four `_INT_F64_MIX` calls removed, axis 1 reads 0 of 4 and fails.
# (6.6.10) with PARSE_INTRIN's `_FBR_MARK` call removed axis 6 fails; with the unary-minus
# `_FLT_TYPE_WARN(S, 3)` removed, or _cl_restore_locals' flag copy removed, axis 7 fails; with `_IFS_CHECK` returning early axis 8 fails.
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
    return r1 + r2 + r3 + r4 + r5 + r6 + r7 + k1 + k3 + neg(1) + clos();
}
var r = main();
syscall(60, r & 255);
EOF
build "$W/a7.cyr"
n=$(count "$K3"); [ "$n" = 8 ] || { bad "axis 7: kind-3 warning count $n, want 8 (-c -e -z -n -x -G -(c), and clos()'s -c across a closure; not -i -GT -GI -q, clos()'s -n or a parameter)"; sed -n 1,12p "$W/e"; }

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

[ "$fail" = 0 ] || exit 1
echo "PASS: f64_int_mix_warn (4 int-left ops warn; no false positives; kind 1 intact; TYPE_CHECK=0 silences; f64 fields and builtin results typed; kinds 3 + 4)"

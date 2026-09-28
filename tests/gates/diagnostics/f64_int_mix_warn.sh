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
# Mutation-proven: with the four `_INT_F64_MIX` calls removed, axis 1 reads 0 of 4 and fails.
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

[ "$fail" = 0 ] || exit 1
echo "PASS: f64_int_mix_warn (4 int-left ops warn; no false positives; kind 1 intact; TYPE_CHECK=0 silences)"

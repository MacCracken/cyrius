# An integer comparison or bitwise operator with an f64 right operand leaves its result typed f64 — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-14 by the 6.7.11 struct lane (unit S5, issues/2026-10-08-struct-operator-results.md
#2), reproduced with the lane's compiler (struct worktree after `29d1210e`).
**Placement:** 6.7.12 — repair 2 (filed from the 6.7.11 struct lane) — never 7.x.
**Severity:** Low — a silent wrong value after a construct that already warns (kind 0 on the comparison, kind 1 on
the next operator); workaround: name the comparison in a typed variable (`var c: i64 = n < x;`).
**Affects:** cycc since v6.2.19 (the f64 comparison arms) through the 6.7.11 lane.

## Summary

6.7.11 (#2 of the struct-operator issue) made every integer operator's result an integer for a STRUCT right
operand (`_int_st`: `n - s + 10`, `(n < s) + 10`, `(n & s) + 10` no longer dispatch). It keeps an f64 / f32 right
operand's type on purpose: for `+ - * /` that is kind 2's design (6.6.8, re-decided 2026-10-13: warn once, typing
unchanged). A COMPARISON, though, yields 0 or 1 whatever its operands are, and `& | ^ % << >>` yield integers too;
with an INTEGER left operand and an f64 right one, the result keeps the f64 type, so the next operator takes the
f64 arm:

```cyrius
fn main(): i64 { var n = 1; var x: f64 = 2.5; var c = (n < x) * 3; return c; }
syscall(60, main());
```

`cat repro.cyr | build/cycc > r && chmod +x r && ./r; echo $?` → **0** (want 3: `n < x` is 1), with
`warning:<source>:1:61: comparison mixes f64 and integer operands` and `warning:<source>:1:66: f64 arithmetic with a
non-f64 right operand` — the second names the wrong mix: the left operand is a boolean, not an f64. (`(n & x) * 3`
takes the f64 multiply the same way, with the kind-1 warning.) An f64 LEFT operand is fine: `_PLOGIC_ATOM`'s f64
and f32 arms set SESTYPE 0.

## Root cause

`_PLOGIC_ATOM`'s integer compare arm (`src/frontend/parse_expr.cyr`) never writes its result's type: the
expression type is the right operand's (`PEXPR` of the rhs). 6.7.11's `_int_res` there clears a struct type only.
The same holds for `_pexpr_bit_ps` (`& | ^`) and PARSE_TERM's tail (`% << >> >>>`).

## Proposed fix

A comparison (and `&&` / `||`) clears any expression type: SESTYPE 0 in the integer arm, as the f64 arms do —
whether `& | ^ % << >>` with an f64 right operand stay f64-typed (they are integer operations on its bits) is the
same question kind 2 answered for `+ - * /` (left as it was); for those, the user's call.

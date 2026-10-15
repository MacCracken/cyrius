# An untyped `var c = f() < 1.0;` with a `: f64` leading call is typed f64 — `-c` flips the sign bit — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-14 by the 6.7.11 struct lane (unit S5, issues/archived/2026-10-08-struct-operator-results.md
#1), reproduced with the lane's compiler (struct worktree after `29d1210e`) and with the tree before it (`93e04937`).
**Placement:** 6.7.13 — repair 3: struct values (receives lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Severity:** Low — a silent wrong value on a narrow shape (a boolean bound from a comparison whose left operand is a
`: f64` call), plus a false kind-2 warning; workaround: annotate (`var c: i64 = f() < 1.0;`) or compare in an `if`.
**Affects:** cycc since v6.5.21 (`var x = f();` with `f: f64` types x f64) through the 6.7.11 lane.

## Summary

PARSE_VAR's untyped-declaration inference takes the LEADING call's return annotation when the initialiser starts
with a call (`_var_rhs_call`). 6.7.11 (`_var_rhs_csid`, issue #1 above) restricted that to a call that ENDS the
initialiser for a STRUCT return, but kept a `: f64` return's f64 (-9) unconditionally, because `var x = f() * 2.0;`
is f64 arithmetic that the leading call drives and must stay f64 (row `b_lf64`, tests/tcyr/crossos/
struct_operator_result_binding.tcyr). A comparison is the exception: `f() < 1.0` is an integer 0 / 1, yet the
binding is typed f64. So `-c` is a float negation (the sign bit flipped: 0x8000000000000001 for true), and
`0 - c` draws a false "integer arithmetic with an f64 right operand" warning while computing -1.

## Reproduction

```cyrius
fn f(): f64 { return 0.5; }
fn main(): i64 { var c = f() < 1.0; var n = -c; return n + 2; }
syscall(60, main());
```

`cat repro.cyr | build/cycc > r && chmod +x r && ./r; echo $?` → **3** (want 1: c is 1, -1 + 2 = 1). With
`var n = 0 - c;` instead: exit 1, and `warning:<source>:2:50: integer arithmetic with an f64 right operand`.
`var d = -c; var e = 0 - c; d == e` is false (exit 0) — the two negations disagree. Measured the same (exit 3 on a
true result) with `f() == 0.5`, `f() <= 0.5`, `f() >= 0.5` and `f() > 0.1 && k == 1`; a false result reads right by
accident (-0.0's bits + 2 = 2).

## Root cause

`_var_rhs_csid` (`src/frontend/parse_decl.cyr`, 6.7.11) returns the callee's GFRS unchanged when it is not a
struct (`rs <= 0`), so -9 (f64) types the binding whatever follows the call. The f64 type of a comparison's
result is already right in the expression state (`_PLOGIC_ATOM`'s f64 arm sets SESTYPE 0), but the binding's
SLTYPE is decided from the peek before the parse.

## Proposed fix

Judge the f64 binding after the parse, as `_var_rhs_post` judges an operator's struct: keep -9 only when the
initialiser's final expression type is still F64 (`GESTYPE(S) == F64_TYID` at the `;`, or the call ends the
initialiser). `var x = f() * 2.0;` (F64 at the end) keeps f64; `var c = f() < 1.0;` (SESTYPE 0 after the compare)
is untyped. Rows: the repro (1), `0 - c` with no warning, `b_lf64` unchanged.

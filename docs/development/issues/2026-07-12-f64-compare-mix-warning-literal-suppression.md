# stricter float typecheck: the f64/int comparison-mix warning (kind 0) needs literal-0 suppression before it can ship

**Filed:** 2026-07-12 (v6.4.56 D3 — the compare-mix half of the stricter-float-typecheck deliverable).
**Severity:** P3 (a warning-quality refinement; the arithmetic-mix warning already ships).
**Component:** `src/frontend/parse_expr.cyr` (`_FLT_TYPE_WARN` kind 0, `_PLOGIC_ATOM` compare arm).

## Context

v6.4.56 shipped the stricter-float-typecheck as WARN-only: the **arithmetic**-mix warning (kind 1,
"f64 arithmetic with a non-f64 right operand") is live — `x + 1` on an f64 `x` silently means
`x + <int-1-as-a-denormal>`, not `x + 1.0`, so it is a genuine footgun worth flagging. The
`_FLT_TYPE_WARN` helper already has the **kind 0** ("comparison mixes f64 and integer operands")
branch, but its call sites in the `_PLOGIC_ATOM` compare arm are **not yet wired**, because kind 0
false-positives on a common idiom.

## The blocker — `if (x > 0)` false-positives

For an f64 `x`, `if (x > 0)` **works correctly**: the integer literal `0`'s bit pattern is identical
to the f64 `0.0`, so `ucomiss`/`fcmp` against it is exact. But a naive compare-mix check (RHS is not
`F64_TYID`) would warn on it — and f64 sign-checks (`if (result > 0)`) are common in the f64
libraries (naad/hisab/goonj), so it would nag idiomatic code.

**Note:** this is specific to literal **0**. `if (x > 5)` IS a real bug (5's int bits ≠ 5.0's f64
bits, so it compares against a denormal), so the warning there is correct — only literal 0 is the
exception.

## Fix

Wire the kind-0 call sites in the `_PLOGIC_ATOM` compare arm (the two `if (GESTYPE(S) != F64_TYID)`
/ `if (GESTYPE(S) == F64_TYID)` checks — the prototype in the v6.4.56 design draft), **plus** a
suppression: skip the warning when the non-float operand is the **integer literal 0** (peek the RHS
token before parsing, or detect a literal-0 producer). Keep it WARN-only (an error would break the
i64-boxed idiom, ADR-002). The two SESTYPE-normalization leak-fixes (PF64CMP, PARSE_FNCALL) that
kind 0 depends on already shipped in v6.4.56.

## Acceptance

- `if (x > 5)` (f64 x, non-zero int literal) warns; `if (x > 0)` does NOT.
- `if (x > y)` (f64 x, int var y) warns (genuine mix).
- 0 corpus false positives; cycc self-host byte-identical.

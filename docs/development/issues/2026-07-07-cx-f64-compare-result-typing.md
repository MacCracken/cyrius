# cx: f64 comparison results are F64-typed → misbehave in `if()` / `== N` on the cx target

- **Filed**: 2026-07-07 (during cx arc Release B — cx scalar float)
- **Severity**: P2 — a correctness footgun IF the compare opcodes are wired, so for
  Release B f64 comparisons **fail loud** on cx (hard-error) rather than ship
  silent-wrong. Blocks conditional f64 logic on cx; arithmetic is unaffected.
- **Scope**: shared frontend type-tracking (`PF64CMP`) × the cx backend's handling
  of an F64-typed condition. x86/aarch64 are NOT affected (they handle it today).

## Symptom

The cxvm f64 compare opcodes (`flt`/`fle`/`fgt`/`fge`/`feq`/`fne`, 0x5A-0x5F) exist and
compute correctly for **direct** use — `var g = f64_gt(a, b);` yields the right 0/1.
But used in a conditional they misbehave **only on cx**:

- `if (f64_lt(a, b)) { ... }` is **always true** (all of lt/gt/eq returned 1 in
  isolation, regardless of the operands).
- `f64_gt(a, b) == 1` evaluates false when it should be true (and `== 0` works only
  by coincidence — 0 bits == 0.0).

x86 native compiles the same programs correctly.

## Root cause (to confirm)

`f64_lt`/`f64_gt`/`f64_eq` return an **i64 boolean**, but the builtin dispatch
(`parse_expr.cyr:2124`, `if (ptyp >= 68) { if (ptyp <= 70) { PF64CMP(S, ptyp); return 0; } }`)
does **NOT** `SESTYPE(S, 0)` — unlike the other i64-returning f64 builtins (`f2i` at
:2123, `f32_from` at :2143 both reset). So the compare result stays **F64_TYID**, and a
following `if (...)` / `== N` takes the f64-typed path. On x86 that path happens to work
(the i64 boolean and the literal compare as equal bit patterns via `ucomisd`); on cx the
f64-typed-condition path yields wrong results.

**A naive fix — adding `SESTYPE(S, 0)` after `PF64CMP` — was tried and REJECTED**: it
churned 10 corpus programs' codegen (differential RED, they rely on the f64-typed result)
AND did not fix cx. So the fix is NOT a one-line frontend type reset — it needs the cx
backend's `if (F64_expr)` truthiness path traced (why an F64-typed condition is
always-true on cx) and reconciled with the x86 behavior, or a cx-local type/emit fix.

## Current state (Release B)

`EF64_CMP` in `src/backend/cx/emit.cyr` hard-errors (`_cx_float_unsupported`) so f64
comparisons **fail loud** on cx. The cxvm compare opcodes are shipped and correct — the
follow-up only needs to (a) fix the type-tracking / cx conditional path and (b) re-wire
`EF64_CMP` to emit the opcodes. f64 **arithmetic** (`+`/`-`/`*`/`/`, casts, neg/abs) works.

## Fix sketch (the cx-arc "f64 compare" follow-up)

1. Trace how `if (F64_expr)` lowers on cx vs x86 (the truthiness test for an f64 condition).
2. Decide: reset the compare result to i64 in a cx-safe way (without the 10-program churn),
   OR fix the cx f64-condition truthiness emit.
3. Re-wire `EF64_CMP` to the 0x5A-0x5F opcodes; add a `_cx_float_gate` conditional case.

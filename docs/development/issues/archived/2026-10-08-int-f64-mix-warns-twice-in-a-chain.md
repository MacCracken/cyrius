# One integer + f64 mix warns twice when the expression continues (`x = x + (x + 1.5)`) — RESOLVED

> ✅ **RESOLVED in v6.7.11** (ST-11, the user's decision D41 (2026-10-13, the roadmap's default): one integer + f64 mix warns once, however far its result is carried — the warned mix stamps the code pointer it ended at, and an operand that ends exactly there is that result; typing and code are unchanged. The repro `var x = 1; x = x + (x + 1.5);` warns once (twice before); `x += x + 1.5`, `2 * (x + 1.5)` once, `x - (x * (x + 1.5))` once (three times before); two mixes still warn twice. Row: `f64_int_mix_warn.sh` axis 16 (the repro verbatim, the combined binary equal to the `CYRIUS_TYPE_CHECK=0` one). The warnings `crossos/struct_value_codegen.tcyr` draws are its own deliberate integer + f64 rows (I12 / I13, K27), one each. CHANGELOG [6.7.11])

**Status:** ✅ **RESOLVED in v6.7.11** (see the banner). Was: 🟡 **OPEN** — reported 2026-10-08 by the 6.7.7 `+=` warning lane: `_INT_F64_MIX` leaves the expression typed f64 after warning, so the next integer operator warns again; `x += x + 1.5` (new in 6.7.7) inherits it.
**Placement:** 6.7.11 — Break 2, repair 1 (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-09 — never 7.x.
**Discovered:** 2026-10-08 by the 6.7.7 cmpdwarn lane (out of its scope); filed 2026-10-08.
**Severity:** Low — a duplicate diagnostic.
**Affects:** cycc ≤ 6.7.7

## Summary

After warning "integer arithmetic with an f64 right operand", `_INT_F64_MIX` does not reset the result's type, so an
enclosing integer operator sees an f64 right operand and warns a second time for the same mix. The lane also noted that
`tests/tcyr/crossos/struct_value_codegen.tcyr` draws this warning under 6.7.6 — check whether that row means it.

## Reproduction

`var x = 1; x = x + (x + 1.5);` → two warnings for one mix.

## Proposed fix

Warn once per mix: after warning, type the result as the integer side (what the generated code computes), or mark the
subexpression as already reported.

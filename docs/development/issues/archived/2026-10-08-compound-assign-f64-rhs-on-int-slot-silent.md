# `x += 1.5` on an integer slot is silent where `x = x + 1.5` warns — RESOLVED

> ✅ **RESOLVED in v6.7.7** (merge f0fd31e5 (lane cmpdwarn, 085d5ac7); CHANGELOG [6.7.7] § *Fixed*). `x OP= e` on an integer place now warns kind 2 on an f64 right operand, as the long form does; codegen unchanged over the 661-file corpus.

**Status:** ✅ **RESOLVED in v6.7.7** — see the banner above (filed OPEN 2026-10-08 against 6.7.6 @ 2fb6ad8b).
**Placement:** 6.7.7 — shipped.
**Discovered:** 6.7.5 planning probe `iw` (roadmap commit 68de8001); filed 2026-10-08 from roadmap.md.
**Severity:** Low
**Affects:** cycc 6.6.8 – 6.7.6 (the kind-2 warning's whole life; the field / `*p` forms since 6.7.5)

## Summary

The kind-2 type-check warning (an integer left operand with an f64 right operand: the f64's BITS are added) fires
in the expression parser's `+ - * /` arms, but compound assignment never reaches those arms. Every `OP=` on an
integer lvalue funnels through `_asg_compound_op`, whose integer arm combines the operands with no kind check, so
the same mistake spelled `x += 1.5` compiles with no diagnostic.

## Reproduction

```cyrius
struct H { n; }
var g = 1;
fn main() {
    var x = 1;
    x += 1.5;            # silent
    var h: H;
    h.n = 1;
    h.n += 1.5;          # silent
    g += 1.5;            # silent
    var y = 1;
    y = y + 1.5;         # warns (control)
    return x;
}
var r = main();
syscall(60, r);
```

```sh
cat repro.cyr | build/cycc > /tmp/r
```

Expected: `warning:<source>:N:C: integer arithmetic with an f64 right operand` on each `+= 1.5` line, as on the
`y = y + 1.5` line. Actual: the warning appears only on line 11.

## Root cause

`_asg_compound_op` (`src/frontend/parse.cyr:3149`): after `PCMPE` it routes an f64/f32 SLOT to
`_asg_compound_float` (`parse.cyr:3136`, which warns kinds 1/5), and every other slot to the integer arm
(`parse.cyr:3158`–`3170`) with no `_INT_F64_MIX` (`src/frontend/parse_expr.cyr:6223`) call. The variable, field
(6.7.5 B8), subscript (`_arr_sub_assign`) and `*p` (`_deref_store`) forms all share this helper, so one check covers
them all.

## Proposed fix

In `_asg_compound_op`'s integer arm, for `cop` 6–9 (`+= -= *= /=`), call `_INT_F64_MIX(S)` after `PCMPE` — the
same WARN-only kind 2 the binary operators use (ADR-002: no conversion). ⚠ Check that `_fbr_rhs` (which
`_INT_F64_MIX` reads and clears) holds this RHS's state and not a stale one from an earlier expression
(speculation — not traced). Add a diagnostics gate row per lvalue shape (variable, global, field, subscript, `*p`)
and a negative row (`x += 2` stays silent).

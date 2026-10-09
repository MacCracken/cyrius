# A call through a variable or closure that returns f64 gives an untyped word (documented design gap) — OPEN

**Status:** 🟡 **OPEN** (design gap, documented) — reproduced 2026-10-08 against 6.7.6 @ 2fb6ad8b with `build/cycc`:
`fncall1(&dbl, d) + 1.0` is an f64 add (5.0), `fncall1(fp, d) + 1.0` with `var fp = &dbl;` is an INTEGER add of the
bit patterns (warns "integer arithmetic with an f64 right operand"; the value is wrong), and binding the result to a
`var r: f64` first is right.
**Placement:** 6.7.8 — features: checked dyn + C2 (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-09 — never 7.x.
**Discovered:** 6.7.6 (lane FE's `_icall_result`, struct_value_codegen.sh rows I / I3); written into the guide as the
rule; filed 2026-10-08 from roadmap.md.
**Severity:** Low — a design gap the guide documents, with a stated workaround and a warning at the site.
**Affects:** cycc 6.7.6 (6.7.5 typed a name intrinsic's result from its LAST ARGUMENT, which got this case right by
accident and dispatched struct operators wrongly; 6.7.6 kept only the `&f` form)

## Summary

The result of `fncall0`..`fncall8(..)` / `callptr(..)` is an untyped word. The one exception (guide § "The result of a
name intrinsic"): when the callee is written `&f`, `f` returns `: f64` and the last argument is an f64, the result is an
f64. Through a variable (`var fp = &dbl;`) or a closure the callee is not known at compile time, so the result is an
untyped word and a following `+ 1.0` is an integer add of the f64's bits (the left operand types a binary operator).
The guide documents it: "Through a variable or a closure, or with any other last argument, the result is an untyped
word: write `f64_add(fncall1(fp, d), 1.0)` or bind it to a `var r: f64`." Filed as a design gap because a cyrius
program has no way to state a fn pointer's return type.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/fnptr.cyr"
fn dbl(x: f64): f64 { return x * 2.0; }
fn main(): i64 {
    var d: f64 = 2.0;
    var a = fncall1(&dbl, d) + 1.0;        # the documented exception: an f64 add (5.0)
    var fp = &dbl;
    var b = fncall1(fp, d) + 1.0;          # through a variable: an integer add of the bit patterns
    var r: f64 = fncall1(fp, d);
    var c = r + 1.0;                       # the documented workaround: 5.0
    var e = 0;
    if (f64_to(a) != 5) { e = e | 1; }
    if (f64_to(b) != 5) { e = e | 2; }
    if (f64_to(c) != 5) { e = e | 4; }
    return e;
}
syscall(60, main());
```

```sh
cat repro.cyr | build/cycc > /tmp/r && chmod +x /tmp/r && /tmp/r; echo $?      # run from the repo root
```

Actual: `warning:<source>:9:33: integer arithmetic with an f64 right operand`, exit **2** (only `b` is wrong).

## Root cause

`_icall_result` (`src/frontend/parse_expr.cyr:709`) types the result f64 only when `_icall_callee` (`:701`) resolved the
callee expression to exactly `&f` (`cfi >= 0`) and `GFRS(cfi) == -9`; any other callee expression gives `cfi = -1` and
an untyped result. There is no fn-pointer type in the language, so a variable's or closure's return type is unknowable
at the call.

## Proposed fix

A language decision — **the user's**: (a) a typed fn-pointer declaration (e.g. a return-type annotation on the
variable), checked at `&f` / closure assignment, read by `_icall_result`; or (b) a narrower compiler rule — a local
assigned exactly once from `&f` carries `f`'s return type (a provenance heuristic that silently stops at reassignment);
or (c) keep the documented rule and the warning (status quo). Until then the guide's workaround stands.

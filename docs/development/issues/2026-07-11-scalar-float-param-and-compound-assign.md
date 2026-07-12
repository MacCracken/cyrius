# scalar-float ergonomics: f64/f32 param arithmetic + compound-assign don't dispatch to float ops

**Filed:** 2026-07-11 (during v6.4.55 scalar-f64-return; surfaced by the design-workflow verifiers).
**Severity:** P2 (correctness footgun in a `: f64` fn; clean workaround exists).
**Component:** `src/frontend/parse_fn.cyr` (param-type tagging), `src/frontend/parse_decl.cyr`
(compound-assign desugar). Frontend / all targets.

## Context

v6.4.55 added scalar `f64` as a return type (sentinel -9, xmm0). A `: f64` fn body can do f64
arithmetic on **locals** (`var y: f64 = x; y + y` → `mulsd`), but NOT on **params** or via
compound-assign. Both are pre-existing gaps that make `: f64` fns easy to miscompile.

## Gap A — f64/f32 params are not float-typed

```cyr
fn inc(x: f64): f64 { return x + f64_from(1); }   # returns 0 (WRONG), not 5, for inc(4)
```
The param `x` is not tagged `F64_TYID`, so `x + <f64>` dispatches to **integer** add on the
bit-pattern (silent wrong answer). Workaround: `var y: f64 = x; return y + f64_from(1);` works
(exit 5). Fix: in PARSE_FN_DEF's param loop (`parse_fn.cyr` ~3198, where `_classify_param_type`
folds the class into masks), tag a scalar-`f64`/`f32` param's local slot `F64_TYID`/`F32_TYID`
(mind the SLTYPE negative-sid vs F64_TYID-positive schemes — this is why it was deferred from .55).
Applies to f32 params once f32 scalar arithmetic lands (v6.4.56).

## Gap B — compound-assign on a scalar float

`x += y` where `x` is an `f64` (or `f32`) local does NOT float-add — it exits 0 (integer-path or
no-op). Reproduces on f64 too on the unmodified compiler, so it is a **pre-existing** unsupported
path, not a float-return regression. Explicit `x = x + y` works. Fix: route the compound-assign
desugar (`parse_decl.cyr`) through the F64_TYID/F32_TYID operator arms when the LHS is float-typed.

## Acceptance

- `fn inc(x: f64): f64 { return x + f64_from(1); }` returns the correct value.
- `x += y` on an f64/f32 local float-adds.
- cycc self-host byte-identical; x86/aarch64/PE/cx unaffected on non-float code.

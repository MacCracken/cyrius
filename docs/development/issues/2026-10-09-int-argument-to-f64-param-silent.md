# An integer constant passed to an `f64` / `f32` parameter keeps its bits with no warning — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-09 against 6.7.6 @ e44470b7 with the tree's `build/cycc`. `f(3)` into
`fn f(x: f64)` passes 0x3, a subnormal, and prints no warning. The same holds for an `f32` parameter, a method and a
tail call. `var x: f64 = 3;` warns "an integer stored into an f64/f32 slot keeps its integer bits (write a float
literal)".
**Placement:** unpinned — 6.x-line backlog — never 7.x.
**Discovered:** 2026-10-09 during the 6.7.7 B6 (default and named arguments) planning (repro `f64i.cyr`). B6 refuses
the default-value form (`x: f64 = 3`), so this issue is the positional argument only.
**Severity:** Low — a missing warning. The value is ADR-002's kept bits, which every other float slot also stores,
with a warning.
**Affects:** cycc 6.6.10 – 6.7.6: the 6.6.10 warning never covered an argument. Measured on 6.7.0, 6.7.3 and 6.7.6; the
repro's inherent `impl` needs 6.7.0.

## Summary

Since 6.6.10, an integer CONSTANT stored into an `f64` / `f32` slot warns: a declaration, an assignment, a field store
or a struct-literal field (guide § "An integer CONSTANT stored into an f64 / f32 slot", `docs/guides/cyrius-guide.md:99`).
An argument for an `f64` / `f32` parameter is a store into that slot too, but it is not judged.

`f(3)`, `g(3)` with `g(x: f32)`, `p.m(3)` and `return f(3);` all pass the integer's bits silently, so the callee sees
about 1.5e-323, not 3.0. `0` and an IEEE hex pattern at or above 2^52 stay exempt, as they are for every other slot.

## Reproduction

`docs/development/issues/repros/2026-10-09-int-argument-to-f64-param-silent.cyr`:

```cyrius
struct P { x; }
fn f(x: f64): i64 { return f64_to(x * 2.0); }
fn g(x: f32): i64 { var d: f64 = f32_to(x); return f64_to(d * 2.0); }
impl P { fn m(self, x: f64): i64 { return f64_to(x * 2.0); } }
fn t(): i64 { return f(3); }
fn main(): i64 {
    var p = P { 1 };
    var e = 0;
    if (f(3) != 6) { e = e | 1; }
    if (g(3) != 6) { e = e | 2; }
    if (p.m(3) != 6) { e = e | 4; }
    if (t() != 6) { e = e | 8; }
    if (f(3.0) != 6) { e = e | 16; }
    return e;
}
var r = main();
syscall(60, r);
```

```
actual:   no warning; rc 0; exit 15 (each integer-argument row gets 0; f(3.0) is right)
expected: four "an integer stored into an f64/f32 slot keeps its integer bits" warnings, at lines 11 (the tail call),
          15, 16 (the f32 parameter) and 17 (the method); the exit code stays 15 (ADR-002: a warning, not a conversion)
```

Run it from the repo root: `cat <repro> | build/cycc > /tmp/r && chmod +x /tmp/r && /tmp/r; echo $?`.

## Root cause

- `src/frontend/parse_expr.cyr:2095` `_IFS_CHECK` (kind 4 of `_FLT_TYPE_WARN`) is called from the declaration, assignment,
  field-store and struct-literal paths (`src/frontend/parse.cyr:3068`, `src/frontend/parse_expr.cyr:2056`,
  `src/frontend/parse_decl.cyr:1743` / `:2203` / `:3760`). It is never called for an argument.
- `src/frontend/parse_expr.cyr:1558` `_bx_pcmpe_arg` is the per-argument hook every call path shares:
  - PARSE_FNCALL (`src/frontend/parse_fn.cyr:4560`);
  - the inline replay (:4355);
  - the tail arm (:944);
  - `_call_arg_one` (:2666), which serves `_owncall_args` and the method loop.

  It handles `bool` (`_pbool_get` 1) and the 6.7.6 f32 rounding (3). It has no f64 class, and it does not judge an
  integer constant for f32.

## Proposed fix

In `_bx_pcmpe_arg`, record the argument's first token. After PCMPE, when the parameter is `f64` or `f32`, call
`_IFS_CHECK(S, k, t)`. For f64 this needs a per-parameter class, recorded where `_fnt_pbool` records bool and f32 (in
pass 1 as well, for forward calls). `_param_float` tags only the callee's own slot, so a call cannot read it.

The warning is warn-only, the same ADR-002 posture as kind 4 everywhere else. Add a gate row for each call path in the
repro.

## Consumer-side workaround

Write the float literal (`f(3.0)`), or `f(f64_from(n))` for a runtime integer.

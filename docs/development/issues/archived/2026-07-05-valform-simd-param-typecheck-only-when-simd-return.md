# Value-form SIMD params skip type-checking (and the XMM param ABI) unless the callee returns a SIMD type

> **RESOLVED — v6.4.15 (absorber-band).** The filed root-cause was WRONG: an instrumented
> cycc proved `_fnt_simdmask` is already stored correctly (15) for a SIMD-param / non-SIMD-return
> fn — the mask is independent of return type. The real hole is `PARSE_RETURN`'s **tail-call
> path** (`return simdfn(local)`), which evaluates args via PCMPE/EPUSHR and never read the mask.
> Fix: read the callee's mask up-front (read-only FINDFN — the real FINDFN/REGFN registration is
> unchanged, byte-identical) and reject a value-form SIMD-arg type mismatch there, mirroring
> PARSE_FNCALL's class check. Reject-only (emission untouched) → self-host + differential 0/0
> (src/ has zero SIMD-value params). Guard added: `tests/simd_vec_reject.sh` Guard 3. See CHANGELOG [6.4.15].

- **Filed**: 2026-07-05 (during v6.4.4, SIMD Phase 1 f32v4)
- **Severity**: P3 (type-strictness gap; no memory-unsafety, no crash, no wrong
  result for correctly-typed programs)
- **Scope**: pre-existing — affects f64v2 identically; NOT introduced by f32v4.
  Discovered while resolving the v6.4.4 adversarial-review finding #2.

## Symptom

A function that takes a value-form SIMD parameter (`f64v2` / `f64v4` / `f32v4`)
but returns a **non-SIMD** type (e.g. `i64`) has its per-fn `_fnt_simdmask`
stored as **0**. At the call site (`PARSE_FNCALL`, `src/frontend/parse_fn.cyr`
~1156) `_fc_simd_mask` reads 0, so `_fc_class == 0` and the entire value-form
SIMD-arg routing block (including the v6.4.4 arg/param type-check) is skipped.

Consequences:

1. **No type-checking.** `fn f(a: f32v4): i64` called with an `f64v2` local
   compiles silently (the mask-based check at ~1186 never runs). Same for an
   `f64v2`-param / i64-return fn given an `f32v4` arg. The two 16-byte SIMD types
   are interchangeable at these call sites with no diagnostic.
2. **The arg is still passed correctly** — verified: `fn getlane0(v: f32v4): i64
   { return f32v4_lane0(v); }` and the f64v2 analogue both return the right value
   with matching types. So this is a *strictness* gap, not a correctness bug for
   well-typed code. (The arg reaches the callee via the non-mask path, not
   `ELOAD_F64V2_TO_XMM`.)

The v6.4.4 fix (mask code 3 distinguishing f32v4 from f64v2) **does** engage and
reject mismatches when the ABI is live — i.e. when the callee **returns** a SIMD
type (`mask != 0`), the idiomatic SIMD-in/SIMD-out shape. See
`tests/simd_vec_reject.sh` (guard 2). This issue is only the residual
`mask == 0` (non-SIMD-return) case.

## Reproduction

```
fn wrong(a: f32v4, b: f32v4): i64 { return f32v4_lane0(a); }
fn main(): i64 {
    var p: f64v2 = f64v2_make(100, 200);   # wrong type
    return wrong(p, p);                     # compiles rc=0 — should reject
}
```

vs. the ABI-engaged shape which IS now rejected:

```
fn combine(a: f32v4, b: f32v4): f32v4 { return f32v4_add(a, b); }
# combine(<f64v2>, <f64v2>)  ->  error: callee expects f32v4   (v6.4.4)
```

## Root cause (to investigate)

Why is `_fnt_simdmask` 0 for a SIMD-param / non-SIMD-return fn? Both writers
(`_prescan_params` ~2135 and the `PARSE_FN` def-fold ~3146) store the mask
unconditionally from the classified params, and the def-fold's param loop
recognizes f32v4 (`_ptc == 8`) / f64v2 (`_ptc == 6`). Yet the stored mask is 0
unless the fn also returns a SIMD type. The likely cause: the SIMD **param**
metadata path (SLTYPE tagging + mask OR) is only entered on the branch that also
sets up the SIMD **return** machinery, so a non-SIMD-return fn never runs it.
Needs a targeted trace of the def-fold param loop to confirm.

## Fix sketch

Make the param-mask assignment independent of the return type: ensure the
def-fold param loop tags each SIMD param's SLTYPE and ORs the mask code
regardless of `_cur_fn_ret_scalar`. Then the call-site type-check fires for all
SIMD-param callees. This also needs a re-verify that a non-SIMD-return callee
actually receives its value-form SIMD param via XMM (today it works via a
different path; changing the mask must not break that).

## Why deferred (not fixed in v6.4.4)

v6.4.4 shipped f32v4 end-to-end + the two adversarial-review findings that ARE
f32v4-specific (the -2121 OOB struct-table escape, and the f32v4/f64v2 mask
conflation on the ABI-engaged path). This residual is (a) pre-existing and equal
for f64v2, (b) not a correctness bug, and (c) requires its own def-fold trace +
re-verify of the non-SIMD-return param ABI. Tracked here for a follow-up slot in
the SIMD arc.

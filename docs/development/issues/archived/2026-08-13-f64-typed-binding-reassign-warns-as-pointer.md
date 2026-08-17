# `x = f64_add(x, y)` on an f64-typed binding warns about pointers

> ### ✅ RESOLVED — SHIPPED in v6.5.24
>
> Verified against the filed repro: the warning is gone for `f64`- and `f32`-typed
> bindings, and for width-annotated locals (`i32`, `i16`, `u8`).
>
> ⛔ **The filed one-line remedy was only HALF the bug, and shipping just that half would
> have left the check broken in the other direction.** Excluding `F64_TYID`/`F32_TYID` from
> a `lt > 0` test fixes the float symptom but leaves the sign inverted: in the local SLTYPE
> scheme a POSITIVE `lt` is a narrow WIDTH (1/2/4) or a float tag, and the pointer-like case
> is stored NEGATIVE as `0 - sid`. So `lt > 0` meant "narrow or float" — the exact set of
> locals the warning should ignore. Measured before the fix: `var w: i32 = 5; w = 6;`
> warned, and a STRUCT-typed local — a genuine typed pointer, the case the check exists for
> — did **not** warn at all. The condition is now `lt < 0`, which is what the GLOBAL arm of
> this same warning (`vt < 0`, ~40 lines below) had always used; the two arms had silently
> disagreed. Recorded on the roadmap as Slot 1 item (d).
>
> ⭐ **The reverse dependency is discharged**: `2026-08-13-ranga-ganita-f32-math-surface`
> was gated on this, and ganita 1.1.0's f32 tier shipped in the same release.
>
> ⛔ **No `.tcyr` could ever have caught this** — a warning changes no exit code — which is
> how a check that was wrong in both directions survived. Gate
> `tests/gates/diagnostics/typed_pointer_warn_sign.sh`; axis 4 is the anti-vacuous one,
> because axes 1-3 all assert an ABSENCE and would pass if the warning were deleted
> outright. Mutation-proven: restoring the pre-fix condition turns axes 1 and 4 red.

**Status:** ✅ RESOLVED in v6.5.24 — archive at slot close.
**Discovered:** 2026-08-13, abaco 2.4.1 adopting the v6.5.21 tuples it proposed
**Severity:** Low — **diagnostic only, values are correct** (verified against a
run binary, not inferred). It earns a filing because v6.5.21 is what makes it
common, and because there is no way to decline it.
**Affects:** cycc 6.5.21 (the warning predates tuples; see *Scope*)
**Repro:** [`repros/2026-08-13-f64-typed-binding-reassign-warns.cyr`](repros/2026-08-13-f64-typed-binding-reassign-warns.cyr)

## Summary

Assigning the result of an `f64_*` builtin back into a binding that carries an
f64 type produces:

```
warning:<source>:N: assigning non-pointer to typed pointer
        e1 = f64_add(e1, f64_from(444));
                                       ^
```

Two things are wrong with that line, and neither is the codegen:

1. **It says "pointer" about a float.** The local's declared type lands in the
   same slot the pointer types use (`GLTYPE` in `parse.cyr:1476-1482`), so an
   `: f64` binding inherits a pointer-flavoured message. A consumer reading it
   goes looking for a pointer bug that does not exist.
2. **It fires on the canonical correct pattern.** `x = f64_add(x, y)` is how
   every f64 accumulator in the language is written; `f64_*` builtins do not
   mark their result as carrying a type, so `aps == 0` and the warning trips
   every time.

**The values are right.** The repro prints 447 / 780 / 7 as expected. This is
noise, not a miscompile — stated explicitly because the last abaco filing got
its premise wrong by not checking, and the roadmap lesson from that one is to
premise-check against a run binary.

## Why v6.5.21 makes it worth fixing now

Before .21 you could simply not annotate — and per your own changelog, almost
nobody did: the `: f64` return annotation "had **two uses ecosystem-wide, both
in our own tests**". So the warning had nearly no surface.

Tuples change that, because **the element types come from the callee's
signature, not from the binding**. Given

```cyr
fn _two_product(a, b): (f64, f64) { … }
var p, e = _two_product(hi, d);
e = f64_add(e, f64_mul(lo, d));     # ← warns, unavoidably
```

there is no annotation to remove at the binding. The only way to silence it is
to drop the return type from the *callee* and fall back to the undeclared
v3.7.2 form — which gives up exactly what .21 added: arity checking at a forward
call, and the destructure contract.

Measured in the repro: `from_declared` warns, `from_undeclared` (identical
statement, undeclared callee) does not.

abaco hit this on five lines in `src/eval.cyr` and worked around it by
accumulating into a fresh local:

```cyr
var p, e0 = _two_product(hi, d);
var e = f64_add(e0, f64_mul(lo, d));    # fresh binding, untyped, no warning
```

That is a fine stopgap and abaco ships it. It is also exactly the kind of
"write it slightly wrong to keep the build quiet" that the warning should not be
causing.

## Scope — NOT tuple-specific

Verified: a plain `var x: f64 = …; x = f64_add(x, …);` warns identically
(`plain_typed_local` in the repro). So the trigger is *any* f64-typed binding
reassigned from an f64 builtin. Tuples do not introduce the behaviour, they
remove the ability to opt out of it.

An i64 tuple does **not** warn — `var p, e = ipair(); e = e + 4;` is clean — so
this is specific to the f64 type slot.

## Reproduction

```sh
cd <any dir with a cyrius.cyml declaring [deps].stdlib including "math">
cyrius build repros/2026-08-13-f64-typed-binding-reassign-warns.cyr out && ./out
```

Observed on cycc 6.5.21, x86_64 Linux — **two** warnings, and the pair is the
point:

```
warning:<source>:N: assigning non-pointer to typed pointer
        e1 = f64_add(e1, f64_from(444));      <- declared tuple: WARNS
warning:<source>:M: assigning non-pointer to typed pointer
        x = f64_add(x, f64_from(4));          <- plain `: f64` local: WARNS
447
780
7
```

`from_undeclared` — the identical statement against an undeclared callee — is
**absent** from the warning list. That absence is the finding: the warning
tracks whether the binding carries a type, and with a declared tuple return the
caller cannot choose. All three values correct.

⚠ The reported line numbers `N` / `M` will not match the file. That is a
separate, already-known issue —
[`2026-08-13-source-diag-line-shift-scales-with-deps-stdlib.md`](2026-08-13-source-diag-line-shift-scales-with-deps-stdlib.md)
— and is why this section quotes the caret text rather than the numbers.

## Suggested directions

Not a recommendation between these — the type-table design is yours:

- **Cheapest:** split the message. When the local's type is a scalar
  (`f64`) rather than a pointer type, say so — "assigning untyped value to an
  f64 binding" — so the reader is not sent hunting for a pointer.
- **Better:** mark the `f64_*` builtins' results as f64-typed, so
  `x = f64_add(x, y)` type-checks instead of warning. This is the same gap that
  made the `: f64` *return* annotation unusable before .21 (defect 3 in your
  .21 notes) — the argument side of it.
- **Also worth considering:** the adjacent `f64 arithmetic with a non-f64 right
  operand` warning fires on `e = e + 0`, which is correct and useful. That one
  is working as intended; only the pointer message is misleading.

## Not claimed

- No miscompile. Every value in the repro is correct on x86_64 Linux. Not
  checked on aarch64 / PE / cx — the abaco suite (657 asserts) is Linux-only,
  so if this turns out to interact with the per-backend f64 boxing that defect 2
  of .21 involved, that would be a separate finding and not one this file has
  evidence for.

# An `async fn` with a value-form vector parameter computes with the wrong vector at ANY arity — the constructor captures every parameter as one int slot — ✅ FIXED in 6.6.6 (bite 14)

**Status:** ✅ **FIXED in 6.6.6 (bite 14) — by refusal**, the second option the filing offered: a
value-form vector parameter on an `async fn` (any class, coroutine or plain) is now a compile error
naming the parameter — `async fn parameter 'v' is a value-form vector, which an `async fn` does not
capture yet — pass a pointer to it` (`src/frontend/parse_fn.cyr`, `_refuse_async_simd_param`).
Found during 6.6.6 bite 1's review; re-measured on HEAD `bbc880a9` before the fix: `50` / `35`,
exactly as filed.
**Placement:** the next 6.6.x repair release. Not parked to 7.x (nothing codegen is).
**Discovered:** 2026-09-19.
**Severity:** High — silent (exit 0, no diagnostic, a wrong number). The asymmetry makes it worse:
a SIMD **local** in an `async fn` is refused loudly (`a SIMD local in an `async fn` is not
supported yet`), so a user reasonably reads the accepted SIMD **parameter** as supported.
**Affects:** cycc 6.6.5 and 6.6.6-in-flight, x86_64 Linux measured (`async fn` with a mid-body
`await` is x86-only; aarch64 and cx refuse it). Behind `CYRIUS_ASYNC=1`.

## Reproduction

```cyr
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/vec.cyr"
include "lib/syscalls.cyr"
include "lib/simd.cyr"
include "lib/async.cyr"
fn nopark(): i64 { return 0; }
async fn c2(v: f64v2, a): i64 {
    var s = await nopark();
    return load64(&v) * 10 + a;
}
async fn a2(v: f64v2, a): i64 { return load64(&v) * 10 + a; }
fn main(): i64 {
    alloc_init();
    var v = f64v2_make(9, 0);
    var C = c2(v, 5);
    future_force(C); future_force(C);
    print_num(future_force(C)); println("");
    var F = a2(v, 5);
    var z = f64v2_make(3, 4);
    print_num(future_force(F)); println("");
    return 0;
}
var e = main();
syscall(60, e);
```

`cat r.cyr | CYRIUS_ASYNC=1 ./build/cycc > r && ./r` — want `95` twice:

| shape | got | what happened |
|---|---|---|
| coroutine (`await` in the body) `c2(v, 5)` | `50` | lane 0 of `v` reads `a`'s 5, `a` reads 0 — the ints shifted into the vector's slots |
| plain `async fn` (no `await`) `a2(v, 5)` | `35` | `v` is never captured; the body reads whatever XMM0 holds at `future_force` time (`z`'s 3) |

Without the `var z = f64v2_make(3, 4);` line the plain `async fn` prints `95` — XMM0 still holds `v`
by accident. A gate must clobber the vector registers between construction and force.

## Root cause

The async constructor (`src/frontend/parse_fn.cyr`, the `fn`-with-`async` constructor emitted after
the body — `ESTOREPARM(S, i, i, pc)` for `i` in `0..pc`, then the `_coro_was` copy
`obj[_CORO_LOCAL_OFF + i*8] = local i`, or `obj[16 + i*8] = arg i` for a plain async fn) treats
every parameter as ONE int-class argument in int register `i` and one frame slot `i`. A value-form
vector arrives in XMM (SysV) and owns 2 (or 4) slots, so the int registers are read one ordinal too
early and the vector itself is never stored. It is the same `pc`-as-everything shape 6.6.6 bite 1
removed from PARSE_FN_DEF's stack-param pass, but here it is wrong for REGISTER params too, and
the missing piece is capture, not homing.

## Proposed fix

Either capture the vector properly — the constructor records each param's (int ordinal, frame
slot, class) the way PARSE_FN_DEF's loop now does (`_stkp_defer`), stores XMM-passed vectors into
their 2/4 slots, and the impl's param layout matches — or, as the SIMD-local case already does,
refuse a value-form SIMD parameter on an `async fn` with a named diagnostic until it is supported.
Silent is not an option under either.

## Acceptance criteria

1. The repro prints `95` twice, or the compiler refuses both `async fn`s with a diagnostic naming
   the parameter.
2. If supported: a `.tcyr` with literal expectations covering f64v2 / f32v4 / f64v4 params, vector
   first / middle / last, 2 and 7+ int params, coroutine and plain async, with the vector registers
   clobbered between construction and `future_force`.
3. `build/cycc` fixpoint + seed-derive GREEN; the `.tcyr` corpus byte-difference count reported.

## Corrections to this filing

- **Not x86-only in effect.** "`async fn` with a mid-body `await` is x86-only" is true of the
  coroutine form, but a PLAIN `async fn` (no `await`) builds on every target, and the capture gap
  is target-independent — `future_force` re-enters the body with int arguments. Measured with the
  bite-1 compiler (`3e35aed2`) and cross-compilers built from its source: aarch64 (qemu-user, NOT
  hardware) plain `a2(v, 5)` → `35`, the same stale-V0 read as x86; Win64 (wine, NOT hardware)
  coroutine `c2(v, 5)` → `50`, and plain `a2(v, 5)` a PAGE FAULT (`movupd (%rax)` with
  `rax = 5`: the impl's by-pointer vector homing dereferenced the int argument). The refusal is in
  the shared frontend, so it covers every target.
- **Why refusal rather than capture.** Capturing needs the constructor to copy 16/32 bytes into the
  Future and the impl to take the vector as something `fncallN` can pass — i.e. a different
  parameter ABI for async impls than for every other fn. That is new machinery, not a repair; the
  refusal makes the gap loud, matches the existing SIMD-local refusal, and costs nothing that
  worked (a vector parameter never computed the right value). A pointer to the vector works today
  and is what the diagnostic says to use; `coroutine_midbody_suspend.sh` pins that it does.
- The follow-up it implied for bite 1's `ESTOREPARM(S, i, i, pc)` in the async constructor: with
  every async parameter now int-class, `pc` IS the int-class total, so that call is correct.


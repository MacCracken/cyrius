# `async fn` with 7+ parameters silently returns garbage — pinned v6.5.70

**Status:** ✅ **RESOLVED at v6.5.70** — filed and fixed in consecutive releases, which is one
release too many; it should have been fixed where it was found.

**The fix was one line, and both halves of the defect were in it.** `_async_emit_constructor`
read `if (i < 6) { ESTOREPARM(S, i, i, 0); }`: the gate skipped homing every parameter past the
sixth, and the hard-coded `0` is the ARITY argument `ESTORESTACKPARM` needs to compute the SysV
stack-arg displacement — so even an un-gated call would have addressed the wrong slot. It is now
`ESTOREPARM(S, i, i, pc)`, unconditionally; `ESTOREPARM` already dispatched to the stack path
past the register args. The second cause was real too: `future_force` laddered `fncall0..6` and
fell through for `argc >= 7`, so the impl was called with six arguments. `fncall7`/`fncall8`
already existed in `lib/fnptr.cyr` and are now wired, with anything past 8 failing loudly instead
of quietly wrong.

Verified: arity 6/7/8 correct for both `await` and the plain-fn control on every rung —
`tests/gates/frontend/coroutine_midbody_suspend.sh` axis 8.
**Filed:** 2026-09-06 (during v6.5.69)
**Severity:** High (silent wrong answer), bounded by the `CYRIUS_ASYNC=1` gate.
**Component:** `src/frontend/parse_fn.cyr` (`_async_emit_constructor`) + `lib/async.cyr`
(`future_force`).

## Reproduction

```
async fn a7(a,b,c,d,e,f,g): i64 { return a+b+c+d+e+f+g; }
var v7 = await a7(1,2,3,4,5,6,7);     # 28 expected
```

Measured on cycc 6.5.69, `CYRIUS_ASYNC=1`: **`v7` is a code-address-shaped value, not 28.**
Exit 0, no diagnostic. Controls in the same program are both correct — the 6-parameter async
form gives 21, and the *plain* (non-async) 7-parameter fn gives 28 — so it is the async
lowering alone, not the calling convention.

## Two independent causes, both required

1. **The constructor never spills parameters 6 and up.** `_async_emit_constructor` binds its
   params with `if (i < 6) { ESTOREPARM(S, i, i, 0); }` — arguments past the sixth arrive on
   the stack, are never homed, and the `obj[16 + i*8]` writes that follow therefore copy
   uninitialised frame slots into the Future.
2. **`future_force` has no dispatch past six arguments.** It ladders `fncall0`..`fncall6` and
   falls through for `argc >= 7`, so the impl's stack arguments are never written and are read
   as whatever the stack held.

## ⛔ DO NOT "FIX" THIS BY REFUSING ARITY >= 7

That is the `<=6 args` rule this repo retired at v6.4.64, and the retirement note is explicit
about why: a Win64 codegen defect had been written into `CLAUDE.md` as a language rule telling
users to restructure around it, so for about a year it was never fixed — and it was then cited
to file an issue against *sigil*, asking a stdlib to contort around a cyrius bug. **This is the
language repo: when the compiler cannot compile valid cyrius, fix the compiler.**

## Why v6.5.70 and not v6.5.69

v6.5.69 shipped the mid-body suspend transform, which requires a coroutine to take exactly one
parameter (its context) — the same restriction, from the same missing machinery: the
constructor cannot yet place arguments into frame slots, whether those slots live on the stack
(this bug) or in a coroutine frame (the coroutine limit). Fixing argument placement once closes
both. Splitting them apart would fix the same code twice.

## Acceptance

- `async fn` at arities 0 through 12 returns the right value, awaited and spawned.
- A coroutine (`async fn` with a mid-body `await`) accepts more than one parameter, with its
  arguments pre-bound into the coroutine frame by the constructor.
- Gate: an arity ladder 0..12 across both async forms, with the *plain* fn at the same arity as
  the control on every rung — the shape that isolated this defect in the first place.
- `tests/gates/frontend/coroutine_midbody_suspend.sh` axis 4's "exactly one parameter" refusal
  is REMOVED in the same change, not left as a documented limit.

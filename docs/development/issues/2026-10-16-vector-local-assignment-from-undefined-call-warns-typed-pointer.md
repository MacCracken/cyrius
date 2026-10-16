# `v = missing(..)` into a vector local warns "assigning non-pointer to typed pointer" — v is no typed pointer — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-16 on the 6.7.13 vectors lane (after the refusal-hint bite `64dfcee4` and the
review fixes, `0fbeb6de`) on x86_64, aarch64, cx and PE; the 6.7.10 compiler printed the same warning (measured at the
bite, the lane handoff's V4 notes). Pre-existing; the refusal-hint bite routes this shape back to that generic
assignment path (the lane base printed the vector-local refusal with the out-pointer hint instead).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (vectors lane; filed from the 6.7.13 vectors review, placed at the 6.7.13 integration, 2026-10-16) — never 7.x.
**Discovered:** 2026-10-16, the review of the 6.7.13 vectors lane
(issues/2026-10-14-vector-local-refusal-hint-every-source.md).
**Severity:** Low — a wrong warning before the right errors (the undefined-function lines); no binary is written.
**Kind:** bug (diagnostic).

## Reproduction

```cyrius
fn run(): i64 { var v: f64v2; v = f64v2_splat(1.0); return 1; }
syscall(60, run());
```

(no `include "lib/simd.cyr"`, so `f64v2_splat` is undefined)

```
the lane, x86_64 / aarch64 / PE:
warning:<source>:1:51: assigning non-pointer to typed pointer
warning: undefined function 'f64v2_splat'
warning: undefined function 'f64v2_splat' (reachable call site)
error: refusing to emit binary with 1 reachable undefined function(s) (pass --allow-undef to downgrade)
the lane, cx: the same warning, then "error: undefined function(s) called (cx backend):"
the base (f59668ad), x86_64:
error:<source>:1:35: a value-form vector local is assigned only from a local of its type or a call declared to return it (by name, or fncallN / callptr with the callee written `&f`) - got `f64v2_splat`; through a fn pointer held in a variable, give the target an out-pointer
(then the same undefined-function lines)
```

`var v: f64v2; var q = 1; v = q;` is refused by the vector-local rule with no warning (right), so only the undefined-call
shape meets the typed-pointer check.

## Root cause

A call naming no fn is now left to the generic assignment path (the refusal-hint bite: the undefined-function lines name
it). That path's typed-pointer warning (src/frontend/parse.cyr, the local arm: `if (lt < 0 && _asg_ret_sid <= 0)`
then `aps == 0`) takes any negative SLTYPE for a typed pointer (`0 - sid`): a value-form vector local's SLTYPE is a
descriptor (<= -2048), negative too, and an undefined call leaves no declared return sid.

## What a fix needs

The typed-pointer warning skips a value-form vector destination (its SLTYPE in the descriptor band); a row asserting the
undefined-call shape prints only the undefined-function lines, on x86_64 / aarch64 / cx / PE.

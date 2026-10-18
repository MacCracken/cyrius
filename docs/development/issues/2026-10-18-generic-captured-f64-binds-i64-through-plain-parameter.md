# A closure's captured `f64` passed to a generic's `x: T` binds i64, where the f64 local it captures binds f64 — `|| gid(h) * 2.0` multiplies the double's bits — DECISION — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 by the 6.7.15 generics lane (unit G4) on the lane's tree at 5bf321ca5
(after D11 / D12 / the token-scan fix), x86_64; the same before them (the capture rung never read an f64).
**Placement:** unplaced — filed from the 6.7.15 generics lane (wave 1; filed at its integration, 2026-10-18); the user places what 6.7.15 files — never 7.x.
**Discovered:** 2026-10-18, 6.7.15 generics G4, implementing D12 (a) (a captured struct VALUE now binds S through
`x: T` / `p: *T`, `_ic_cap`): the capture rung reads a captured struct and a captured `*S` / scalar pointer, and
reads every other capture as a global of its name (`_infer_conc_global(S, noff, 0)`), so a captured f64 is i64.
**Severity:** Medium — silent: the i64 base runs, its `: T` result is an untyped word, so `gid(h) * 2.0` is integer
arithmetic with a warning (the result 0, 3 is right); the same call on the f64 local the closure captures gives 3.
**Kind:** language — which instance an existing call runs (6.7.9 listed "an `f64` local or parameter, an `f64`
global, a float literal, a call returning `f64`"; a capture of one is not named), so the user's call.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
fn gid<T>(x: T): T { return x; }
fn m(): i64 { var h: f64 = 1.5; return f64_to(gid(h) * 2.0); }
fn mc(): i64 { var h: f64 = 1.5; var f = || f64_to(gid(h) * 2.0); return fncall0(f); }
syscall(60, m() * 10 + mc());
```

```
rc 0
warning:<source>:4:64: integer arithmetic with an f64 right operand
exit 30   (m() 3: the f64 instance; mc() 0: the captured h ran the i64 base — 33 if it bound f64)
```

## The question

Does a closure's captured `f64` bind `T = f64` through `x: T`, as the f64 local it captures does (6.7.9)? (a) yes —
as 6.7.15's D12 (a) binds a captured struct as the struct local it captures; (b) no — keep i64 and document it.

## Root cause

`_ic_cap` (src/frontend/parse_fn.cyr): a capture with no pointer mark whose snapshot type is not a struct reads as
a global of its name (`_infer_conc_global(S, noff, 0)`, -8 when none); the local rung's `_load_lt(..) == F64_TYID`
test (`_infer_conc_at`) has no capture twin (`_cl_snap_type(esl) == F64_TYID`).

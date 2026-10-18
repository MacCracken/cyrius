# A generic passing its `T`-typed VALUE whole into a stub generic's struct-carrier position (`gx(x)`, `x: T`, `fn gx<U>(b: Box<U>)`) is refused at its definition — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-16 by the 6.7.14 generics lane (unit G4) on its tree after the
forwarding-carrier bite (issues/archived/2026-10-14-generic-forwarding-carrier-into-stub-generic-refused.md) and on the slot-open
compiler: identical.
**Placement:** 6.7.15 — repair 5 (generics lane, wave 1, unit G5; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Discovered:** 2026-10-16, 6.7.14 generics G4, at the edge of the forwarding-carrier bite. That bite's filed scope (and
its brief) follows a struct carrier's NAME (`gx(b)`, `b: Box<T>`) or a generic CALL carrying T (`gx(mk1(x))`) in a
carrier position; a bare `T`-typed name in that position was not in it.
**Severity:** Low — a loud refusal of valid source; the forwarder can only be called with a `Box<..>` instance as `T`.
**Affects:** 6.7.8 (struct carriers) through the 6.7.14 lane tree; every target (frontend).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct Pt { x; y; }
struct Box<T> { v: T; n; }
fn gx<T>(b: Box<T>): i64 { return b.n + b.v.y; }
fn outer<T>(x: T): i64 { return gx(x); }
fn go(): i64 { var b: Box<Pt>; b.v.x = 3; b.v.y = 4; b.n = 8; return outer(b); }
syscall(60, go());
```

```
actual:   error:<source>:5:36: generic 'gx' has no i64 (or other scalar) instance: it uses its type parameter as a struct
          (a '.field' on a T-typed value, directly or in a generic it forwards T to) — pass a struct argument, or name a
          struct type argument
expected: exit 12 (outer$Box$Pt -> gx$Pt: 8 + 4), outer a stub (outer(5) refused naming outer)
```

## Root cause

The stub scan's forwarding mode (`_gs_use` mode 1 -> `_gs_fwd_carr` / `_gs_carries`, src/frontend/parse_fn.cyr)
answers 1 in a callee's struct-carrier position for a carrier's name or a generic call carrying T, and — by the
forwarding-carrier bite's scope — 0 for a bare T-typed name there (`if (dep == 0) { return 0; }` in `_gs_carries`).
So `outer` keeps an i64 base, whose `gx(x)` (x: i64) binds gx's T to i64 and meets gx's stub refusal at outer's
definition, called or not.

## Fix direction

Let `_gs_carries` answer `_gsn_has` at depth 0 too (a T-typed value whole in a carrier position carries T when T is
itself a carrier instance). Rows: the repro (12); `outer(5)` refused naming outer; a forwarder into a non-stub carrier
generic unchanged.

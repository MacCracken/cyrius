# A generic forwarding its `T` inside a struct carrier into a stub generic (`gx(mk1(x))`, `gx(b)` with `b: Box<T>`) is refused at its definition — RESOLVED

> ✅ **RESOLVED in v6.7.14** (GN-12 (`fe930ef3`): the stub scan's forwarding mode follows a callee's struct-carrier positions (`_gs_fwd_carr`: a carrier's name, or a generic call carrying T), so a forwarder into a stub generic through a struct carrier is a stub itself. The filed repro exits 12 (it was refused at outer's definition), and so do the `var b: Box<T>` local form and `outer<Pt>(p)`, on x86_64, aarch64, cx and PE; `outer(5)` is refused naming outer; a forwarder into a non-stub carrier generic keeps its i64 base (99, unchanged); the method spelling, `gx(mk1<T>(x))`, a nested `gx(wrap(b))` and two levels work too. Rows: `frontend/generic_type_arg_unknown_refused.sh` FC0 (the repro verbatim) – FC7; `crossos/generic_forward_tparam.tcyr` FC1 – FC8 on seven legs; mutations MFC1 – MFC3 RED. Filed, 6.7.15: a bare T-typed value in a stub's carrier position (`return gx(x);`) is still refused at the definition. CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-14 on the 6.7.11 genfe lane (l6711-genfe, unit G3, build/cycc 2,185,200 B)
and on unit G2's compiler (ed9456c1): both definitions below are refused at the definition, called or not ("generic
'gx' has no i64 (or other scalar) instance") — the forwarder's eagerly emitted i64 base meets the stub refusal. The
explicit spelling `outer<Pt>(p)` cannot help: the base is parsed first. `gx` itself became a stub in 6.7.11 (unit G2:
a carrier's `T` field read as a struct, `b.v.y`; before it its definition did not compile at all).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (generics lane, wave 1, unit G4; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Discovered:** 2026-10-14 by the 6.7.11 genfe lane, unit G3, while adding the row "a generic forwarding T through a
generic call's result" for issues/archived/2026-10-10-generic-call-result-as-carrier-argument-refused.md.
**Severity:** Low — a loud refusal of valid source; workaround: forward the `T` value itself
(`fn outer<T>(x: T) { return gy(x); }` with `gy` reading `x.y`) or give the forwarder a scalar-safe callee.
**Affects:** the 6.7.11 lane tree (units G2 / G3).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct Pt { x; y; }
struct Box<T> { v: T; n; }
fn mk1<T>(x: T): Box<T> { var b: Box<T>; b.v = x; b.n = 8; return b; }
fn gx<T>(b: Box<T>): i64 { return b.n + b.v.y; }
fn outer<T>(x: T): i64 { return gx(mk1(x)); }
fn go(): i64 {
    var p: Pt; p.x = 3; p.y = 4;
    return outer(p);
}
syscall(60, go());
```

```
expected: exit 12 (outer$Pt -> gx$Pt: 8 + 4), the base `outer` a stub as a direct forwarder `return gx2(x);` makes it
actual:   error:<source>:6:36: generic 'gx' has no i64 (or other scalar) instance: it uses its type parameter as a struct
          (a '.field' on a T-typed value, directly or in a generic it forwards T to) — pass a struct argument, or name a
          struct type argument
```

The carrier spelled as a local, `fn outer<T>(x: T): i64 { var b: Box<T> = mk1(x); return gx(b); }`, is refused the same
way (at 6:60). G2's compiler printed the first form's error twice; G3's prints it once.

## Root cause

The stub scan's forwarding mode (`_gs_use` mode 1, src/frontend/parse_fn.cyr) follows a T-TYPED NAME passed whole to a
stub generic (`gx2(x)`, and since 6.7.11 a method, `_gs_mfwd`). Neither a carrier name (`gx(b)` with `b: Box<T>`,
recorded by `_gcr_note` for mode 0 only) nor a generic call carrying T (`gx(mk1(x))`) is followed, so `outer` keeps an
i64 base, whose `gx(..)` binds T = i64 and is refused by name.

## Fix direction

Mode 1 counts a stub callee given a whole argument that carries the scanned fn's T: a recorded carrier name (the `_gcr`
table) in a carrier position, or a whole generic call whose argument carries it. Rows: the repro (12); the `var b:
Box<T>` local form; `outer<Pt>(p)`; a scalar `outer(5)` refused naming outer.

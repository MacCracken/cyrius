# A zone untyped `var y = b.idm(P);` — a GENERIC method returning its type parameter `: T`, bound to a struct — binds nothing (`y.a` is "no struct type in scope for 'y'") where after the first statement it binds the struct — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-20 on the 6.7.16 zone lane (l6716-zone, unit Z2, x86_64; the frontend is
shared), and identical on the lane base (f8139264f's compiler).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 zone lane, wave 2; placed at the wave-2 integration, 2026-10-20 — the user: what 6.7.16 finds is fixed in 6.7.16, "INTO .16") — never 7.x.
**Severity:** Low — valid code refused (no miscompile); the same line after the first statement works.
**Kind:** bug (the zone and after-the-first-statement typings disagree).
**Discovered:** by unit Z2 while landing issues/2026-10-18-zone-untyped-generic-method-generic-struct-result-binds-nothing.md
(a generic method returning a generic struct's INSTANCE, `: G1<T>`). A `: T` return is a different shape: the free
call's twin `var y = id(P);` binds (6.7.14, `_tok_gen_ret_sid`), the method's does not.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct Pt { a; }
struct B1 { a; }
struct S8 { a; }
impl B1 { fn idm<T>(self, v: T): T { return v; } }
var b = B1 { 1 };
var P = Pt { 33 };
var y = b.idm(P);
syscall(60, y.a);
```

```
error:<source>:9:16: no struct type in scope for 'y'; a '.field' access needs its struct declaration (missing include?)
```

With `var Z0 = 0; Z0 = 1;` before `var y` it builds and exits 33.

## Root cause

`_gz_chain`'s method arm types the step by the base method's return (`GFRS`), which for `: T` is no struct, so
`_gu_wsid` answers 0. A fix reads the `: T` binding at the method call as Z2's `_gu_minst` reads a `: G<..>` one
(`_gen_ret_tp` on the method, then the binding from `_mcall_infer` / the explicit list, no instance made).

# A declaration-zone `var G = if (c) { mkg1(P) } else { mkg1(P) };` (branches a generic call's generic struct instance) binds nothing — `G.v` is "no struct type in scope for 'G'", where after the first statement and in a fn it binds — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-20 on the 6.7.16 zone lane (l6716-zone, unit Z3, after the D16 commit; x86_64,
the frontend: every target).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 zone lane, wave 2; placed at the wave-2 integration, 2026-10-20 — the user: what 6.7.16 finds is fixed in 6.7.16, "INTO .16") — never 7.x.
**Severity:** Low — valid code refused at the global's first `.field` (rc 1, a clear message); nothing miscompiles.
**Kind:** language (the reach of 6.7.16's D16 (a) in the declaration zone).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct G1<T> { v: T; }
struct Pt { a; }
fn mkg1<T>(v: T): G1<T> { var g: G1<T>; g.v = v; return g; }
var P = Pt { 33 };
var G = if (1 == 1) { mkg1(P) } else { mkg1(P) };
syscall(60, G.v.a);
```

```
error:<source>:7:16: no struct type in scope for 'G'; a '.field' access needs its struct declaration (missing include?)
```

The same line after a first statement (`var Z0 = 0; Z0 = 1;` before `var G`) exits 33, and in a fn (`var p = Pt { 33
}; var g = if (1 == 1) { mkg1(p) } else { mkg1(p) }; return g.v.a;`) exits 33.

## Root cause

6.7.16's D16 (a) binds an untyped top-level if-expression of struct branches of 8 B or less. After the first statement
the binding comes from the parse's own record (`_gu_ierec`, src/frontend/parse_decl.cyr), which carries the instance the
branch's call made (`G1$Pt`). In the declaration zone it comes from the tokens (`_gu_ie`, from `_gu_wsid`): the first
branch reads (`_gz_ie` -> `_gz_bty` -> `_gz_chain` -> `_gz_call_rs`) as the generic struct's BASE `G1` (`_gz_gb`), not
the instance, so `_gu_ie` declines a generic struct base (binding the base would disagree with the replay's instance and
`_gz_agree` does not check a differing struct) and G stays untyped, as before 6.7.16. A whole generic call / method
initialiser resolves its instance through `_gu_gen` / `_gu_minst`; a branch does not.

## Fix direction

In `_gu_ie`, resolve a first branch that is one whole generic call (`_gu_gen` on its name token) or ends in a generic
method step (`_gu_minst`, the state `_gz_ty` left) to the instance, as `_gu_zsid` / `_gu_wsid` do for a whole
initialiser; rows zone and after on x86_64 / aarch64 / cx / PE.

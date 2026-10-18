# The explicit method spelling `v.m<..>(..)` escapes a bound's contract: a method no trait of the bound declares, called with type arguments on a bounded `T` (or a carrier's `T` field), compiles — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 by the 6.7.15 generics lane (unit G5) on the lane's tree at b71f8853a
(after D5 (a)), x86_64; the name form the same on the slot-open compiler.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 generics lane, wave 1; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
**Discovered:** 2026-10-18, 6.7.15 generics G5, implementing D5 (a) (the contract on a carrier's T field). The
contract's site scan keys a call by the exact tokens `name . name (` (and `name . f . name (` for the field form);
6.7.14's D7 (a) explicit spelling `x.m<..>(..)` puts `<..>` between the name and its `(`, so the scan never sees it.
**Severity:** Low — the contract's hole: such a generic compiles and calls the instance's own method (the
6.7.11 per-instance reading), where the inferred spelling is refused at the definition.
**Kind:** language — makes source that compiles today stop compiling (the user's D5 / 6.7.1 contract already says it
should be refused, so it is the contract's surface, but it is a newly refused shape).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
trait Show { fn show(self): i64; }
struct Pt { x; y; }
impl Show for Pt { fn show(self): i64 { return self.y; } }
impl Pt { fn other<V>(self, k: V): i64 { return 77; } }
struct Box<T> { v: T; n; }
fn gn<T: Show>(v: T): i64 { return v.other<i64>(1); }
fn gs<T: Show>(b: Box<T>): i64 { return b.v.other<i64>(1); }
fn go(): i64 { var p: Pt; p.y = 6; var b: Box<Pt>; b.v.y = 6; return gn(p) + gs(b); }
syscall(60, go());
```

```
actual:   exit 154 (Pt's own `other`, twice; no refusal)
compare:  the same file with `v.other(1)` / `b.v.other(1)`: error:<source>:7:38: method 'other' is not in the bound
          on type parameter 'T' (at the definition, called or not)
```

## Root cause

`_bnd_sites` (src/frontend/parse_fn.cyr) records a site for `recv.m(` only when `TOKTYP(S, i + 3) == 10`, and
`_bnd_fsite` only when `TOKTYP(S, i + 5) == 10`; `recv.m<..>(` has `<` (19) there. The parser's method arm takes the
explicit list (`_mx_take`, 6.7.14) and resolves the instance's own method.

## Fix direction

Accept `<..>(` after the method name in both scans (the list's end via `_targs_end` / `_mchain_targs`), so the
explicit spelling is checked, and consumed when refused, as the inferred one is. Rows: the repro refused twice
(once per definition); a bound's own generic member with explicit arguments unchanged.

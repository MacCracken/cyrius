# The explicit method spelling `v.m<..>(..)` escapes a bound's contract: a method no trait of the bound declares, called with type arguments on a bounded `T` (or a carrier's `T` field), compiles — RESOLVED

> ✅ **RESOLVED in v6.7.16** (GB-4, `f272ffabf` — the user's D4 (2026-10-19): refused at the definition, like the inferred spelling. The contract's site scan accepts a `<..>` list before the call's `(` (`_bnd_mopen`) when every name in it is a type, so `h(v.y < a, c > (1))` stays two comparisons. The filed repro (exit 154) is refused at 7:38 and 8:45, "method 'other' is not in the bound on type parameter 'T'", the notes naming 'v' and 'b.v', called or not; a bound's own generic member called with an explicit list keeps compiling, and at a scalar T now compiles (it was refused). Rows: `trait_bounds_checked.sh` BX0 (the filed repro verbatim) – BX8, BXK, BXU, BXS; `tests/tcyr/crossos/trait_bound_explicit_member.tcyr` (40 asserts, x86_64 / aarch64 / cx / PE); mutations MBX1 – MBX7 each RED. Met beside it, each its own commit and rows: `--syntax-only` / `cyrius lint` and a call in the chain of a sibling struct's receiver (GB-5 `b6ccc7a50`, its named-argument review fix GB-5r `498c32bd1`, the single-name call's chain GB-24 `58e3807b2`), a type-argument list on a non-generic fn or method refused once at its name (GB-6 `9ac212def`), a local of a sibling's struct under lint (GB-7 `69a6e0469`). Recorded residual (D4's "called or not" holds for a list of types): a list naming no type at all, `v.other<Nope>(1)` with Nope declared nowhere, is no site, so an UNCALLED such generic compiles; every call is refused, "unknown type 'Nope' as a type argument" (row BXU). CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-18 by the 6.7.15 generics lane (unit G5) on the lane's tree at b71f8853a
(after D5 (a)), x86_64; the name form the same on the slot-open compiler.
**Placement:** 6.7.16 — Break 2, repair 6 (genbind lane, wave 3, unit GB2; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Decision (user, 2026-10-19, at the 6.7.16 open):** D4 — Yes: refused at the definition, like the inferred spelling.
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

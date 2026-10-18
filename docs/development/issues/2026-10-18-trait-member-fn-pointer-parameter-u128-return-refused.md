# A trait member's `cb: *fn(i64): u128` parameter is refused "`u128` is not supported as a parameter type yet", where a fn's compiles — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 generics lane (unit G3), writing D3's control rows (a
member's `: u128` return refused, a `*fn( .. ): u128` type's own return unchanged). Pre-existing: identical on the
lane's compiler before G3 (373ab3d29), since 6.7.14's D10 (a) refused a member's `u128` parameter.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 generics lane, wave 1; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
**Severity:** Low — a valid trait member is refused; the same parameter on a fn compiles (no wrong code).
**Kind:** bug (a valid signature refused; 6.7.14's D10 (a) leaves "a `*fn(u128)`'s own list" unchanged, and a fn
pointer's own return is the same position).

## Reproduction

```cyrius
include "lib/fnptr.cyr"
struct P { x; }
trait T { fn e(self, cb: *fn(i64): u128): i64; }
impl T for P { fn e(self, cb: *fn(i64): u128): i64 { return fncall1(cb, 0); } }
fn k(x): i64 { return 3; }
fn main(): i64 { var p = P { 1 }; return p.e(&k); }
syscall(60, main());
```

```
$ build/cycc < fu2.cyr > fu2
error:<source>:3:36: `u128` is not supported as a parameter type yet - pass `*u128`
    trait T { fn e(self, cb: *fn(i64): u128): i64; }
                                       ^
```

The fn form compiles and runs: `fn ap(cb: *fn(i64): u128): i64 { return fncall1(cb, 0); }` with `ap(&k)` exits 3
(the parameter reader's `_pty_fn` reads the fn pointer's return with `inner` set).

## Root cause

`_trs_type` (src/frontend/parse_fn.cyr), at `*fn( .. )`, reads the list inside `_trs_inner` (`_trs_lvl` raised) but
the fn pointer's `: T` return after it at the caller's level, with the parameter's name `nm`: so `_trs_u128` sees a
parameter (`nm >= 0`), unstarred (`st == 0`), at level 0, and refuses it as the parameter's own type.

## Fix direction

Read the fn pointer's return under `_trs_inner` too (or pass a level), as `_pty_fn` reads it with `inner = 1`. Rows:
the repro (exit 3); a member's own `v: u128` parameter still refused (type_name_refused.sh `u128_trait`); a member's
`: u128` return still refused (6.7.15's D3).

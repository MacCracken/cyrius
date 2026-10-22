# A trait member's `cb: *fn(i64): u128` parameter is refused "`u128` is not supported as a parameter type yet", where a fn's compiles — RESOLVED

> ✅ **RESOLVED in v6.7.16** (GS-4, `d4a59f3e4` — no decision needed (6.7.14's D10 (a) leaves a `*fn( .. )`'s own types unchanged, and a fn's form compiles). `_trs_type` reads the fn pointer's `: T` a level in (`_trs_fnret`, `_trs_lvl + 1`), as a fn's parameter reader (`_pty_fn`, inner 1) does. The filed program, verbatim, exits 3 on x86_64, qemu-aarch64, cx and PE (it was refused at 3:36 as a `u128` parameter); a member's own `v: u128` and its `: u128` return (6.7.15's D3) stay refused, and a `v: u128` after such a parameter is reported at its own token (2:45; it was 2:36). Rows: `type_name_refused.sh` `u128_trait_fnret` (the filed program verbatim), `u128_trait_fnret_own`; `traits_checked.tcyr` `Ap.ap2`. Mutant: the lane's previous compiler → RED 2. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 generics lane (unit G3), writing D3's control rows (a
member's `: u128` return refused, a `*fn( .. ): u128` type's own return unchanged). Pre-existing: identical on the
lane's compiler before G3 (373ab3d29), since 6.7.14's D10 (a) refused a member's `u128` parameter.
**Placement:** 6.7.16 — Break 2, repair 6 (gensig lane, wave 2, unit GS2; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
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

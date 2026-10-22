# A generic trait member's own type parameter is "unknown type" anywhere after a `*fn(..)` in its signature (`fn g<U>(self, c: *fn(i64): i64, u: U): U;`) — RESOLVED

> ✅ **RESOLVED in v6.7.16** (GS-3, `be7156d69` — no decision needed (the same signature compiles on a plain generic fn). `_tn_sig_tparam` steps over a `fn` that follows a `*` (a fn-pointer type inside the signature, `_tn_fnptr_kw`) to the signature's own `fn`, at the shared resolver's root. The filed program, verbatim, exits 5 on x86_64, qemu-aarch64, cx and PE (it was `3:47: unknown type 'U' for parameter 'u'`); the `*fn`-last variant with a `: U` return and `cb: *fn(U): i64` exit 5 too; `u: Nope` after a `*fn(..)` (3:47) and a non-generic fn's `U` after one (2:27) stay refused once. Rows: `traits_checked.sh` TP1 (the filed program verbatim) – TP6; `tests/tcyr/crossos/traits_checked.tcyr` `Ap.ap`. Mutant: the lane's previous compiler → RED 3 (TP1 – TP3). CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 generics lane (unit G3), writing the control rows of the
trait-signature type-argument check (D7). Pre-existing: identical on the lane's compiler before G3 (373ab3d29) —
the reader has had this since 6.7.8 parsed a member's signature.
**Placement:** 6.7.16 — Break 2, repair 6 (gensig lane, wave 2, unit GS2; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Severity:** Low — a valid generic trait member is refused (no wrong code); the same signature on a plain generic
fn compiles.
**Kind:** bug (a valid signature refused; no language question).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct P { x; }
trait Sh { fn g<U>(self, c: *fn(i64): i64, u: U): U; }
impl Sh for P { fn g<U>(self, c: *fn(i64): i64, u: U): U { return u; } }
fn main(): i64 { var p = P { 1 }; return p.g(0, 5); }
syscall(60, main());
```

```
$ build/cycc < tp4.cyr > tp4
error:<source>:3:47: unknown type 'U' for parameter 'u'
    trait Sh { fn g<U>(self, c: *fn(i64): i64, u: U): U; }
                                                  ^
  note: a type is i8..i64, u8..u64, u128, f32, f64, bool, cstring, Result, Option, Tagged, Vec, an enum, a vector type, or a struct or union (a fn-local var also takes a slice [T] / slice<T>; missing include?)
```

With the `*fn` parameter last (`fn g<U>(self, u: U, c: *fn(i64): i64): U;`) the parameter `u: U` reads, and the
RETURN is refused: `error:<source>:3:51: unknown type 'U' as a fn return type`. A `U` inside the `*fn(..)` itself
(`c: *fn(U): i64`) is refused too (`3:34: unknown type 'U' for parameter 'cb'`). The same signatures on a plain
`fn g<U>(c: *fn(U): i64, u: U): U` compile (the fn path asks `_is_tparam_of(_cur_fn_ix, ..)`).

## Root cause

`_trs_name` (src/frontend/parse_fn.cyr) resolves a member's type name with `_tn_resolve_at` -> `_tn_tparam` ->
`_tn_sig_tparam` (src/frontend/parse_types.cyr), which walks BACK from the name to the nearest `fn` token and reads
that fn's `<..>`. A `*fn( .. )` type's own `fn` token is nearer than the member's, has no `<` after it, and answers
"not a type parameter". The member's `fn` token is known to the walker (`_tr_sig_check`'s `p`; 6.7.15's `_trs_fn`).

## Fix direction

Have the trait reader test the member's own list from its `fn` token (`_fn_tp_has(S, _trs_fn - 1, noff)`, added by
6.7.15's D7 for the type-argument read) before refusing a name, or make `_tn_sig_tparam` step over a `fn` that
follows a `*` (a fn-pointer type is not a signature). Rows: the repro (exit 5), the `*fn` last with a `: U` return,
`*fn(U): i64` itself, a non-generic member unchanged, and an unknown name after a `*fn(..)` still refused.

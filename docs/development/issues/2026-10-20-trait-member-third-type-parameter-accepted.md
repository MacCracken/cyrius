# A trait member's own third type parameter is accepted (`trait T { fn g<A, B, C>(..); }`) — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-20 by the 6.7.16 gensig lane (unit GS3), implementing 6.7.16's D8 (a third type
parameter is refused at its declaration, by name). Measured on the lane head after the D8 bite (cacd0ff68) and before it.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 gensig lane, wave 2; placed at the wave-2 integration, 2026-10-20 — the user: what 6.7.16 finds is fixed in 6.7.16, "INTO .16") — never 7.x.
**Severity:** Low — no value is computed wrongly that a fn would not refuse: an impl's method declaring the same three
parameters is refused by D8 at the impl, and a member with a default body is refused when the default is parsed. What
stays accepted is the member's own declaration, and an impl that declares fewer parameters for it.
**Kind:** language — the filed surface of D8 (issues/2026-10-18-third-type-parameter-accepted-and-unrecorded.md) is a
generic fn's and a generic struct's header (`_capture_tparams`); a trait member's signature is read by the trait
reader (`_tr_sig_check`, src/frontend/parse_fn.cyr), which skips its `<..>` (`d` loop near "`<..>` is skipped, as
PARSE_FN_DEF's SKIP_GENERICS does"). Whether a bodiless member's third parameter is refused too is the user's call:
it changes what compiles.

## Reproduction

The member alone:

```cyrius
trait T { fn g<A, B, C>(self, a: A, b: B, c: C): i64; }
struct P { x; }
fn main(): i64 { return 3; }
```

```
$ build/cycc < trm.cyr > trm && ./trm; echo $?
3           # compiles, no diagnostic
```

An impl declaring two parameters for the three-parameter member:

```cyrius
trait T { fn g<A, B, C>(self, a: A, b: B, c: C): i64; }
struct P { x; }
impl T for P { fn g<A, B>(self, a: A, b: B, c: i64): i64 { return 4; } }
fn main(): i64 { var p = P { 1 }; return p.g(1, 2, 3); }
```

```
$ build/cycc < trm2.cyr > trm2 && ./trm2; echo $?
4           # compiles, no diagnostic
```

For comparison, a default body is refused (it is parsed as a fn), once, at its `C`:

```cyrius
trait T { fn g<A, B, C>(self, c: C): i64 { return sizeof(C); } }
struct S3 { a; b; c; }
struct P { x; }
impl T for P { }
fn main(): i64 { var p = P { 1 }; var s = S3 { 1, 2, 3 }; return p.g(s); }
```

```
error:<source>:1:22: a third type parameter 'C': a generic takes at most two type parameters
    trait T { fn g<A, B, C>(self, c: C): i64 { return sizeof(C); } }
                         ^
```

## Root cause

The trait reader steps over a member's `<..>` without counting it (it never goes through `_capture_tparams`), and
the impl check (`_tr_check_impl`) compares parameter counts and return types, not type-parameter lists.

## Fix direction

If the user wants the member refused as a fn is: count the member's list in the trait reader (`_tp_count_at`, the
6.7.16 helper, counts as `_capture_tparams` does) and refuse its third name once with D8's line
(`_ctp_third`'s words). Rows: trm.cyr / trm2.cyr refused once at the member's `C`; a default body still once (not
twice); `<T: Show + Eq, U>` members unchanged.

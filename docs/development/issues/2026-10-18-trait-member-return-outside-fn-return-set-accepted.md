# A trait member's return type a fn's return refuses (`u8`..`u64`, `f32`, an enum, `*fn(..)`) still compiles at the trait — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 generics lane (unit G3), implementing D9 (a)
(issues/2026-10-16-trait-member-vec-return-accepted.md: a member's `: Vec<..>` return is refused at the trait with a
fn's words) and D3 (a) (`: u128`). Those two decisions name `Vec` and `u128`; the rest of a fn's return set was not
asked, so it is filed, not extended. Pre-existing since 6.7.8 parsed a member's signature.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 generics lane, wave 1; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
**Severity:** Low — the trait declares a method no impl can define (every impl spelled as the member says is
refused); no wrong code.
**Kind:** language (a newly refused shape: the user's call — D9's question was asked for `Vec` only).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct P { x; }
enum Color { Red, Green }
trait Sh { fn a(self): u8; fn b(self): f32; fn c(self): Color; fn d(self): *fn(i64): i64; fn e(self): u64; }
fn main(): i64 { return 4; }
syscall(60, main());
```

```
$ build/cycc < rv.cyr > rv && ./rv; echo $?
4
```

The same returns on a fn:

```
error:<source>:3:9: type 'u8' cannot be a fn return type
error:<source>:4:9: type 'f32' cannot be a fn return type
error:<source>:5:9: type 'Color' cannot be a fn return type
error:<source>:6:9: type 'u64' cannot be a fn return type
```

and `fn h(): *fn(i64): i64 { .. }` is `expected identifier, got reserved keyword 'fn' (cannot be used as an
identifier ...)` — a fn-pointer type is a parameter type (6.7.11), not a return type. An impl of the member
(`impl Sh for P { fn a(self): u8 { return 1; } }`) is refused at the impl: `4:29: type 'u8' cannot be a fn return
type`. tests/gates/frontend/traits_checked.sh V4 pins `fn d(self): *fn(i64): i64;` and `fn g(..): f64` as compiling
(f64 is in the set; `*fn(..)` is not).

## Root cause

`_tr_sig_check` (src/frontend/parse_fn.cyr) reads a member's return with `_trs_type` -> `_trs_name`, which accepts
every resolved type name; 6.7.15's `_trs_ret_refused` holds the return to a fn's set for `Vec` (D9) and `u128` (D3)
only. PARSE_FN_DEF's return reader takes `_classify_return_type`'s set plus bool, `*T`, a multi-value and a type
parameter, and refuses the rest by name (`_tn_ret_report`).

## Fix direction

If the user wants a member's return held to the whole set: `_trs_ret_refused` refuses a head name (no `*`) that
`_classify_return_type` does not take and that is not `bool`, `dyn ..` or the member's own type parameter, with
`_tn_ret_report`'s words; a `*fn( .. )` return by the fn's grammar error or a named refusal (then the fn's own
`: *fn(..)` message is worth naming too). V4's `*fn(..)` member moves with it. Rows: each shape refused once; `: i64`,
`: f64`, `: bool`, `: Pt`, `: *u8`, `: Result`, a member's own `: U` unchanged.

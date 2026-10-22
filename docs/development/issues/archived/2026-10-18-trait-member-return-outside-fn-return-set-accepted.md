# A trait member's return type a fn's return refuses (`u8`..`u64`, `f32`, an enum, `*fn(..)`) still compiles at the trait — RESOLVED

> ✅ **RESOLVED in v6.7.16** (GS-5, `00d27769b`, with GS-6 `f201704a2` and GS-5r `aff3849ff` — the user's decision D9, 2026-10-19 at the 6.7.16 open: refuse each at the trait, once, with a fn's words. `_trs_ret_refused` holds a member's return to a fn's whole return set. The filed rv.cyr, verbatim, is refused with exactly five lines, one per member, each with the fn's note — `type 'u8' cannot be a fn return type` (4:24), `'f32'` (4:40), `'Color'` (4:57), ``a fn-pointer type `*fn( .. )` cannot be a fn return type`` (4:76), `'u64'` (4:103) — on x86_64, qemu-aarch64, cx and PE (it exited 4). A `**fn( .. )` return gets the same line (beyond D9's text). Under `--syntax-only` the names are silent and the `*fn( .. )` line is reported, as a fn's are. An impl spelled `: i64` under such a member adds nothing beside the member's line, nor does a formed dyn (GS-5r); an impl method's own `*fn( .. )` return is its reader's one line (GS-6). Rows: `traits_checked.sh` TM1 (the filed program verbatim) – TM6, TR8c; `dyn_checked.sh` F8r1 – F8r4. Mutant: the lane's previous compiler → RED 8. Filed beside it (placed in 6.7.16, the f16 lane): a member's bare `cb: *fn` parameter is refused (D91), and a fn's own `: *fn( .. )` return is not named by its refusal (the filing's "worth naming too", which D9 did not ask). CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 generics lane (unit G3), implementing D9 (a)
(issues/archived/2026-10-16-trait-member-vec-return-accepted.md: a member's `: Vec<..>` return is refused at the trait with a
fn's words) and D3 (a) (`: u128`). Those two decisions name `Vec` and `u128`; the rest of a fn's return set was not
asked, so it is filed, not extended. Pre-existing since 6.7.8 parsed a member's signature.
**Placement:** 6.7.16 — Break 2, repair 6 (gensig lane, wave 2, unit GS2; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Decision (user, 2026-10-19, at the 6.7.16 open):** D9 — Refuse each at the trait, once, with a fn's words.
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

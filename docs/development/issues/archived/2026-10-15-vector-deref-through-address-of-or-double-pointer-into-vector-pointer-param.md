# A vector dereference through an address-of or a double pointer, `rd(*&b)` / `rd(**ppb)`, into a `*V` parameter still passes lane 0 as the address (D27's `*pv` rule misses an operand with no step word) — RESOLVED

> ✅ **RESOLVED in v6.7.13** (VC-11, `d9aa49ec`: no decision needed for `*&b` (the source names `b`); `**pps` follows D9 (a), the user's decision of 2026-10-15 (the structs lane), with 6.7.10's decision 6. The filed `rd(*&b)` and the struct analogue `take(**pps)` exit 42 on x86_64, IR=3, aarch64, cx and PE and on ecb, ach, pi and cass (they faulted: 139 / 139 / 139 / cx 253 / PE 5), as do `rd(*(&b))`, a parameter's, a capture's and a vector global's `*&x`, and `**pps` wrapped, as `*(*pps)`, and of a parameter, field, capture or global. The filed `rd(**ppb)` and `take(*&s)` already passed at the lane's base (the structs lane's D9 (a) and `*(&p)`) and are pinned here. `take(**ppq)` of another struct, `rd(*&f)` of another vector and `rp(*&b)` into another pointer kind are refused by name. Rows: `simd_pointer_param.sh` DR1-DR5, DRY1 / DRY2 / DRYw, DRS1 / DRSw, DRK; `simd_pointer_param.tcyr` `sp_drows` (11 rows); `struct_deref_whole_operand.tcyr` `d` rows (8); `struct_arg_type_refused.sh` D17 / D18; mutations M-DR1-M-DR3 RED. Filed beside it: a generic instance's `pp: **T` parameter (`take(**pp)` still 139), `ri(*&b)` into `*i64` (with D31's word-pointer class), and the pointer-to-pointer pin cap now counting structs. CHANGELOG [6.7.13])

**Status:** ✅ **RESOLVED in v6.7.13** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-15 on the 6.7.12 fixfirst lane (after D27, `2026-10-13-vector-value-into-pointer-parameter-passes-lane-bits.md`, which passes `pv` for `rd(*pv)`) and on the slot-open compiler (`7f57e532`, x86_64): each repro compiles with no diagnostic and faults — x86_64 139, x86_64 `CYRIUS_IR=3` 139, aarch64 (qemu) 139, cx 253 (a guest fault), PE (wine) 5. The struct analogues (`take(*&s)` / `take(**pps)` into `p: *P3`) fault the same way (139 / 139 / 139 / cx 252 / PE 5).
**Placement:** 6.7.13 — repair 3: struct values (vectors lane; re-placed at the 6.7.13 open, 2026-10-15) — never 7.x.
**Discovered:** 2026-10-15, the review of the 6.7.12 fixfirst lane (D27's `*pv` neighbours).
**Severity:** Medium — compiles clean and faults on every target, no diagnostic; the plain spellings (`rd(&b)`, `rd(b)`, `rd(pb)`, `rd(*pb)`) work.
**Affects:** every target; a `*` whose operand is an address-of (`*&b`, `*(&b)`) or a dereference (`**ppb`), into a `*V` parameter (and, for structs, into a `*S` parameter).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/simd.cyr"
fn rd(p: *f64v2): i64 { return load64(p); }
fn main(): i64 {
    var b: f64v2 = f64v2_make(42, 7);
    return rd(*&b);            # want 42
}
var rc = main();
syscall(60, rc);
```

```cyrius
include "lib/syscalls.cyr"
include "lib/simd.cyr"
fn rd(p: *f64v2): i64 { return load64(p); }
fn main(): i64 {
    var b: f64v2 = f64v2_make(42, 7);
    var pb: *f64v2 = &b;
    var ppb: **f64v2 = &pb;
    return rd(**ppb);          # want 42
}
var rc = main();
syscall(60, rc);
```

```
each, the fixfirst lane:  x86_64 139, IR=3 139, aarch64 139, cx 253, PE 5      (no diagnostic; 42 is right)
each, slot-open 7f57e532: x86_64 139
```

The struct analogues, the same outputs (cx 252):

```cyrius
include "lib/syscalls.cyr"
struct P3 { a; b; c; }
fn take(p: *P3): i64 { return p.c; }
fn main(): i64 {
    var s: P3; s.a = 1; s.b = 2; s.c = 42;
    return take(*&s);          # want 42; `var ps: *P3 = &s; var pps: **P3 = &ps; take(**pps)` the same
}
var rc = main();
syscall(60, rc);
```

## Root cause

D27's dereference arm (`_dlo_park` -> `_dlo_vec`, src/frontend/parse_expr.cyr) parks the pointer only when the
operand's step word names a vector: `_ps_vdesc(_pk_word(S))`. `&b` carries no step word (`_hl_psid` answers 0 for
`&x`, the `*(&p)` issue's root cause), and an inner `*` clears it (a dereference's result has SPSC 0, the `**T` issue's
root cause), so nothing is parked and the loaded lane 0 is pushed as the address. The struct arm (`_hl_psid` in
`_dlo_park`) misses the same two operands.

## Proposed fix

With the two open issues: type `&x` of a vector / struct local as its `*V` / `*S` (so `*&b` is `b`), and give `*pp` of a
`**V` / `**S` the inner pointer's step word (the `**T` issue's question, the user's call there). Rows beside
simd_pointer_param.sh R4 / Y11 and the 6.7.10 decision-6 rows, on x86_64 / IR=3 / aarch64 / cx / PE.

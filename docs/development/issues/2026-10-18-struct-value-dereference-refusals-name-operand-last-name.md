# A struct VALUE dereference refused by its struct is named by its operand's last name — `ri(*gps(&s))` '*s', `take8(*gu(pu))` 'pu', `return *gu(pu);` '*pu', `var s: S8 = *h.pu;` 'pu' — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 vectors lane (unit V4), landing
issues/2026-10-17-vector-dereference-refusal-names-operand-last-name.md: that fix names a refused dereference argument as
the source spells it in `_sarg_vdo` (a `*V` into another pointer kind) and `_dro_check` (the address-passed arm:
`rp(*gq(pq))` now '*gq(pq)', `rp(*pq)` '*pq'), through the new `_src_span_nm` (src/frontend/parse_fn.cyr). The struct
VALUE arms read a different name: `_ess_deref` (parse_fn.cyr; the by-value struct of 8 B or less, the small-struct
return, `_sarg_sval_ptr`'s refusal into another pointer kind) and `_hl_dstar` / `_hl_dnm` (parse_decl.cyr; a declaration
or assignment of another struct) both quote `_hl_lastnm`. Diagnostics only; every target alike (the frontend's text).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 vectors lane, wave 2; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
**Severity:** Low — the right statement is refused once, at the right column; the quoted operand is not the source's,
and two of the four drop the `*` the argument starts with.
**Kind:** bug (diagnostic wording).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct Pt { x; y; }
struct U8 { u; }
struct S8 { s; }
struct H { k; pu: *U8; }
fn ri(p: *i64): i64 { return *p; }
fn take8(s: S8): i64 { return s.s; }
fn gps(p: *Pt): *Pt { return p; }
fn gu(p: *U8): *U8 { return p; }
fn f1(): i64 { var s: Pt; return ri(*gps(&s)); }
fn f2(): i64 { var u: U8; var pu: *U8 = &u; return take8(*gu(pu)); }
fn f3(): S8 { var u: U8; var pu: *U8 = &u; return *gu(pu); }
fn f4(): i64 { var u: U8; var h: H; h.pu = &u; var s: S8 = *h.pu; return s.s; }
syscall(60, f1() + f2());
```

```
$ build/cycc < e1.cyr > e1      (the vectors lane at unit V4; x86_64, aarch64, cx, PE alike)
error:<source>:10:37: cannot pass '*s' to a parameter that is not a pointer to its struct type in a call to 'ri' - a struct value is no address
error:<source>:11:65: cannot pass 'pu' to a parameter of a different struct type in a call to 'take8'
error:<source>:12:51: a fn returning the struct `S8` takes a value of that struct, or a pointer to one — got `*pu` (a `U8`)
error:<source>:13:58: cannot copy 'pu' into a variable of a different struct/vector type: 's'
```

Expected, as the address-passed arm prints since the vectors-lane fix: '*gps(&s)', '*gu(pu)', `*gu(pu)`, '*h.pu'.
The rows that pin today's words: struct_arg_type_refused.sh V4 V7 V11 (`'\*pp'`, `'\*\*pp'`, `'\*gps'`) and D3-D5 (the
6.7.11 "named by its last name" rows), small_struct_return_type_refused.sh's dereference rows.

## Root cause

`_ess_deref` sets `_ess_nm = _hl_lastnm(S, a + 1, pe, ..)` (read by `_sarg_type_errf`, `_sval_kind_err` with its `*`
count, and `_ret_sid_refuse` kind 2), and `_hl_dstar` sets `_hl_dnm` the same way (read by `_AGG_ASSIGN_TYPE_ERR` /
`_fsc_type_err` callers and `_ret_ptr_src`). `_sarg_type_errf` and the declaration's copy refusal print the name with
no `*`.

## What a fix needs

The same renderer the vector fix added: `_src_span_nm(S, a, pe, <the last name>)` over the dereference's tokens —
including its `*`s where the printer adds none, the operand alone where it prints its own (`_sval_kind_err`'s `star`,
`_ret_sid_refuse`'s kind 2). The span's scratch sits at GNPOS + 1024, clear of `_fn_src_name`'s, so a method callee
(`t.take8(*gu(pu))`) prints both names. Rows above move to the source spelling, on x86_64 / aarch64 / cx / PE.

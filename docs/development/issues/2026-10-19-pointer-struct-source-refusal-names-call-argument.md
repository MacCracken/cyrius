# A `*T` struct source that is no dereference is refused naming its last name, a call's ARGUMENT — `l = gq(&q)` 'q', `o.s = gq(&q)` 'q', `return gq(&q);` `q` — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-19 by the 6.7.16 structs lane (unit S5) while landing
issues/2026-10-18-struct-value-dereference-refusals-name-operand-last-name.md, which names every refused struct VALUE
DEREFERENCE as the source spells it (`l = *gq(&q)` is now '*gq(&q)'). The twin shape with no `*` — a `*Q3` source
copied into a struct of another type (`_hl_psrc` / `_hl_pnm`, and the small-struct pointer return `_hl_pnm`) — still
quotes the chain's last identifier, which for a call with arguments is an argument's name, not the source's. Not that
issue's filed surface (no dereference), so filed, not fixed. Pre-existing: the same output on the lane's compiler
before S5 (45135d7db) and after it (x86_64; the frontend's text, every target alike).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 structs lane, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16"; s16 lane, wave 4, unit SS1) — never 7.x.
**Severity:** Low — the right statement is refused once, at the right column; the quoted name is an argument
(`'q'`), which reads as if the variable q were the source.
**Kind:** bug (diagnostic wording).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct Q3 { a; b; c; }
struct P3 { x; y; z; }
struct O { s: P3; n; }
struct H { k; pq: *Q3; }
fn gq(p: *Q3): *Q3 { return p; }
fn f1(): i64 { var q: Q3; var l: P3; l = gq(&q); return l.x; }
fn f2(): i64 { var q: Q3; var o: O; o.s = gq(&q); return o.n; }
fn f3(): i64 { var q: Q3; var h: H; h.pq = &q; var l: P3; l = h.pq; return l.x; }
fn f4(): P3 { var q: Q3; return gq(&q); }
syscall(60, f1());
```

```
$ build/cycc < ps.cyr > ps          (rc 1)
error:<source>:7:48: cannot copy 'q' into a variable of a different struct/vector type: 'l'
error:<source>:8:43: cannot copy 'q' into a struct field of a different struct type: 's'
error:<source>:9:67: cannot copy 'pq' into a variable of a different struct/vector type: 'l'
error:<source>:10:33: a fn returning the struct `P3` takes a value of that struct, or a pointer to one — got `q` (a `*Q3`)
```

Wanted (by the rule 6.7.15 / 6.7.16 apply to arguments and dereferences): the source as written — 'gq(&q)' (or the
callee, 'gq', as a by-value call result is named: `ri(mk())` 'mk'), 'h.pq' (or 'pq').

## Root cause

`_hl_psrc` (src/frontend/parse_decl.cyr) sets `_hl_dnm = _hl_pnm(S, a, e)`, and `_hl_pnm` takes `_hl_lastnm` of the
chain — the last identifier token in it, which inside `gq(&q)` is the argument `q`. The same `_hl_pnm` names the
small-struct pointer return (`_ret_small_ptr`, `_ret_ptr_src`'s pointer arm, src/frontend/parse_fn.cyr). The readers:
`_hl_psrc_copy` (src/frontend/parse.cyr), `_fsc_psrc`, `_ret_small_ptr` / `_ret_ptr_src`.

## Fix direction

Name the source as written (`_src_span_nm` over [a, e), rendered at the refusal, as 6.7.16's `_hl_dname` does for a
dereference), or by the callee for a call; re-pin the rows that quote the last name (struct_copy_type_checked.sh,
small_struct_return_type_refused.sh's pointer rows) on x86_64 / aarch64 / cx / PE.

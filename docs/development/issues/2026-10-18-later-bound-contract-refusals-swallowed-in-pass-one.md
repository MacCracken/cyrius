# Only the first bound-contract refusal of a compile prints: every later "method 'm' is not in the bound on type parameter 'T'" (another generic, or the same body) is swallowed by the first's panic latch — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 by the 6.7.15 generics lane (unit G5) on the lane's tree at b71f8853a, x86_64;
the same on the slot-open compiler (whose later refusals printed their notes alone — the orphan notes were removed by
b71f8853a, `_bnd_site_refuse` behind `_err_quiet`).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 generics lane, wave 1; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
**Discovered:** 2026-10-18, 6.7.15 generics G5, implementing D5 (a) (a carrier field's call held to the bound): the
contract is checked in pass 1 (`_bnd_sites`, src/frontend/parse_fn.cyr), whose refusals go through ERR_IDENT, which
sets the panic latch; nothing in pass 1 resyncs it, so every later contract refusal of the compile is swallowed
until pass 2's first statement resync.
**Severity:** Low — every such input is still refused (rc 1, no binary); the user sees one of N independent errors per
build, and fixes them one compile at a time.
**Kind:** diagnostics.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
trait Show { fn show(self): i64; }
struct Pt { x; y; }
impl Show for Pt { fn show(self): i64 { return self.y; } }
impl Pt { fn other(self): i64 { return 77; } }
fn g1<T: Show>(v: T): i64 { return v.other(); }
fn g2<T: Show>(v: T): i64 { return v.other(); }
fn go(): i64 { return 3; }
syscall(60, go());
```

```
actual:   error:<source>:6:38: method 'other' is not in the bound on type parameter 'T'
            fn g1<T: Show>(v: T): i64 { return v.other(); }
                                                 ^
            note: a bound is the contract for a bounded type parameter - call only its traits' methods on 'v', or add a trait that declares this one to the bound
          (rc 1; nothing for g2's line 7)
expected: the same error for g2 at 7:38 too (two independent definitions, two errors), as a pass-2 error after it
          prints (`fn go(): i64 { var k = 1 2; ...}` placed between them prints its "expected ';'" below g1's)
```

The same in one body: `fn gm<T: Show>(b: Box<T>): i64 { var r = b.v.other(); b.v.other(); return r; }` prints only
the first; and the ambiguous refusal ("ambiguous method 'show': more than one trait ... declares it") is swallowed
the same way after any earlier contract refusal.

## Root cause

`_bnd_site_refuse` (src/frontend/parse_fn.cyr) reports with `_bnd_err_at` -> ERR_IDENT -> `_err_once`, which returns
0 while `_panic == 1`; the first refusal sets `_panic` and pass 1 (`_bnd_fn_record` -> `_bnd_sites`, once per
definition) never clears it. G3's trait checks (`_tr_check_impl`) print with no panic latch for this reason.

## Fix direction

Report the contract's refusals latch-free (save `_panic`, clear it, report, restore — or an `_err_dup`-keyed writer as
ERR_UNDEF), so each definition's refusal prints once; keep the call consumed quietly (`_bs_add(.., -1, ..)`). Row:
the repro above prints two errors and two notes.

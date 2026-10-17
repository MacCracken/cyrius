# A fn that returns a `: stack` pair only through `?` is not a pair to a caller ABOVE it: `qb(x)?` SIGSEGVs, `var v = qb(x);` binds the tag — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-15 by the 6.7.13 tools lane (unit T1) while giving `cyrius header` the `?`
route (issues/archived/2026-10-15-cyrius-header-misses-a-pair-propagated-by-question-mark.md): the header's file-local fixpoint
refuses `qa` below, and cycc's own "bind both" oracle disagreed for exactly the fn whose pair callee is defined after
it. Measured with the slot-open compiler (build/cycc at b13d3598) on x86_64 and with the tree's cycc_aarch64 under
qemu-aarch64.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (receives + multi-value lane, wave 2, unit R5; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Severity:** High — valid `?` code compiles clean and crashes at run time with no diagnostic (rc 139 on x86_64 and
aarch64), and the single bind keeps the tag in silence where the same program with the definitions swapped is refused
"bind both". The same class as issues/archived/2026-10-14-pair-trait-default-method-used-above-its-trait-not-flagged.md (a trait
default method) and the archived 2026-10-10-pair-method-defined-after-use-not-flagged.md (impl methods, D23), for a
plain top-level fn whose ONLY pair route is a `?`.
**Affects:** cycc since `?` learned the pair form (v6.6.0), every target (the pair flag is shared frontend state).

## Reproduction

`fwd.cyr`:

```cyrius
include "lib/result.cyr"
fn parse(x): Result { if (x > 0) { return Ok(x * 2); } return Err(0 - x); }
fn qa(x) { var v = qb(x)?; return v; }
fn qb(x) { var v = parse(x)?; return v; }
var z = qa(5);
syscall(60, z);
```

```
$ build/cycc < fwd.cyr > fwd && ./fwd; echo $?
warning:<source>:4:31: `qb` returns a `: stack` pair on another path but a SINGLE value here — …
139                                   (aarch64, qemu: 139 — uncaught target signal 11)
```

With `qb` defined ABOVE `qa` the same program builds and exits 10 (qa's own mixed-return warning aside).

`fwd2.cyr` — the single bind, qb below qa:

```cyrius
include "lib/result.cyr"
fn parse(x): Result { if (x > 0) { return Ok(x * 2); } return Err(0 - x); }
fn qa(x) { var v = qb(x); return v; }
fn qb(x) { var v = parse(x)?; return v; }
var z = qa(0 - 3);
syscall(60, z);
```

```
actual:   rc 0 from cycc (qb's mixed-return warning only); ./fwd2 exits 1 — the Err TAG bound as the value
expected: refused, as it is with qb above qa:
          error:<source>:5:18: a `: stack` enum returns two values — bind both: `var tag, val = f();`
```

## Root cause

A fn becomes pair-returning (fn flag 256) three ways: `return Ctor(..)` / `return pairfn(..)` (PARSE_RETURN), and a `?`
on a pair call (the `?` lowering in src/frontend/parse.cyr and parse_expr.cyr, `SFLG(.., | 256)`). Only the first two
are seen BEFORE pass 2 reaches the fn's body: `_pair_prescan` / `_pair_body_scan` (src/frontend/parse.cyr) follow
`return f(..)` alone. So qb is flagged only when its body is parsed, and every caller above it reads `qb(..)` as one
value — `qb(x)?` takes the boxed path (`_tpair` 0) and dereferences the returned word as a Result pointer.

## Proposed fix

`_pair_body_scan` also answers 1 for a `?` whose call is pair-returning (`_tok_q_is_pair`, which the mixed-return pass
already uses with final flags), inside the same rounds, closure and nested-fn bodies skipped as now. Rows: both repros
above (x86_64, aarch64 qemu, cx, PE wine — the flag is frontend state), each in both definition orders.

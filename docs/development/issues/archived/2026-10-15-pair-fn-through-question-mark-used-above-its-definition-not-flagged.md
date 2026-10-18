# A fn that returns a `: stack` pair only through `?` is not a pair to a caller ABOVE it: `qb(x)?` SIGSEGVs, `var v = qb(x);` binds the tag — RESOLVED

> ✅ **RESOLVED in v6.7.14** (RC-15, `c4930b46` + `9245e108` + `0d0a054d`, and RC-22, `7920bf35` — no decision needed: definition order must not change the verdict: `_pair_body_scan` answers 1 for a `?` on a pair call (`_tok_q_is_pair`) inside `_pair_prescan`'s rounds, for free fns, impl methods, inherited trait defaults and dyn slots. fwd.cyr (exit 139 / 139 / 10 / 5) is refused "bind both" at its single bind `var z = qa(5);` (5:7) and fwd2.cyr (exit 1) at 3:18, as with qb above — on x86_64, aarch64, cx and PE; a forward `qb(x)?` chain propagates the Err pair (13); a dyn formed above an impl whose slot's only route is `?` is refused by the 6.7.8 dyn pair check. The issue's "with qb above it builds and exits 10" was stale: that order was already refused. RC-22 keeps a closure's own `?` in an expression body (`var f = |a| parse(a)?;`) the closure's — a regression of RC-15 inside the release. Rows: `frontend/stack_enum_lossy_context.sh` axis QF (QF1 / QF2 the repros verbatim, `docs/development/issues/repros/2026-10-15-pair-fn-through-question-mark-used-above-its-definition-not-flagged{,-single-bind}.cyr`; QF3 – QF12) on four legs; NEW `crossos/pair_question_forward.tcyr` (5 / 5 also on pi, ecb, ach and cass); mutations RED. Not closed here (filed, 6.7.15): the mixed-return warning skips impl methods (`2026-10-17-mixed-pair-return-warning-skips-impl-methods.md`). CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — found 2026-10-15 by the 6.7.13 tools lane (unit T1) while giving `cyrius header` the `?`
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

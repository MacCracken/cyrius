# A multi-value method call on a field-chain receiver is refused as a destructure source: `var c, d = w.p.m2();` is "multi-value destructure needs a call on the right-hand side" — OPEN

**Status:** 🟡 **OPEN** — found by the 6.7.16 wave-3 genbind review, 2026-10-20.
**Placement:** 6.7.16 — Break 2, repair 6 (found by the 6.7.16 wave-3 genbind review; placed at the wave-3 integration, 2026-10-20 — every find of 6.7.16 is fixed in it; s16 lane, wave 4, unit SZ7) — never 7.x.
**Severity:** Medium — valid cyrius refused (rc 1); documented as a limit since 6.6.16, never a decision.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct P { k; }
struct W { p: P; }
impl P { fn m2(self): (i64, i64) { return (3, 4); } }
fn main(): i64 { var w: W; var c, d = w.p.m2(); return c * 10 + d; }
syscall(60, main());
```

rc 1, "multi-value destructure needs a call on the right-hand side"; the same for a generic method (`w.p.mm(h)`, `w.p.mm<f64>(h)`). `var p = w.p; var c, d = p.m2();` returns 34.

## Root cause

Every pair / multi-value asker's lookahead (`_pair_callee_at`, `_tok_method_open`, `_mcall_open`, src/frontend/parse.cyr) types only a single-name receiver.

## Acceptance

The repro returns 34 on every target; the destructure, `?`, the lossy-bind refusals and tuple capture take a field-chain receiver's multi-value method as they take a single-name receiver's. No decision: a compiler failing valid cyrius is fixed (a day-plus repair, folded into 6.7.16 by the user's rule).

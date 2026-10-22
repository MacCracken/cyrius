# A multi-value method call on a field-chain receiver is refused as a destructure source: `var c, d = w.p.m2();` is "multi-value destructure needs a call on the right-hand side" — RESOLVED

> ✅ **RESOLVED in v6.7.16** (SB-1, `7cdce3aa1`, with its follow-up SB-4 `ed17925c9` and the review fixes SB-4r `ca9e73061`, SB-1r `cd9d77e02`, SB-1r2 `8f484834d`, SB-1r3 `37bde68f1`, SB-1r4 `891683647` and SB-4r2 `d21d3a9bb` — no decision needed (a compiler failing valid cyrius is fixed, as filed; SB-1r4's single-name change is within 6.7.16's D42, the user 2026-10-19: "Both spellings compile, refuse and run alike"). `_mcall_open` answers a chain's last method (`_mco_chain` -> `_mch_open`; from the unit's tokens in the token passes), typing every step from its template and minting no instance (an inferred, explicit, `: V` / `: *V` / `: G<V>` generic step by a peek of its binding), and every pair / multi-value asker reads it. The filed repro, verbatim, exits 34 on x86_64, IR=3, aarch64 (qemu), cx (cxvm) and PE (wine) (it was rc 1, "multi-value destructure needs a call on the right-hand side"); `w.p.mm(h)` and `w.p.mm<f64>(h)` destructure too. On every receiver the method arm takes — a field chain through an inline or `*P` field at any depth, a `*W` parameter, `self`, a global, a closure's capture, a method's or a call's result, `callptr(&f, ..)`, a parenthesised head, a generic step or generic call head — the destructure and re-assignment, a tuple capture (a re-assignment on a parenthesised head too), a 9-16 B struct destructured, `?` (it took the boxed `?`: SIGSEGV), a forwarder below its caller, the dropped-tag warning (a false one on `return w.p.rs(4);` gone), a `*T` method as a dyn source and both top-level zones read the chain; the lossy-bind refusals ("bind both": each kept the tag in silence) and the multi-value-into-a-struct refusals (a field, a `: Q8` or async return: each stored the first value) take it as the single name's, with the receiver spelled as written in the hint. Met while landing it: SB-2 (`df29930ab`, a `callptr(..)` chain as a by-value struct argument passes the struct — it crashed on every target) and SB-3 (`4a790ef3c`, a struct over 8 B returned from a chain's method — it was refused). Rows: `tests/tcyr/crossos/method_receiver_chain_lookaheads.tcyr` (96 rows) on x86_64 plain / IR=1 / IR=3 / DCE=1, aarch64, cx and PE, and in the ecb / ach / cass / pi crossos legs; `tests/gates/frontend/method_receiver_chain_lookaheads.sh` (607 rows: R0 the repro verbatim on five legs, C1 – C24 each refusal word for word as the single name's on 15 receiver modes, W the warning, F1 – F3 a forwarder below its caller, X1 / X2 a lookahead minting nothing under `CYRIUS_COVERAGE=1`; mutations M0 – M22 each RED). Still refused, as the method arm refuses its `.field`: a generic step whose argument is itself a generic call (`q.idv(q.idv(q)).m2()`). Staged beside it, the user's decision: a `: stack`-pair fn through `callptr(&f, ..)` / `fncallN(&f, ..)` is no pair. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found by the 6.7.16 wave-3 genbind review, 2026-10-20.
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

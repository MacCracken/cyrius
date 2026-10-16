# An undeclared `async fn` that says `return h();` of a multi-value call still drops the second value — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-14 on the 6.7.11 returns lane (l6711-returns, unit R4, with
`2026-10-09-async-fn-multi-value-return-loses-second-value.md` repaired) on x86_64, aarch64 (qemu), cx (cxvm) and PE
(wine), `CYRIUS_ASYNC=1`: the repro builds clean and exits 19 on all four (12 or a refusal is right).
**Placement:** 6.7.13 — repair 3: struct values (multivalue lane; re-placed at the 6.7.13 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.13 open):** D24 — A.
**Severity:** High — the same silent value loss the parent issue refused: a Future carries one i64.
**Discovered:** 2026-10-14, the 6.7.11 returns lane (unit R4). The parent issue's decision (A, 2026-10-13) refuses
`async fn g(): (i64, i64)` at its declaration and `return (a, b[, c]);` / `ret2(a, b)` in an undeclared async body.
A `return h(..);` that FORWARDS a multi-value call is a third body spelling, outside that issue's filed surface.

## Reproduction

```cyrius
include "lib/alloc.cyr"
include "lib/fnptr.cyr"
include "lib/async.cyr"
fn h2(): (i64, i64) { return (1, 2); }
async fn g() { return h2(); }
fn h(): (i64, i64) { return (7, 9); }
fn main(): i64 {
    alloc_init();
    var f = g();
    var a0 = await f;
    var x, y = h();
    var a = await f;
    var b = rethi();
    return a * 10 + b;
}
syscall(60, main());
```

```
CYRIUS_ASYNC=1: builds clean, exits 19 on x86_64 / aarch64 / cx / PE (the memoised 1, then h's 9 from rethi())
```

The undeclared callee `fn h2(a) { return (a, 2); }` (pass 1 counts it 2 values, `_fn_ret_arity`) gives 19 as well.
`return (1, 2);` and `ret2(1, 2)` in the same body are refused since 6.7.11 ("`async fn g` returns 2 values, and a
Future carries one i64 - return a pointer to a struct holding them").

## Root cause

`_refuse_async_mv_body` (src/frontend/parse_fn.cyr, 6.7.11) is reached from PARSE_RETURN's multi-value literal
(`_async_mv_ret`) and the `ret2` builtin. A `return h2();` takes the tail-call arm (or the plain expression path), and
its callee's value count — declared (`GFRS == MULTIRET_SID`, `GFRN`) or recorded in pass 1 (`_fn_ret_arity`) — is never
asked. The fix is the same refusal at the forwarded call when its callee returns several values (R1's `_mret_fwd_ok`
already answers "how many values does this forwarded callee return").

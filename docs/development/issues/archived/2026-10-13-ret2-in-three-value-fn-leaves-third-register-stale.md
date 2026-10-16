# `ret2(a, b)` in a fn declared `: (i64, i64, i64)` leaves the third value stale — RESOLVED

> ✅ **RESOLVED in v6.7.13** (MV-10 (the user's decision D21, 2026-10-15: A, refused by name, as 6.7.11's D17): `ret2(a, b)` in a fn declared `: (T1, T2, T3)` is refused "'f' returns 3 values - return (a, b, c)". This is how a two-value `return (a, b);` is refused there; it is reported once (a generic's instances) and in sync. The filed repro exited 88 (a stale third register) on x86_64, aarch64, cx and PE. It is refused at 2:28 on all four, and under `CYRIUS_MACHO=1`. `return ret2(..);` there is refused once too. In a fn declared `: (T1, T2)` ret2 still runs (15), as does a closure's own ret2 inside a 3-value fn (57). Rows: `diagnostics/destructure_one_value_refused.sh` axis 5 (ret2_in_3 the repro verbatim, ret2_in_3_gen, ret2_in_3_next, return_ret2_in_3, ret2_in_2, ret2_closure_in_3); mutations MR3a – MR3c RED. CHANGELOG [6.7.13])

**Status:** ✅ **RESOLVED in v6.7.13** (see the banner). Was: 🟡 **OPEN** — reproduced 2026-10-13 on the 6.7.11 returns lane (l6711-returns, after the
declared-return repair) on x86_64, aarch64 (qemu), cx (cxvm) and PE (wine): the repro builds and exits 88.
**Placement:** 6.7.13 — repair 3: struct values (multivalue lane; re-placed at the 6.7.13 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.13 open):** D21 — A.
**Severity:** Medium — silent garbage in a binding.
**Discovered:** 2026-10-13, the 6.7.11 returns lane (unit R1), while repairing
`2026-10-09-multi-value-receive-reads-stale-return-registers.md`, whose decision (A, 2026-10-13) refuses every
`return` statement of a declared multi-value fn that does not write its values. `ret2` is a builtin statement,
not a `return`, so it is outside that issue's filed surface and is filed here.

## Reproduction

```cyrius
fn h(): (i64, i64, i64) { return (1, 77, 88); }
fn f(x): (i64, i64, i64) { ret2(x, x + 1); }
fn main(): i64 { var x, y, w = h(); var a, b, c = f(5); return c; }
var r = main(); syscall(60, r);
```

```sh
cat repro.cyr | build/cycc > /tmp/r && chmod +x /tmp/r && /tmp/r; echo $?
```

Exits 88 on x86_64, aarch64 (qemu), cx and PE (wine): `ret2` writes rax:rdx, and the caller's `c` reads the 88
an earlier call left in the third register. No diagnostic.

## Root cause

The `ret2` builtin (`src/frontend/parse_expr.cyr`, its `_mret_land` call) does not consult the enclosing fn's
declared arity (`_cur_fn_ret_scalar == MULTIRET_SID`, `GFRN`). Declared arity 2 matches it; arity 3 does not.

## Proposed fix

Refuse `ret2` in a fn declared with three values by name ("'f' returns 3 values - return (a, b, c)"), the
6.7.11 declared-return rule applied to the legacy builtin. A row in
`tests/gates/diagnostics/destructure_one_value_refused.sh` axis 5.

# A fn declared `: (T1, T2[, T3])` that can fall off its end hands the caller stale registers — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-13 on the 6.7.11 returns lane (l6711-returns, after the
declared-return repair) on x86_64, aarch64 (qemu), cx (cxvm) and PE (wine): the repro builds and exits 77.
**Placement:** 6.7.12 — repair 2 (filed from the 6.7.11 returns lane) — never 7.x.
**Severity:** Medium — silent garbage in a binding, the same symptom as the declared-return shapes 6.7.11 refused.
**Discovered:** 2026-10-13, the 6.7.11 returns lane (unit R1), while repairing
`2026-10-09-multi-value-receive-reads-stale-return-registers.md`. That repair (the user's decision A, 2026-10-13)
refuses every `return` statement in a declared multi-value fn that does not write its values; a body with no
final `return` is not a return statement, so it is outside that issue's filed surface and is filed here.

## Reproduction

```cyrius
fn h(): (i64, i64, i64) { return (1, 77, 88); }
fn f(x): (i64, i64) { if (x > 0) { return (1, 2); } }
fn main(): i64 { var x, y, w = h(); var a, b = f(0); return b; }
var r = main(); syscall(60, r);
```

```sh
cat repro.cyr | build/cycc > /tmp/r && chmod +x /tmp/r && /tmp/r; echo $?
```

Exits 77 on x86_64, aarch64 (qemu), cx and PE (wine): `f(0)` runs off the end of its body, and the caller's `b`
reads the 77 an earlier call left in the second return register. No diagnostic.

## Root cause

PARSE_FN_DEF emits no check that a body declared `: (T1, T2[, T3])` cannot reach its closing `}`. 6.7.11's
`_mret_ret_check` (`src/frontend/parse_fn.cyr`) judges each `return` statement; the fall-through path has none.
The pass-1 proof `_body_ends_in_return` (a final `return`, or an infinite loop no `break` leaves) already answers
"can this body fall off its end?" for undeclared fns.

## Proposed fix

A decision for the user (it stops code that compiles today): refuse a declared multi-value fn whose body is not
provably left only through its returns (`_body_ends_in_return` == 0) by name — "'f' returns 2 values, and its
body can end without a `return`" — or define the fall-off value. Rows in
`tests/gates/diagnostics/destructure_one_value_refused.sh` axis 5.

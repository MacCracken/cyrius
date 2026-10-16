# A fn declared `: (T1, T2[, T3])` that can fall off its end hands the caller stale registers — RESOLVED

> ✅ **RESOLVED in v6.7.13** (MV-17 (the user's decision D28, 2026-10-15: C, every value is 0 off the end, the pair to a bool fn's `false`): a fn declared `: (T1, T2[, T3])` whose body reaches its closing `}` without a `return` returns 0 for every value. rax, rdx[, r3] are zeroed on the fall-through path only (`_mret_falloff`, and `_mret_falloff_fi` for an `#inline` replay of such a callee); every `return` is untouched and nothing is refused. The filed repro read the seeded 77 on x86_64, aarch64, cx and PE and now reads 0 on all four. Three values give 0s; a defer, an f64 pair, a method, a generic, an `#inline` replay, an empty body and `rethi()` after it give 0 too. An if / else that returns on both paths is unchanged (34). Rows: `crossos/multi_return.tcyr` section 9 (23 assertions, 306 / 306 crossos on ecb / ach / cass / pi; cx through `codegen/cx_auto_call_main.sh` T2) and `diagnostics/destructure_one_value_refused.sh` axis 5 (fall_off_2 the repro verbatim, fall_off_3, fall_off_defer, fall_off_f64, fall_off_inline, fall_off_taken, ifelse_both_return, loop_end_declared); mutations m1 / m2 RED. CHANGELOG [6.7.13])

**Status:** ✅ **RESOLVED in v6.7.13** (see the banner). Was: 🟡 **OPEN** — reproduced 2026-10-13 on the 6.7.11 returns lane (l6711-returns, after the
declared-return repair) on x86_64, aarch64 (qemu), cx (cxvm) and PE (wine): the repro builds and exits 77.
**Placement:** 6.7.13 — repair 3: struct values (multivalue lane; re-placed at the 6.7.13 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.13 open):** D28 — C — every value is 0 off the end.
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

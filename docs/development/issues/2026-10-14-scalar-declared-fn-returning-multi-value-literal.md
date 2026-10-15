# A sync fn declared one value (`fn g2(): i64 { return (1, 2); }`) compiles clean and the caller silently gets the first value — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-14 on the 6.7.11 returns lane tip (l6711-returns, `build/cycc` the fixpoint
of 4288c67f + the review's doc fix) and on the lane base 0f733aea (the slot-open cycc), x86_64.
**Placement:** 6.7.12 — repair 2 (filed from the 6.7.11 returns review) — never 7.x.
**Severity:** Medium — silent: the declaration says one value, the body returns two, and nothing is said either way.
**Affects:** every compiler with declared return types — pre-existing. The reverse shape (a fn declared `: (i64,
i64)` returning one value) is refused since the 6.7.11 returns lane's ac07bb7a, and the async form since fcb8d909.
**Discovered:** 2026-10-14, the 6.7.11 returns lane's review (met in passing, not under review).

## Reproduction

```cyrius
fn g2(): i64 { return (1, 2); }
fn main(): i64 { var a = g2(); return a; }
syscall(60, main());
```

Compile rc 0, no diagnostic; exits **1** (the second value is dropped), lane tip and base. The declaration is
contradicted the other way too — the destructure accepts it:

```cyrius
fn g2(): i64 { return (1, 2); }
fn main(): i64 { var a, b = g2(); return a * 10 + b; }
syscall(60, main());
```

Compile rc 0; exits 12. `fn g2(): i64 { ret2(1, 2); }` + `var a = g2();` likewise compiles clean and exits 1.

## Root cause

PARSE_RETURN (src/frontend/parse_fn.cyr) judges the return against the declaration only for a fn declared
`: (T1, T2[, T3])` (`_mret_ret_check`, `GFRS == MULTIRET_SID`); a fn declared with a scalar return type takes the
multi-value literal arm (`return (a, b);`) and `ret2` with no check, and the destructure's arity check
(`_fn_ret_arity` / `_mret_fwd_ok`) does not treat a declared scalar as one value.

## Fix

A decision for the user, in one line: refuse `return (a, b[, c]);` / `ret2(..)` in a fn declared one value, by name
("'g2' is declared `: i64` - one value; declare `: (i64, i64)` to return two"), as ac07bb7a refuses the reverse — the
undeclared `fn divmod_old(a, b) { ret2(..); }` + `rethi()` legacy idiom in the guide § Multi-Return is untouched.
Rows: `: i64` / `: f64` / `: *T` / a struct return type with `return (a, b)` and `ret2`, and the destructure of such a
fn, in tests/gates/diagnostics/destructure_one_value_refused.sh (axis 5, ac07bb7a's rows for the reverse shape).

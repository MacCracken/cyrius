# Top-level `var X = "literal"` compiles clean but holds garbage at runtime → SIGSEGV

**Filed:** 2026-06-28 (by the `yeo-cy-test` consumer; cyrius 6.3.1 / 6.3.0 pin)
**Severity:** Medium — silent miscompile. It builds with **no error or warning**,
then crashes (or worse, reads garbage) the first time the global is used. The
fail-loud expectation (cyrius hard-errors on undefined fns, etc.) is violated for
a construct that *looks* valid.
**Component:** global-variable initializer codegen (the `gvar_initval` path —
`src/common/util.cyr` + the per-fork init that seeds global initial values).

## Summary

A module-level global initialized with a **string literal**:

```
var DB_PATH = "yeo.patra";
...
fn db_init(): i64 { var h = patra_open(DB_PATH); ... }   # SIGSEGV
```

compiles cleanly but `DB_PATH` does **not** hold the address of the `"yeo.patra"`
literal at runtime — it holds garbage (an uninitialized / wrong value). The first
dereference (`patra_open(DB_PATH)`) faults. cyrius's global initializers appear to
be **integer-only** (the `gvar_initval` table stores scalar init values); a
string-literal initializer needs the literal emitted into a data section and the
global seeded with its address, which doesn't happen — yet it's accepted silently.

## Reproduction

```
var S = "hello";
fn main() { var n = strlen(S); fmt_int(n); println(""); return 0; }   # SIGSEGV / wrong
var rc = main(); syscall(SYS_EXIT, rc);
```

Expected: prints `5`. Actual: crashes / garbage (the global `S` is not the
literal's address).

## Workaround (consumer-side)

Return the literal from a function instead of a global initializer — the literal's
address resolves correctly inside a function body:

```
fn db_path(): i64 { return "yeo.patra"; }
... patra_open(db_path()) ...
```

## Ask

Either (a) make string-literal global initializers work (emit the literal +
seed the global with its address), or (b) **fail loud at compile time** — reject
a non-integer global initializer with a clear error — so this can't silently
miscompile. (b) is the minimum; the current silent-garbage behavior is the trap.

## Status

✅ **RESOLVED (option a) — already fixed by an earlier v6.3.x; regression-locked in
v6.3.16.** As of v6.3.15, `var S = "hello"; strlen(S)` returns 5, `load8(S+i)`
returns the real literal bytes, cross-function use + a second global (`var DB_PATH
= "yeo.patra"`, len 9) all resolve correctly — default-on and `CYRIUS_STACK_ARRAYS=0`.
The literal is emitted into the data section and the global is seeded with its
address (option a), so no hard-error was needed. Pinned by
`tests/tcyr/struct_local_codegen.tcyr` (the string-literal global assertion) so it
can't silently regress. See CHANGELOG [6.3.16].

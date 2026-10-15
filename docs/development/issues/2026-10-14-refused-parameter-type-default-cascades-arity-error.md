# A parameter type refused by the 6.7.11 type reader still drops its default: `fn f(a: 5 = 0)` + `f()` gives a second error, "'f' expects 1 argument, got 0" — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-14 on the 6.7.11 tree (main 0601aff4, `build/cycc` 2,223,320 B, x86_64).
A cross-lane hand-off the returns lane left for the wave-1 merge that was not applied (the user, 2026-10-14: "file and
fix them in 6.7.12").
**Placement:** 6.7.12 — repair 2 (filed from the 6.7.11 integration) — never 7.x.
**Severity:** Low — the input is invalid and is refused at the parameter; the extra line is a cascade.
**Affects:** cycc 6.7.11 (the call-arguments lane's whole-type parameter reader, 25711ad2, met the returns lane's
cascade repair, 4288c67f).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
fn f(a: 5 = 0): i64 { return a; }
fn main(): i64 { return f(); }
syscall(60, main());
```

```
error:<source>:2:9: expected a type for parameter 'a', got number 5
error:<source>:3: 'f' expects 1 argument, got 0
```

Want: the first line only.

## Root cause

The returns lane (R5, shape 9 of `issues/archived/2026-10-09-refusal-cascades-tuples-pairs-u128-d19.md`) keeps a
parameter's default when only the parameter's TYPE was refused, through `_pd_type_refused` (src/frontend/parse_fn.cyr),
which answers 1 for a slice or an unresolved type name. The call-arguments lane (ARG-3, 25711ad2) added a refusal for any
non-type token (`a: 5`, `a: fn`); on the returns branch pass 2 accepted those silently, so `_pd_type_refused` was not
taught them, and after the merge such a parameter's default is dropped and every short call is refused again.

## Fix (the returns lane's hand-off, `~/.cache/c6/6711_handoff_returns.md` § Integration note)

Make `_pd_type_refused` answer 1 for every token `_pty_end` refuses (or call the same predicate), and add a row beside
`default_named_args_checked.sh` R9s1–R9s5 (`fn f(a: 5 = 0)` + `f()`: exactly one error, at the parameter).

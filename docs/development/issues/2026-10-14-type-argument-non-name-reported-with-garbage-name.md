# A type argument that is not a name (`Box<1 + 2>`, `Box<u128>`, `id<1 + 2>(3)`) is refused as "unknown type 'truct'" / "'struct'" — a name read from a number — and the generic call cascades — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-14 on the 6.7.11 genfe lane (l6711-genfe, unit G4, the compiler built from
the unit's tree, 2,189,720 B; the lane's base build/cycc prints the same).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (generics lane, wave 1, unit G2; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Discovered:** 2026-10-14 by the 6.7.11 genfe lane, unit G4 (comparing how each type-argument position refuses a
token that is no type, for `Vec<1 + 2>`).
**Severity:** Low — loud (the program is refused), but the message names a garbage type, and in a generic call the
cursor is left mid-list: two more errors follow, the last at the end of the file.
**Affects:** the lane base (0155abc7) and the unit G4 tree; older releases not bisected.

## Reproduction

```cyrius
struct Box<T> { v: T; }
fn id<T>(x: T): T { return x; }
fn main(): i64 {
    var a: Box<1 + 2>;
    var b: Box<u128>;
    return id<1 + 2>(3);
}
syscall(60, main());
```

```
actual:
error:<source>:4:18: unknown type 'truct' as a type argument (a type argument is a struct, i8/i16/i32/i64, f64, or a type parameter in scope)
error:<source>:5:20: unknown type 'struct' as a type argument (...)
error:<source>:6:17: unknown type 'truct' as a type argument (...)
error:<source>:7:1: expected ';', got '}'
error:<source>:8:21: expected '}', got end of file
expected: one error per argument, at the argument's token, naming what is there — "a type argument is a type name,
          got number 1" / "u128 cannot be a type argument" (as `Vec<1 + 2>` says "expected a Vec element type for
          'w', got number 1" since 6.7.11 unit G4) — and no cascade
```

The caret also points one token late (at `+` / the `>`), not at the argument.

## Root cause

`_parse_one_type_arg` (src/frontend/parse_fn.cyr) refuses a tuple's `(` and a slice's `[` by name, then takes
`PEEKV(S)` as a name-pool offset and steps one token WITHOUT checking that the token is an identifier: a number's value
(1) or `u128`'s keyword value is read as an offset into the name pool (offset 1 of a stored "struct" is "truct"), and
`_type_arg_leaf` refuses that garbage name. In `id<1 + 2>(3)` only `1` is consumed, so `+ 2>(3)` is left to the
statement parser.

## Proposed fix

In `_parse_one_type_arg`, when the token is not an identifier (and not `(` / `[`): report "a type argument is a type
name, got <token>" once at the token (a `u128` by its own text), skip the rest of the list to its closing `>` as
`_skip_targ_list` would from depth 1, and return the i64 base (`0 - 8`) so nothing cascades. Rows: the three repro
lines, one error each, at their argument's column; `Box<i64>`, `id<i32>(3)` unchanged.

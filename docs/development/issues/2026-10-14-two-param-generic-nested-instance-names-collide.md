# A two-parameter generic's instance name is ambiguous when a type argument is itself an instance: `g2<P<R>, i32>` and `g2<P, R<i32>>` share `g2$P$R$i32` — the second call runs the first's body — OPEN

**Status:** 🟡 **OPEN** — found by the 6.7.11 genfe lane (unit G1) while fixing the f64 / `struct i` instance-name
collision; pre-existing, untouched by that fix.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (generics lane, wave 1, unit G1; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Decision (user, 2026-10-16, at the 6.7.14 open):** D1 — (a).
**Discovered:** 2026-10-14, 6.7.11 genfe G1 (a probe of the name class the f64 fix closes)
**Severity:** High — a silent miscompile (the wrong instance's body runs, no diagnostic); the trigger is narrow (a
two-parameter generic whose arguments include a generic struct's instance AND a generic struct used bare)
**Affects:** cycc since two-parameter generics minted `Base$<c0>$<c1>` (v6.3.33) through the 6.7.11 genfe tree
(6538d390), every target (the name is minted in the frontend)

## Summary

`_mint_generic_name` (src/frontend/parse_fn.cyr) names a two-parameter instance `Base$<frag0>$<frag1>`, and a
struct type argument's fragment is its registered name — for a generic struct's instance, that name already holds a
`$` (`P$R`, `R$i32`). So the split between the two fragments is lost: `g2<P<R>, i32>` mints `g2$` + `P$R` + `$` +
`i32`, and `g2<P, R<i32>>` mints `g2$` + `P` + `$` + `R$i32` — the same `g2$P$R$i32`. FINDFN dedups by name, so the
second instantiation calls the first's body. The 6.7.11 fix (`$f64`, and `$.f64` for a struct named like a scalar)
made scalar and struct fragments distinct; it does not cover a fragment boundary inside a nested instance's name.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
struct P<T> { v: T; }
struct R<T> { v: T; w; }
fn g2<A, B>(a: *A, b: *B): i64 { return sizeof(A) * 100 + sizeof(B); }
fn main(): i64 {
    var x = g2<P<R>, i32>(0, 0);
    var y = g2<P, R<i32>>(0, 0);
    fmt_int(x); syscall(1, 1, " ", 1); fmt_int(y); syscall(1, 1, "\n", 1);
    return 0;
}
syscall(60, main());
```

```
$ cat nest.cyr | build/cycc > nest && ./nest
1604 1604
```

Expected `1604 812` (`P<R>` is 16 B, `i32` 4; the bare `P` is 8 B, `R<i32>` 12). With the two calls swapped it
prints `812 812` (expected `1604 812`). A coverage dump (`CYRIUS_COVERAGE=1`) shows one instance entered twice:
`2 <source>:6 g2$P$R$i32`. Measured on the 6.7.11 base (5fb211da's tree compiler) and on the genfe tree after
6538d390 — identical.

A generic STRUCT mints through the same function, so `Two<P<R>, i32>` and `Two<P, R<i32>>` share `Two$P$R$i32`
too (both are 20 B, so `sizeof` does not show it; the field layout does):

```cyrius
struct P<T> { v: T; }
struct R<T> { v: T; w; }
struct Two<A, B> { a: A; b: B; }
fn main(): i64 {
    var t1: Two<P<R>, i32>;
    var t2: Two<P, R<i32>>;
    t2.b.w = 5;
    return t2.b.w;
}
syscall(60, main());
```

```
error:<source>:7:9: expected '=', got '.'
        t2.b.w = 5;
            ^
error:<source>:7:12: undefined variable 'w' (missing include or enum?)
```

`t2` got `t1`'s layout (`b` an i32). Without the `t1` line it compiles and exits 5.

## Root cause

`_append_conc_name` copies a struct sid's registered name verbatim, and a generic struct instance's registered name is
itself `Base$<frag>` (minted by `_instantiate_generic_struct`). `$` is both the separator `_mint_generic_name` writes
between fragments and a byte inside a nested fragment, so the parse of `Base$a$b$c` into two fragments is not unique.

## Proposed fix

Make the fragment boundary unambiguous for a nested instance: e.g. bracket a fragment that itself contains `$` (a
non-identifier byte pair such as `<` … `>` or a length prefix), so `g2$<P$R>$i32` and `g2$P$<R$i32>`. That changes
the spelling of every nested two-parameter instance name the toolchain shows (diagnostics, the coverage dump), so the
spelling is the user's call; the single-parameter names (`Box$Pair$i32`) are unambiguous already (one fragment).
Rows: the repro above (`1604 812`) and its swap on every fork; the struct form with a field layout that differs.

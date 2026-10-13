# A generic instantiated at `f64` and at a struct named `i` share one instance (`gen$i`) — the second call runs the first's body — OPEN (a decision)

**Status:** 🟡 **OPEN** — the fix needs a one-line decision on the f64 instance's spelling (below).
**Placement:** unplaced — for the user to place (found by the 6.7.10 P5-B review, lane p5b; pre-existing).
**Discovered:** 2026-10-12 during the 6.7.10 P5-B review (execution coverage prints instance names, `gen$i`)
**Severity:** High — a silent miscompile; the trigger is narrow (a struct named `i`, or one named like a scalar)
**Affects:** cycc since generic instances were minted per concrete type (v6.3.33's `_mint_generic_name`) through 6.7.10

## Summary

`_mint_generic_name` (src/frontend/parse_fn.cyr) names an instance `Base$<conc>`, and `_append_conc_name` spells a
scalar `conc` as `i64` / `i32` / `i16` / `i8` — but `f64` (conc `-9`) falls through every arm and is written as a bare
`i`. A struct named `i` is spelled by its own name, `i`. So `gen<f64>` and `gen<i>` both mint `gen$i`, the
FINDFN dedup finds the first, and the second instantiation calls the first instance's body. Nothing is reported.

## Reproduction

```cyrius
struct i { a; b; }
fn gen<T>(x: *T): i64 { return sizeof(T); }
var a = gen<f64>(0);
var b = gen<i>(0);
var r = a * 10 + b;
syscall(60, r);
```

```sh
cat repro.cyr | build/cycc > /tmp/r && chmod +x /tmp/r && /tmp/r; echo $?
```

Expected `96` (8 * 10 + 16). Actual `88`: `gen<i>` ran `gen$i` = the f64 instance (`sizeof` 8). With the two calls
swapped the result is `176` (16 * 10 + 16): the f64 call runs the struct's instance. Measured on bc8370b9's
`build/cycc` (6.7.10 slot) and on the p5b lane's compiler; unchanged by the lane.

## Root cause

`_append_conc_name` (src/frontend/parse_fn.cyr, `if (conc < 0)` arm): it stores `i` first, then the width digits
for -8 / -4 / -2 / -1 only, so -9 leaves `i` alone. The two sibling writers already spell f64 correctly —
`_bnd_type_is` (`c0 = 102` for -9) and `_bnd_pr_conc` (`PRSTR("f64")`) — so only the minted name is wrong.

## Proposed fix — the decision it needs

Spell -9 distinctly in `_append_conc_name`. The obvious `f64` (`gen$f64`) is NOT collision-free by itself: `struct
f64 { a; b; }`, `struct i32 { … }` and `struct i8 { … }` all compile today, so a struct may carry a scalar's name and
mint the same `$f64` / `$i32` fragment. A collision-free spelling needs either a character no struct name can hold in
the scalar fragments, or a marker on the struct fragments — a change to every instance name the toolchain shows
(diagnostics, the execution-coverage dump, which documents `gen$i32` and cuts at `$`). Which spelling
is the user's call; with it decided, the writer change is a few lines plus a regression row (the repro above, and its
swapped form) on every fork.

Note for whoever fixes it: the 6.7.10 execution-coverage gates pin today's `gen$i` / `sh_gen$i` spelling of a
`<f64>` instance (`tests/gates/codegen/coverage_exec_hits.sh` B1 and F3, `tests/gates/toolchain/coverage_exec_cli.sh`
X1's comment); the CLI reads names cut at the first `$`, so its counts do not depend on the spelling.

## Consumer-side workaround

Do not name a struct `i` (or `i8` / `i16` / `i32` / `f64`) when it is used as a generic type argument.

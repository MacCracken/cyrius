# A parenthesised argument to a ≤ 8 B by-value struct parameter skips the struct type check — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-08 against 6.7.6 @ 2fb6ad8b with `build/cycc`: `bs1(t)` with `t: T1` into
`p: S1` (both 8 B) is refused, `bs1((t))` and `bs1(((t)))` compile and run (exit 7, T1's word read as an S1). The
16- and 24-byte by-value cases refuse all three spellings. Same on the installed 6.7.3 and 6.7.5 compilers.
**Placement:** 6.7.10 — Break 2, repair 1 (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-09 — never 7.x.
**Discovered:** the 6.7.6 review (pre-existing; roadmap commit d2d5309b); filed 2026-10-08 from roadmap.md.
**Severity:** Low — a missed refusal (wrong-typed argument accepted), no crash; the unparenthesised spelling is caught.
**Affects:** cycc 6.7.3 – 6.7.6 (the 6.7.3 check never covered the wrapped spelling)

## Summary

6.7.3 made an argument of another struct type into a struct parameter a compile error by name; 6.7.6 made parentheses
around a whole argument transparent (`_sarg_paren`) for the address-passed parameters. A parameter of a struct of 8 B
or less is passed BY VALUE and checked by `_sarg_byval_small`, which recognises a bare name only when the argument's
first token is the name — `(t)` begins with `(`, so its struct is never read and the call compiles.

## Reproduction

```cyrius
struct S1 { v; }
struct T1 { w; }
fn bs1(p: S1): i64 { return p.v; }
fn main(): i64 { var t: T1 = T1 { 7 }; return bs1((t)); }
syscall(60, main());
```

```sh
cat repro.cyr | build/cycc > /tmp/r && chmod +x /tmp/r && /tmp/r; echo $?
```

Expected (as `bs1(t)` reports): `error:<source>:4:N: cannot pass 't' to a parameter of a different struct type in a
call to 'bs1'`. Actual: builds; exit 7. `bs1(((t)))` the same. With `S2 { v; u; }` / `T2 { w; q; }` (16 B) or 24-byte
structs, `bs1(t)`, `bs1((t))` and `bs1(((t)))` are all refused.

## Root cause

`_try_push_struct_addr_arg` (`src/frontend/parse_fn.cyr:1547`) returns `_sarg_byval_small(S, fi, argc)` at line 1549
for any parameter without a struct-mask bit — BEFORE the 6.7.6 parenthesis unwrap at line 1550
(`if (PEEKT(S) == 10) { return _sarg_paren(..); }`). `_sarg_byval_small` (`parse_fn.cyr:1651`) takes the bare-name
struct only under `if (PEEKT(S) == 2)` (an identifier first); its fallbacks (`_sc_whole`, the `_fpk` field record,
`_fls_whole`) do not cover a wrapped name, so `asid` stays 0 and `_sarg_type_err` passes.

## Proposed fix

In `_sarg_byval_small`, step over whole-argument parentheses (`_pwrap_k`, as `_sarg_paren` does) before the
bare-name / call test, reading the name inside; the PCMPE + EPUSHR emission stays as it is (byte-identical code). A
`tests/gates/codegen/struct_value_codegen.sh` P-family row for `bs1((t))` / `bs1(((t)))` (refused once, by name) and
the 8 B call / field / method-result spellings wrapped. Refusing it makes code that compiles today stop compiling —
the same refusal the unwrapped spelling has had since 6.7.3.

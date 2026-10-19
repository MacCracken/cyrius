# `var y: T = mkp();` (or `y = mkp();`, `p = mkp();` into a `p: *T`) inside a generic fn called with `T = i64` / `u8` keeps the struct's first word — D24 / D27 / D32 never judge a scalar instance's `T` — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 receives lane (unit R3, after the D32 / D33 bites,
326c1b56a) with `build/cycc` built from that tree (x86_64); the lane before the unit (d5adfcd2a) gives the same exits.
**Placement:** 6.7.16 — Break 2, repair 6 (genbind lane, wave 3, unit GB5; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Severity:** Medium — a silent wrong value (the struct's first word) where the guide says the line is judged per
instance and the same line outside a generic is refused by name.
**Discovered:** 2026-10-18, the receives lane, writing D32's rows (issues/2026-10-17-struct-result-assigned-to-pointer-
or-untyped-scalar-keeps-first-word.md): D32's `*T` test exempts a generic BASE's `*T` as `_rcv_ann_hit` exempts its
`T` (`_rcv_tp_base`, "each instance judges its own binding"), and probing the instances showed none of them judges.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct Q { a; b; }
fn mkp(): Q { var q: Q; q.a = 333; q.b = 444; return q; }
fn g<T>(x: T): i64 { var y: T = mkp(); return y; }
fn main(): i64 { var u: u8 = 5; return g(u); }
syscall(60, main());
```

```
rc 0, no diagnostic; exit 77 (333 mod 256, the struct's first word) — `T = u8`
```

The same with `g(5)` (`T = i64`, the base) exits 77; the assignment `var y: T = 0; y = mkp();` through `g<i64>(5)`
exits 77; `var p: *T = 0; p = mkp();` through `g(5)` compiles (exit 0). Outside a generic each line is refused by name
(`var y: u8 = mkp();` — "cannot initialise 'y: u8' from 'mkp', which returns the struct 'Q' - declare 'y: Q' or bind a
field", 6.7.11's D24; the assignment 6.7.14's D27; the `*i64` 6.7.15's D32). The guide (§ struct results) says
"inside a generic fn, `var x: T = mk(9);` is judged per instance (`T = P3` is the struct)".

## Root cause

`_rcv_ann_hit` / `_asa_ptr` (src/frontend/parse_decl.cyr, parse.cyr) exempt a type parameter annotation in the generic's
BASE parse (`_rcv_tp_base`: `_inst_name` 0, T the i64 base), leaving the judgement to each instance. For `T = i64` the
base IS the code that runs, so nothing judges it; a scalar instance (`g$u8`) is not judged either — measured, not
traced: likely the instance's straight-line body is replayed inline at the call (the replay skips the per-definition
checks), or the instance parse resolves `T` to the scalar without reaching `_rcv_ann_refuse`.

## The fix (a sketch)

Judge the annotation where the binding is known: in an instance (or the inline replay of one) whose `T` resolves to a
scalar, and in the base when the call that reaches it binds `T = i64`. `T = P3` (a struct) keeps its copy.

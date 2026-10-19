# A closure's parameter keeps the type an EARLIER fn's local left in its frame slot — `|x| { return x.b; }` compiles as a `*Q` read (SIGSEGV) and `x = mkp();` copies through it — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 receives lane (unit R3, D32 / D33 bite) with `build/cycc`
built from that tree (x86_64); the lane before the unit (d5adfcd2a) gives the same rc and exit for both repros.
**Placement:** 6.7.16 — Break 2, repair 6 (genbind lane, wave 3, unit GB3; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Severity:** Medium — a silent miscompile: an untyped closure parameter is treated as a pointer to a struct that no
part of the closure names, so a field read through it compiles and faults, and a struct-result assignment into it is
a struct copy through the parameter's value (a wild write), where D33 (6.7.15) refuses it.
**Discovered:** 2026-10-18, the receives lane, writing D33's closure-parameter row (`|x| { x = mkp(); }`): the row was
refused in a file whose earlier fns had no `*Q` parameter and built (exit 139) in the gate's header, where
`fn Q_add(x: *Q, y: *Q)` precedes it.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct Q { a; b; }
fn h(w: *Q): i64 { return 0; }
fn main(): i64 { var k = |x| { return x.b; }; return callptr(k, 0); }
syscall(60, main());
```

```
rc 0, no diagnostic; the binary SIGSEGVs (exit 139): `x.b` reads through x (0) as a `*Q`
```

Without `fn h(w: *Q)` the same `x.b` is refused ("no struct type in scope for 'x'"), as an untyped name's field is.
With an assignment (D33's row):

```cyrius
include "lib/syscalls.cyr"
struct Q { a; b; }
fn mkp(): Q { var q: Q; q.a = 333; q.b = 444; return q; }
fn h(x: *Q): i64 { return 0; }
fn main(): i64 { var k = |x| { x = mkp(); return x; }; return callptr(k, 0); }
syscall(60, main());
```

```
rc 0, no diagnostic; exit 139 (the struct is copied through x = 0). With `var t = 1;` first in main (the closure's
parameter in another slot) it is refused, as decided: "cannot assign 'x' from 'mkp', which returns the struct 'Q' -
declare 'x: Q' or bind a field"
```

## Root cause

The closure prologue (`_PARSE_FACTOR_IMPL`'s `|params|` arm, src/frontend/parse_expr.cyr, the `cpgo` loop) declares
each parameter at slot `GFLC` by writing its name and depth only (`S64(S + 0x5D9D000 + cpli * 8, cpnoff)`,
`SLDEP`); the slot's type records (GLTYPE / GLAGG, the pointer word, the handle marks) keep whatever an earlier fn's
local at that index left — here `h`'s parameter 0, a `*Q` handle. `_agc_operand` (the assignment's destination) and
the field load then read x as that `*Q`. A slot is reset when an ordinary local or parameter is declared; the
closure's parameters skip it.

## The fix (a sketch)

Reset each closure parameter's slot records as an ordinary untyped parameter's are (the reset PARSE_VAR / the fn
prologue apply), so `x` is an untyped word: `x.b` refused by name, `x = mkp();` refused by D33. A program that read a
field through such a parameter stops compiling (it faulted).

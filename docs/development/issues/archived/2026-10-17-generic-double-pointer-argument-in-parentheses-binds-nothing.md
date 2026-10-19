# A parenthesised or computed `**S` argument binds nothing in a generic `pp: **T` call — `st((pps))` runs the i64 base, `tg((pps))` faults — RESOLVED

> ✅ **RESOLVED in v6.7.15** (VC-14, `a20d624de` — the user's decisions D22 A (parentheses transparent) and D23 A (a typed pointer plus or minus n is still that pointer), 2026-10-18. `_ic_pp_arg` peels a whole-argument wrap and reads pointer arithmetic by its typed-pointer operand (`_ic_arith_end`, `_ic_parith`, src/frontend/parse_types.cyr). `_ic_arg` takes the arithmetic through `p: *T`, and the stub scan reads it too (`_tok_ta_arith`, parse.cyr). The filed repro `tg((pps))` gives 42 on x86_64, IR=3, aarch64, cx and PE, where it gave 139 / 139 / 139 / cx 254 / PE 5, and so do `tg(pps + 0)` and `tg((&ps))`. Through `p: *T`, `g(ps + 1)` / `g(1 + ps)` / `g((ps) - 1)` step 24 (8 before). `&s + n`, a distance and a bitwise result bind nothing. Rows: `generic_double_pointer_infer.sh` W1 (the filed repro verbatim) – W4 and WK, on the five legs; `crossos/double_pointer_deref_step.tcyr` GW (6), with GK's `(pps)` / `pps + 0` row flipped to `&ps + 0`; `generic_method_infer.sh` P8a – P8g and P8K1 / P8K2. Mutations measured (ledgers in the gates' headers). Already filed, not closed here (6.7.16, the generics lane): the stub scan's missing `**T` rung, `var r = gd2((ppp)); return r.pick(t);` (2026-10-18-generic-token-scans-miss-double-pointer-and-generic-pointer-call-binding.md). CHANGELOG [6.7.15])

**Status:** ✅ **RESOLVED in v6.7.15** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-17 by the 6.7.14 release-docs pass on main (after the vectors lane's VC-15,
which implemented 6.7.14's D40 A: a `**S` argument binds T in `fn st<T>(pp: **T)`), x86_64.
**Placement:** 6.7.15 — repair 5 (vectors lane, wave 2, unit V5; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Decision (user, 2026-10-18, at the 6.7.15 open):** D22 — A: parentheses are transparent.
**Decision (user, 2026-10-18, at the 6.7.15 open):** D23 — A: yes, it is still that pointer.
**Severity:** Medium — `tg((pps))` faults (139) where `tg(pps)` gives 42 (measured on main, x86_64); parentheses around a whole argument are
transparent everywhere else (6.7.13's D19 family, this release's VC-3 for value-form vector arguments).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct P3 { a; b; c; }
fn take(p: *P3): i64 { return p.c; }
fn tg<T>(pp: **T): i64 { return take(**pp); }
fn main(): i64 { var s: P3; s.c = 42; var ps: *P3 = &s; var pps: **P3 = &ps; return tg((pps)); }
syscall(60, main());
```

```
tg(pps)          42
tg((pps))        139   (the i64 base: T unbound)
tg(pps + 0)      139
tg<P3>((pps))    42
```

The guide documents the narrower reach and gate rows GK pin it as "bind nothing".

## Fix

The D40 inference reads the argument's `**S` through whole-argument parentheses (the transparency helper the receives
use) and from a computed `pps + n` of a `**S`; flip the GK rows to the bound result.

# D24 does not reach a top-level declaration: `var G: i64 = mk2(5);` (a 9-16 B struct) compiles and reads the first field — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-15 on the 6.7.12 fixfirst lane (unit X1, after D28's bite) and on the
slot-open compiler (`7f57e532`): the repro compiles with no diagnostic and exits 10 (G = 5, H = 5: each the first
field), x86_64. In a fn the same declarations are refused by name (D24, 6.7.11; D28, 6.7.12, for the `&f` call).
**Placement:** 6.7.13 — repair 3: struct values (structs lane; filed from the 6.7.12 fixfirst lane, placed at the 6.7.12 integration, 2026-10-15) — never 7.x.
**Discovered:** 2026-10-15, the fixfirst lane, measuring D28's neighbours.
**Severity:** Low — a silent first-field read at top level; the in-fn spelling is refused by name. A struct over 16 B
is refused at top level anyway ("returns a struct by value, and a struct result needs storage in a fn's frame").
**Affects:** a top-level (or declaration-zone) global annotated with a type that names no struct (`i64`, `u8`, `f64`,
`bool`, `cstring`, ...) initialised from a call returning a struct of 9-16 B, direct or through a known `&f`.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/fnptr.cyr"
struct P2 { a; b; }
fn mk2(x): P2 { var r = P2 { x, x + 1 }; return r; }
var G: i64 = mk2(5);
var H: i64 = fncall1(&mk2, 5);
syscall(60, G + H);
```

```
compiles, no diagnostic; exits 10
```

## Root cause

`_rcv_scalar_ann` (src/frontend/parse_decl.cyr, D24) is called from PARSE_VAR's receive block, which runs only in a fn
(`GINFN == 1`); D28's `_scv_icall_ann` (6.7.12) is fn-only to match it. The top-level and declaration-zone global paths
(`_sc_global_receive` / `_gvi_expr`) store the call's first word into the scalar global.

## Fix direction

The same refusal, D24's words, in the global declaration paths (the direct call and the known `&f` call), or the
user's word that a global differs. A redeclared / declaration-zone global needs its row too.

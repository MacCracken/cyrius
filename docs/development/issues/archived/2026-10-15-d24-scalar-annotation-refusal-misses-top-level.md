# D24 does not reach a top-level declaration: `var G: i64 = mk2(5);` (a 9-16 B struct) compiles and reads the first field — RESOLVED

> ✅ **RESOLVED in v6.7.13** (ST-11, `8abca341`: 6.7.11's D24 reaches a top-level declaration. The filed repro is refused at both declarations — "cannot initialise 'G: i64' from 'mk2', which returns the struct 'P2' - declare 'G: P2' or bind a field" and H's, through `fncall1(&mk2, ..)` — no binary, on x86_64, aarch64, cx and PE (it exited 10 with no diagnostic). Likewise `: u8` / `: f64` / `: cstring` / `: bool` (D24's words once, no longer "not a bool"), `(mk2(5))`, `callptr(&mk2, ..)` and a generic callee, in the declaration zone and after the first statement, and a redeclared global (was 5). Over 16 B keeps its one no-frame refusal; 8 B or less and `Str` keep the word. No new decision: 6.7.12's D28 ("D24 at every path") is the binding precedent. Rows: `struct_receive_inference_checked.sh` TL0-TL16 + TLK1-TLK3 on the four compilers (row floor 45 → 65); mutations N12-N17 RED. CHANGELOG [6.7.13])

**Status:** ✅ **RESOLVED in v6.7.13** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-15 on the 6.7.12 fixfirst lane (unit X1, after D28's bite) and on the
slot-open compiler (`7f57e532`): the repro compiles with no diagnostic and exits 10 (G = 5, H = 5: each the first
field), x86_64. In a fn the same declarations are refused by name (D24, 6.7.11; D28, 6.7.12, for the `&f` call).
**Placement:** 6.7.13 — repair 3: struct values (structs lane; re-placed at the 6.7.13 open, 2026-10-15) — never 7.x.
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

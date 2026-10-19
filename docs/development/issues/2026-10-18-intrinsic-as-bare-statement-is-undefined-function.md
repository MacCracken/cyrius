# `mulh64(a, b);` / `sizeof(T);` as a bare statement is a call to an undefined fn — with --allow-undef it builds and traps — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-18 by the 6.7.15 structs lane (unit S6) while checking that
`_call_undef` (the undefined-callee field fix) leaves the identifier intrinsics alone. Pre-existing (the lane head
gives the same); x86_64 measured, the frontend's (every target).
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 structs lane, wave 2; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
**Severity:** Low — a statement that only computes an intrinsic discards its value; by default the compile is
refused, but by naming a fn that does not exist, and `--allow-undef` builds a binary that traps at the line.
**Kind:** language / diagnostics (statement position).

## Repro

```cyrius
include "lib/syscalls.cyr"
struct H { n; m; }
fn go(): i64 { mulh64(2, 3); return 0; }
syscall(60, go());
```

```
warning: undefined function 'mulh64'
warning: undefined function 'mulh64' (reachable call site)
error: refusing to emit binary with 1 reachable undefined function(s) (pass --allow-undef to downgrade)
```

rc 1. With `--allow-undef`: rc 0, and the binary exits 132 (SIGILL at the unresolved call). `sizeof(H);` as a statement:
"undefined variable 'H'" then the same undefined-function lines. As a value (`var x = mulh64(2, 3);`,
`var n = sizeof(H);`) both are lowered by name.

## Root cause

PARSE_FACTOR lowers `sizeof(..)` / `mulh64(..)` by name (`_is_ident_intrinsic`, src/frontend/parse.cyr), but
_PARSE_STMT_IMPL's `IDENT (` arm sends the statement to PARSE_FNCALL, which registers and calls a fn of that name
(6.6.20 made the names reserved as declarations, so none can exist). `fncallN` has its statement arm since 6.6.5.

## Proposed fix

The user's call whether a discarded intrinsic statement is accepted (lowered, its value dropped, as `f(x);` drops
one) or refused by name ("the value of 'mulh64(..)' is discarded"); either way not an undefined fn. A row per
intrinsic in statement position, with and without --allow-undef.

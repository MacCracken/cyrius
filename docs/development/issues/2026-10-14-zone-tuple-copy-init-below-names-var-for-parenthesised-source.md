# `var A: (i64, i64) = (B);` in the declaration zone, with B declared below: `_gci_below` names the wrong source, 'var' instead of 'B' — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-14 on the 6.7.11 returns lane tip (l6711-returns, `build/cycc` the fixpoint
of 4288c67f + the review's doc fix) and on the lane base 0f733aea (the slot-open cycc), x86_64.
**Placement:** 6.7.12 — repair 2 (filed from the 6.7.11 returns review) — never 7.x.
**Severity:** Low — the program is invalid and is refused at the right place; the message names the wrong global.
**Affects:** pre-existing message defect. Since the 6.7.11 returns lane's 4288c67f (R5: `_tup_src_later` sends a
parenthesised lone name to the replay, so the generic "not a tuple" no longer comes first) the wrong line is the
ONLY error.
**Discovered:** 2026-10-14, the 6.7.11 returns lane's review (of 4288c67f).

## Reproduction

```cyrius
var A: (i64, i64) = (B);
var B = (1, 2);
fn main(): i64 { return A.0; }
syscall(60, main());
```

Lane tip:
```
error:<source>:1:21: cannot copy-init 'A' from a global declared below it (declare the source first): 'var'
    var A: (i64, i64) = (B);
                        ^
```
Base (0f733aea), the same wrong name as the second of two errors:
```
error:<source>:1:8: cannot initialize tuple 'A' with a value that is not a tuple
error:<source>:1:21: cannot copy-init 'A' from a global declared below it (declare the source first): 'var'
```
Right: `... (declare the source first): 'B'`. Unwrapped (`= B;`) it names `B`.

## Root cause

`_gci_below` (src/frontend/parse_decl.cyr) prints `TOKVAL(S, GTI(S))`, the token at the cursor, as the source's
name. Its comment assumes `_gci_src` left the cursor on an `IDENT [. IDENT ..]` source; for a wrapped source the
cursor is on the `(`, whose TOKVAL is no name offset (offset 0 reads the program's first identifier text, `var`).

## Fix

Name the source's identifier, stepping a whole-value wrap (`_pwrap_k`) first — the same token `_tup_src_later` tests.
Rows: the repro (one error, `'B'`), `((B))`, `(B.f)` for a struct source, in tests/gates/frontend/tuple_checked.sh.

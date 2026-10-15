# `var a, b = callptr(fp, 5);` is refused "multi-value destructure needs a call on the right-hand side", where `fncall1(fp, 5)` destructures — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-13 on the 6.7.11 callargs lane tree (unit A1) and on the slot-open compiler
(`0f733aea`): the repro below is refused at line 6 (`error:<source>:6:16: multi-value destructure needs a call on the
right-hand side`) on x86_64, aarch64, cx and PE, while line 5's `fncall1(fp, 5)` is accepted (11 with line 6 removed).
**Placement:** 6.7.13 — repair 3: struct values (multivalue lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Discovered:** 2026-10-13, the 6.7.11 callargs lane (unit A1), writing the two-word receive's rows.
**Severity:** Low. Refused loudly; the workaround is `fncall1(fp, ..)` (the same lowering).
**Affects:** `callptr` in every destructure (`var a, b = ..`, `a, b = ..`), all four targets.

## Reproduction

```cyrius
include "lib/fnptr.cyr"
fn two(a): (i64, i64) { return (a, a + 1); }
fn main(): i64 {
    var fp = &two;
    var a, b = fncall1(fp, 5);
    var c, d = callptr(fp, 5);
    return a + b + c + d;
}
syscall(60, main());
```
Both compilers, all four targets: `error:<source>:6:16: multi-value destructure needs a call on the right-hand side`.

## Root cause

The destructure's right-hand-side check (`_dt_rhs_check` / `_dt_call_open`, parse_decl.cyr) recognises `f(`, `g<..>(`
and `x.m(`; `callptr` is a builtin token (137), not an IDENT, so it is no "call" there, while `fncall1` is an IDENT
naming lib/fnptr.cyr's fn and passes.

## Proposed fix

Let `_dt_call_open` accept `callptr (` (the same lowering as `fncallN`), and `_dt_call_fn` answer -1 for it (no declared
arity to check, as for `fncallN`). Rows: the repro (exit 22), the assignment form, a top-level one.

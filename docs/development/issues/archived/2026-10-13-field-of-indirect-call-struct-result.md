# `fncall1(&mk3, 5).b` — a field of a struct result through fncallN / callptr is a parse error, where `mk3(5).b` works — RESOLVED

> ✅ **RESOLVED in v6.7.13** (RC-9, `5a73a702` + `389e715d`: the user's decision D16 (a), 2026-10-15 — a known `&f` callee's result takes `.field` / `.method(..)`, chained, as `mk3(5).b` does. The filed repro exits 12 on x86_64, IR=3, aarch64, cx and PE (it was "expected ';', got '.'"); a chained method, a 16 B result, a `*P3` callee's field (and `fncall1(&gp, 5).b = 40;` storing through it), the callee wrapped and the statement `fncall1(&mk3, 5).tot();` work; at top level the field is refused once, by name; a callee held in a variable followed by `.name` is refused by name (its result is a word, 6.7.11's D31); under `--syntax-only` (lint's pre-pass) nothing is reported, as for `mk3(5).b`. Rows: `struct_value_codegen.sh` FP20 (the repro verbatim) – FP32, FPw4 (PE); `crossos/fncall_struct_result.tcyr` FC1 – FC14 (B1 – B7); mutants M-FI1 – M-FI6 RED. Filed beside it: `callptr(&gp, 5).b = 40;` is still "expected ';', got '='" (2026-10-16-callptr-statement-field-store-does-not-parse.md); a top-level method chain over 16 B is refused twice (2026-10-16-toplevel-method-chain-over-16b-refused-twice.md). CHANGELOG [6.7.13])

**Status:** ✅ **RESOLVED in v6.7.13** (see the banner). Was: 🟡 **OPEN** — reproduced 2026-10-13 on the 6.7.11 callargs lane tree (unit A1, after
`2026-10-12-struct-result-through-fn-pointer-faults.md`'s fix, which made a known `&f` callee's struct result a struct
value) and on the slot-open compiler (`0f733aea`): the repro below is refused `error:<source>:6:29: expected ';', got
'.'` on x86_64, aarch64, cx and PE alike, while line 5's `mk3(5).b` (6.6.12, `_call_field`) compiles.
**Placement:** 6.7.13 — repair 3: struct values (receives lane; re-placed at the 6.7.13 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.13 open):** D16 — (a).
**Discovered:** 2026-10-13, the 6.7.11 callargs lane (unit A1).
**Severity:** Low. Refused loudly (no wrong value); the workaround is to bind the result first
(`var p: P3 = fncall1(&mk3, 5); p.b`).
**Affects:** `fncall0`..`fncall8` and `callptr`, every struct result, all four targets.

## Reproduction

```cyrius
include "lib/fnptr.cyr"
struct P3 { a; b; c; }
fn mk3(a): P3 { var r: P3 = P3 { a, a + 1, a + 2 }; return r; }
fn main(): i64 {
    var d = mk3(5).b;
    var x = fncall1(&mk3, 5).b;
    return d + x;
}
syscall(60, main());
```
Both compilers, all four targets: `error:<source>:6:29: expected ';', got '.'`.

## Root cause

PARSE_FACTOR lowers `fncallN(` / `callptr(` through PINDIRECT_CALL and returns at the `)`; the `.field` / `.method(..)`
chain a free call's result takes (`_call_field`, 6.6.12) and a method's (`_method_chain`, 6.6.17) is never offered.
Since 6.7.11 a known `&f` callee's struct result has a temp (`_icall_sret`) and a record (`_sc_post`), so the chain's
inputs exist.

## Proposed fix

After `_PINDIRECT_CALL_IN`, when the callee is known and returns a struct, run the method arm's chain
(`_method_chain(S, cfi, name, beg, t)`) on the result, as `_dyn_call` does; a callee in a variable keeps the parse error
(its result is a word) or is refused by name. Rows: the repro (exit 12), a chained method, a top-level refusal.

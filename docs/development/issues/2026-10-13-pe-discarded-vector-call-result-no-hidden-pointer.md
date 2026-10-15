# On PE a vector-returning call whose result goes nowhere passes no hidden result pointer: `mkv(41, 7);` as a statement page-faults — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-13 on the 6.7.11 callargs lane tree (unit A1, after
`2026-10-12-vector-receive-from-callptr-reads-wrong-lanes.md`'s fix) and on the slot-open compiler (`0f733aea`,
`build/cycc` 2,114,376 B): the three repros below exit 3 on x86_64, aarch64 (qemu) and cx (cxvm), and exit 5 on PE
(wine: a page fault writing to address 41).
**Placement:** 6.7.12 — repair 2 (filed from the 6.7.11 callargs lane) — never 7.x.
**Discovered:** 2026-10-13, the 6.7.11 callargs lane (unit A1), measuring the vector receive's neighbours.
**Severity:** High. A crash on one target from source that compiles clean on all of them, with no diagnostic.
**Affects:** the PE (Win64) target only — every value-form vector return type (`f64v2`, `f32v4`, the integer
vectors, `f64v4`, `f32v8`); the slot-open compiler and the A1 tree alike (not bisected).

## Summary

On Win64 a vector result comes back through a hidden result pointer the CALLER passes as int arg 0. The caller passes
one only where a vector local receives the call: PARSE_VAR's `_f2c` / `_f4c` receives, `_try_vector_call_assign`, and
since 6.7.11 the wrapped and `fncallN(&f, ..)` / `callptr(&f, ..)` receives (`_vrcv_emit`). A vector-returning call
anywhere else — a statement whose result is discarded, an untyped `var x = callptr(&mkv, ..)` (the untyped
declaration infers the vector only from a by-name call) — passes none, so the callee takes its first user argument as
the result pointer and writes the vector through it. SysV / AAPCS64 / cx return the vector in registers and are
unaffected.

## Reproduction

```cyrius
fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn run(): i64 {
    mkv(41, 7);
    return 3;
}
syscall(60, run());
```

```cyrius
include "lib/fnptr.cyr"
fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn run(): i64 {
    callptr(&mkv, 41, 7);
    return 3;
}
syscall(60, run());
```

```cyrius
include "lib/fnptr.cyr"
fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn run(): i64 {
    var x = callptr(&mkv, 41, 7);
    return 3;
}
syscall(60, run());
```

Each: x86_64 3, aarch64 (qemu) 3, cx 3, PE (`cat src/main_win.cyr | build/cycc > cc_win`; `cc_win < f.cyr > f.exe`;
wine) exit 5 — "page fault on write access to 0x0000000000000029".

## Root cause

PARSE_FNCALL emits a by-name call to a vector-returning fn with no destination unless a receive asked for one;
`_PINDIRECT_CALL_IN` passes the hidden pointer only for a receive's one-shot `_icall_vbeg` (6.7.11). Neither reserves a
frame temporary for a discarded or untyped result, as the struct-call hooks do for a struct (`_sc_pre` always reserves
one for a retptr-class struct in a fn).

## Proposed fix

On PE, give every vector-returning call with no receive a frame temporary of its vector type and pass its address as
int arg 0 (the struct-call hooks' shape: `_agg_temp_t` with the vector's slot count), in PARSE_FNCALL and in
`_PINDIRECT_CALL_IN` for a known `&f` callee. Rows on PE (wine, then cass): the three repros above exit 3; a crossos row.
Whether an untyped `var x = callptr(&mkv, ..)` should infer the vector, as `var x = mkv(..)` does, is the companion
issue `2026-10-13-vector-call-results-the-receives-do-not-take.md`.

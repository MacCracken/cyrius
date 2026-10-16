# `var t: (i64, i64) = callptr(fp, ..);` is refused "cannot initialize tuple 't' with a value that is not a tuple", where `fncall1(fp, ..)` captures the same call — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-15 on the 6.7.13 multivalue lane (l6713-multivalue at ade43caa, the
review-fix step) and on the lane base b13d3598: identical refusal, x86_64, aarch64 (qemu), cx (cxvm) and PE (wine).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (multivalue lane; filed from the 6.7.13 multivalue lane, placed at the 6.7.13 integration, 2026-10-16) — never 7.x.
**Severity:** Low — refused loudly at compile time; the workaround is `fncall1(fp, ..)` (lib/fnptr.cyr) or the
destructure `var a, b = callptr(fp, ..);`. No wrong value.
**Kind:** gap — the tuple capture's call recognition has no `callptr` arm. 6.7.13 (fe98679b,
issues/2026-10-13-destructure-of-callptr-refused.md) taught the DESTRUCTURE `callptr(` — that issue's filed surface —
and the guide's Multi-Return list names `callptr` as a call; the typed tuple capture is the sibling spelling.
**Discovered:** 2026-10-15, the 6.7.13 multivalue lane's review (probes review/rev/i5/c.cyr, d.cyr).

## Reproduction

```cyrius
fn two(a): (i64, i64) { return (a, a + 1); }
fn main(): i64 {
    var fp = &two;
    var t: (i64, i64) = callptr(fp, 5);
    return t.1;
}
syscall(60, main());
```

```
error:<source>:4:12: cannot initialize tuple 't' with a value that is not a tuple
```

on all four targets (lane and base). Expected: 6, as the two controls below give.

Control 1 — the same capture through `fncall1` runs, exit 6 on x86_64 / aarch64 / cx / PE (lane and base):

```cyrius
include "lib/fnptr.cyr"
fn two(a): (i64, i64) { return (a, a + 1); }
fn main(): i64 {
    var fp = &two;
    var t: (i64, i64) = fncall1(fp, 5);
    return t.1;
}
syscall(60, main());
```

Control 2 — the destructure of the same `callptr` runs since 6.7.13, exit 56 on all four (base: refused "multi-value
destructure needs a call on the right-hand side"):

```cyrius
fn two(a): (i64, i64) { return (a, a + 1); }
fn main(): i64 {
    var fp = &two;
    var c, d = callptr(fp, 5);
    return c * 10 + d;
}
syscall(60, main());
```

## Root cause

`_tup_cap_check` (src/frontend/parse_decl.cyr) takes the capture's call from `_dt_call_open`, which recognises
`name(`, `name<..>(` and `x.m(` only — `callptr` is a builtin token (137), not an IDENT. fe98679b added the
`callptr (` arm to `_dt_rhs_check_t` (the destructure) and deliberately left the shared `_dt_call_open` unchanged, so
the capture still answers 0 ("not a capture") and the declaration refuses the value as no tuple. The global zone's
`_tup_gci_call` (pass 1's whole-call sizing of `var G: (i64, i64) = ...;`) has the same gap.

## Fix sketch

Give the capture the destructure's arm: a `callptr (` at the cursor is a whole call whose callee is unknown
(`_dt_call_fn` answers -1, so the count is not judged — as for `fncallN`), in `_tup_cap_check` and in the global
zone's `_tup_gci_call` / `_gvi_tup_cap`; rows for a local, a top-level declaration in both zones, a three-tuple, and
`callptr(..) + 1` still refused. Nothing that compiles today changes.

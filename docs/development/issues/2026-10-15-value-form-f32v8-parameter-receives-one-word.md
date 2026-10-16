# A value-form `v: f32v8` parameter receives only its first word: `load32(&v + 8)` reads 0 — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-15 on the 6.7.12 fixfirst lane (unit X1, after the D27 bite) and on the
slot-open compiler (`7f57e532`, `build/cycc` 2,223,320 B): the repro below exits 0 on x86_64, x86_64 `CYRIUS_IR=3`,
aarch64 (qemu), cx (cxvm) and PE (wine), where 38 is right.
**Placement:** 6.7.13 — repair 3: struct values (vectors lane; re-placed at the 6.7.13 open, 2026-10-15) — never 7.x.
**Discovered:** 2026-10-15, the triage of `2026-10-13-vector-value-into-pointer-parameter-passes-lane-bits.md` ("found
in passing, not filed on its own"), re-measured by the fixfirst lane, which fixed only the `*f32v8` half (D27).
**Severity:** Medium — compiles clean and computes a wrong value on every target, no diagnostic; `f32v8` is a
documented vector type (guide § Vector types, v6.4.8). Workaround: take `p: *f32v8` and pass `&e` (or `e`, 6.7.12).
**Affects:** every target; the value-form `f32v8` parameter only (`f64v4`, the other 32-byte vector, has its 2-XMM class).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/simd.cyr"
fn lanes8(v: f32v8): i64 { return load32(&v + 8) * 10 + load32(&v + 28); }
fn main(): i64 {
    var e: f32v8 = f32v8_make(1, 2, 3, 4, 5, 6, 7, 8);
    return lanes8(e);
}
var rc = main();
syscall(60, rc);
```

```
x86_64 0, x86_64 CYRIUS_IR=3 0, aarch64 0, cx 0, PE 0      (38 is right: lane 2 = 3, lane 7 = 8)
```

## Root cause

`src/frontend/parse_fn.cyr` `_classify_param_type` has no class for `f32v8` (it knows f64v2 / f64v4 / f32v4 and the
128-bit integer vectors), so both parameter scans (the prescan's mask ladder and the definition's `pt_simd_class`
ladder) see class 0: `v: f32v8` is an ordinary one-word integer parameter, and the caller's value push gives it lane 0's
word. The return side knows f32v8 (`_classify_return_type` -2153, the 32-byte receive). 6.7.12's D27 bite recognises
f32v8 only behind a `*` (`_ptr_vclass`), deliberately leaving the value form as it was.

## Fix direction

Give f32v8 a class in `_classify_param_type` and f64v4's 32-byte / 2-XMM routing in both scans (mask 2; on Win64 the
struct-mask by-pointer copy-in), and the value-form argument path's 256-bit arm (`_simd_arg_typecheck` / the second
pass); rows on x86_64 / aarch64 / cx / PE and a crossos row (the release gate's hosts).

# Global typed sub-i64 scalar (`var G: i8/i16/i32` at top level) SIGSEGVs on load

**Filed:** 2026-07-02 (surfaced while fixing the v6.3.34 local sub-i64 scalar-arithmetic bug)
**Severity:** Default-path miscompile (SIGSEGV), but a RARE pattern — typed sub-i64 *global* scalars.
Most globals are untyped (`var G = 40`, i64), which work. Distinct from the v6.3.34 fix (that was
sub-i64 *local* arithmetic scaling; this is a *global* *load* crash).
**Pre-existing:** reproduces on cc5 (v5.11.69) and the v6.3.33 cycc — ancient, not introduced recently.

## Repro (exit should be 40, actual SIGSEGV / exit 139)

```
var G: i32 = 40;
fn main(): i64 { return G; }
```

Even reading `G` alone crashes. Same for `i8`/`i16`. `var G: i64 = 40` works (42 for `G + 2`),
and untyped `var G = 40` works. So it is specific to a top-level `var NAME: <sub-i64 type>` global.

## Direction

`PARSE_FACTOR`'s GLOBAL-var path (`src/frontend/parse_expr.cyr` ~line 539): `vt = GVTYPE(S, idx)`.
The disambiguation (`vt < 0` → `SPSC(S, 0 - vt)`; `vt > 0` + `var_sizes < 8` → `SEXW`/`EVLOAD_W`)
mis-handles a typed sub-i64 global — the width-load address / scale is wrong, dereferencing a bad
address. Compare against the (now-fixed) LOCAL path and against the untyped-global path. Likely the
global's `var_sizes`/type encoding for a typed sub-i64 scalar is not what `EVLOAD_W` expects, or the
global base address is mis-computed for a narrow width. Add a `subword_global_scalar.tcyr` when fixed.

## Not v6.3.34

v6.3.34 fixes the sub-i64 *local* arithmetic pointer-scaling (`var a: i32; a + 2` → was 48). This
global-load crash is a separate code path; filed for a later default-codegen slot.

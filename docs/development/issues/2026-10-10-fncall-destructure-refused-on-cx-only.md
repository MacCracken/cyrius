# `var t, v = fncallN(..)` is refused on cx only — `crossos/method_pair_result.tcyr` has never built for cx — RESOLVED

> ✅ **RESOLVED in v6.7.9** (the quick lane's bite 1; CHANGELOG [6.7.9]) lib/fnptr.cyr's nine cx arms are
> `return callptr(..);` (candidate 1), so no target proves an `fncallN` body one-valued and `var t, v = fncallN(..)`
> compiles and runs everywhere: the repro exits 83 on x86_64, aarch64 (qemu), PE (wine) and cxvm, and
> `method_pair_result.tcyr` builds for cx for the first time (31/31). The x86_64 / aarch64 / PE outputs are
> byte-identical (the arm is preprocessed out there). Gate rows R10 (the repro verbatim; fncall0..8 each destructured,
> plus the body run through `&fncall1` / `&fncall8`) and R11 (method_pair_result on cxvm) of
> `tests/gates/codegen/cx_crossos_rows_run.sh`, mutation-proven.

**Status:** ✅ **RESOLVED in v6.7.9** — see the banner above. (Filed: reproduced 2026-10-10 against the merged
6.7.8 tip (l678-int @ 85ee576f, `cycc_merged` 2,053,536 B): the repro exited 83 on x86_64, aarch64 (qemu) and PE
(wine), and the cx compiler (`src/main_cx.cyr`) refused it; `method_pair_result.tcyr` failed for cx at line 79 and no
gate compiled it there.)
**Placement:** 6.7.9 — the repair batch, the quick-fix lane (user, 2026-10-11) — shipped.
**Discovered:** 2026-10-10 by the 6.7.8 checked-`dyn` lane, bite D1 (reported only, `~/.cache/c6/dyn_handoff.md` § D1
*Out of scope*).
**Severity:** Medium — a hard failure on one target for source the other three compile; the crossos file's cx coverage
silently missing.
**Affects:** cycc 6.6.17 (the one-value refusal) – 6.7.8, cx only: the installed 6.6.16 `cycc_cx` compiles the repro;
6.6.17, 6.7.4, 6.7.7 and the merged 6.7.8 tip refuse it.

## Summary

A destructure of a `fncallN` call — `var t, v = fncall1(g, d);`, the form `method_pair_result.tcyr` uses to read a
pair-returning closure through a fn pointer — compiles on x86_64, aarch64 and PE and is refused on cx. The refusal is
6.6.17's "this callee provably returns one value" check, and on cx lib/fnptr.cyr's `fncallN` body IS provably one
value, while on the other targets it is not. The same source has two meanings by target.

## Reproduction

`docs/development/issues/repros/2026-10-10-fncall-destructure-refused-on-cx-only.cyr`:

```cyrius
include "lib/syscalls.cyr"
include "lib/fnptr.cyr"
fn g(d): (i64, i64) { return (d, d + 1); }
fn main(): i64 {
    var t, v = fncall1(&g, 41);
    return t + v;
}
var rc = main();
syscall(60, rc);
```

```
x86_64 / aarch64 (qemu) / PE (wine):  exit 83
cx:  error:<source>:9:16: multi-value destructure binds 2 names, but 'fncall1' returns 1 value - bind it to one name: `var x = f(..);`
```

Build the cx compiler with `build/cycc < src/main_cx.cyr > /tmp/cycc_cx`, then `cat <repro> | /tmp/cycc_cx > /tmp/r.cyx`.

## Root cause

- `_prescan_ret_single` (`src/frontend/parse_fn.cyr:12448`) sets GFLG bit 1024 ("provably one value") on a body whose
  every `return` is one value and that holds no `asm` block, and `_dt_arity_check` (`src/frontend/parse_decl.cyr:5969`,
  the test at `:5981`) refuses a two-name destructure of such a callee.
- lib/fnptr.cyr's `fncall0` … `fncall8` (`:107`, `:180`, `:253`, `:332`, `:417`, `:508`, `:608`, `:733`, `:867`) are an
  `asm` block per target. After the preprocessor, the x86 and aarch64 bodies keep their `asm`, so the bit stays clear;
  the cx arm is `result = callptr(fp, ..); return result;` (`:174`, `:247`, `:326`, `:411`, `:502`, `:602`, `:709`,
  `:854`, `:1000`), which is provably one value, so the bit is set on cx alone.

## Proposed fix

Make the answer the same on every target. Two candidates (the lane picks, the user decides at the open):

1. **lib/fnptr.cyr** — each cx arm `return callptr(fp, ..);` (a call result is not provably one value, so the bit stays
   clear, as on x86). Measured: a wrapper `fn myfc1(fp, a) { return callptr(fp, a); }` destructured against the repro's
   `g` exits 83 on x86_64, aarch64 (qemu), cx (cxvm) and PE (wine) — cx's `callptr` carries the second register through.
   A lib/ edit is high priority under the standing rule; it is the user's call only because the cx compiler starts
   compiling the shape.
2. **`_dt_arity_check`** — skip the `fncall0..8` names (they are intrinsics recognised by name elsewhere), as it skips
   a `: stack` pair.

Rows: the repro on the four targets plus cxvm; `method_pair_result.tcyr` added to the cx leg (a `cx_crossos_rows_run.sh`
row), so a crossos file that does not build for cx is no longer invisible.

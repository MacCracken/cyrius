# A known `&f` callee's non-struct result is an untyped word: `var w: *P2 = fncall0(&gp);` draws the typed-pointer warning, `var a = fncall0(&f);` with `f: f64` binds an integer — RESOLVED

> ✅ **RESOLVED in v6.7.14** (RC-10, `94e980e2` — the user's decisions D25 (a) and D26 (a), 2026-10-16: "as the direct call": `fncallN(&f, ..)` / `callptr(&f, ..)` with `f` declared `: f64` is an f64 whatever its arguments (6.7.6's last-argument rule is gone), and with `f` declared `: *T` it is a `*T` (`_icall_scalar`; the step recorded against the call token and kept by `_call_scale_fix`; `_var_rhs_if64`). Filed repro 1 exits 33 with no typed-pointer warning; filed repro 2 exits 4 with no warning (it exited 0); `var a = callptr(&f);` is 4; `fncall0(&gp) + 1` steps one `P2` (16 bytes, it stepped 1) — on x86_64, aarch64, cx and PE. A callee held in a variable stays a word (6.7.11's D31). The filed fix's `: f32` half has no shape: `f32` is not a fn return type. Rows: NEW `crossos/fncall_scalar_result.tcyr` (18; also on pi and cass); `diagnostics/typed_pointer_warn_sign.sh` axis 13 (K0 the repro 1 verbatim, `docs/development/issues/repros/2026-10-16-known-callee-pointer-or-f64-result-untyped.cyr`); `diagnostics/f64_int_mix_warn.sh` axis 19 (repro 2 verbatim, `…-untyped-f64.cyr`); `crossos/struct_value_codegen.tcyr` I13 changed by decision; mutations RED. Not closed here (filed, 6.7.15): `*fncall0(&bp)` of a `*u8` callee reads a word and `fncall0(&bp)[1]` is refused (`2026-10-17-known-callee-narrow-pointer-result-deref-reads-a-word-and-subscript-refused.md`); `var b: bool = fncall0(&isb);` is refused "not a bool" (`2026-10-17-known-callee-bool-result-not-a-bool.md`). CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-16 by the 6.7.13 receives fix step on the lane tree (l6713-receives at
360a6d05) and the lane base (f59668ad's `build/cycc`): identical on x86_64, aarch64 (qemu), cx (cxvm), PE (wine).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (receives + multi-value lane, wave 2, unit R3; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Decision (user, 2026-10-16, at the 6.7.14 open):** D25 — (a); D26 — (a).
**Severity:** Low — a false warning on the `*T` row; on the f64 row a wrong value, but with a kind-1 warning
("integer arithmetic with an f64 right operand") on the line that uses it.
**Discovered:** 2026-10-16, the receives lane's review of the D15 / D16 bites (1330b9ed, 5a73a702). 6.7.11 gave a
KNOWN callee (`fncallN(&f, ..)` / `callptr(&f, ..)`) the struct-result convention, and D15 / D16 its dyn result and its
`.field`; a `*T` or `: f64` result is outside those surfaces.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/fnptr.cyr"
struct P2 { a; b; }
var G: P2 = P2 { 11, 22 };
fn gp(): *P2 { return &G; }
fn main(): i64 {
    var w: *P2 = fncall0(&gp);
    var x: *P2 = gp();
    return w.b + x.a;
}
syscall(60, main());
```

```
warning:<source>:8:30: assigning non-pointer to typed pointer      (line 8 only; the direct call on line 9 is quiet)
exit 33 on all four
```

```cyrius
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/fnptr.cyr"
fn f(): f64 { return f64_from(5) / f64_from(2); }
fn main(): i64 {
    var a = fncall0(&f);
    var y = a + 1.5;
    return f64_to(y);
}
syscall(60, main());
```

```
warning:<source>:7:20: integer arithmetic with an f64 right operand
exit 0 on all four
```

With `var a = f();` the same program exits 4 with no warning; `var a = callptr(&f);` behaves as `fncall0(&f)` (0, the
warning).

## Root cause

The known-callee hooks (6.7.11, src/frontend/parse_expr.cyr / parse_decl.cyr) carry a struct, vector or dyn result;
for any other declared return the call leaves the expression untyped: no pointer scale for a `*T` (so the typed-pointer
check reads a non-pointer) and no f64 kind for the untyped receive (`var a = f();` is judged after the parse from the
callee's `: f64`; the `&f` form is not).

## Fix

Where the known callee is resolved, set the result's pointer scale from a `: *T` return and its float kind from a
`: f64` / `: f32` return, as the direct call does. Rows: the two programs above quiet and 33 / 4 on four legs; a callee
held in a variable unchanged (its result stays a word).

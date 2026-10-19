# `var x: f64 = mkv(41, 7);` (a by-name call declared to return a vector) compiles and stores a word, where the method spelling is refused since 6.7.14 — RESOLVED

> ✅ **RESOLVED in v6.7.15** (VC-6, `024a5e421`, and the VC-6r review fix `2e8b3d14f` — no decision needed: the v6.5.61 rule, and parity with 6.7.14's D38 method arm, which 6.7.15's D67 keeps and whose text names this fix. PARSE_VAR's vector block infers the callee's vector only when the declaration has no annotation (`ann_ti == 0`). The filed repro `var x: f64 = mkv(41, 7);` is refused once, "vector return type does not match the declared type", on x86_64, IR=3, aarch64, cx and PE; it compiled and exited 3. `: f32`, `: bool`, `: cstring`, an enum, `: Vec`, `: Result`, `: Option` and an explicit instance are refused the same way. Rows: `simd_return_shapes.sh` NK1 (the filed repro verbatim) – NK14, and the control N1 (`: f64v2` and untyped, 161), on the five legs. Mutation M-N1: RED 45. CHANGELOG [6.7.15])

**Status:** ✅ **RESOLVED in v6.7.15** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-17 by the 6.7.14 release-docs pass on main (build/cycc after the vectors
lane, and on the wave-2 base c3af6501), x86_64: the by-name declaration compiles (exit 3; reading the word back gives
41), while the by-name assignment `x = mkv(..)` into an f64 is refused, and since the vectors lane's VC-14 (D38) the
method `var x: f64 = s.mv();` is refused too.
**Placement:** 6.7.15 — repair 5 (vectors lane, wave 2, unit V2; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Severity:** Medium — a silent wrong value: an `f64` declared from a vector-returning call holds the vector's first
lane's bits as a word.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
fn mkv(a, b): f64v2 { var v: f64v2; store64(&v, a); store64(&v + 8, b); return v; }
fn main(): i64 { var x: f64 = mkv(41, 7); return 3; }
syscall(60, main());
```

Compiles (exit 3). Expected (6.7.14's D38 parity, "refused as `var x: i64 = mkv(41, 7);` is"): refused "vector return
type does not match the declared type", as the method spelling and the by-name assignment are.

## Fix

The by-name declaration's vector-receive check (the PARSE_VAR receive that refuses an `i64` destination) treats `: f64`
as a scalar destination too; a row beside VC-14's in tests/gates/codegen/simd_return_shapes.sh (the by-name and method
declarations into `f64`, both refused).

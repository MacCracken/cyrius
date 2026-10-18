# A struct-typed FIELD passed to a `*V` parameter (`rd(w.s)`, `s: Pt`, `p: *f64v2`) is accepted silently, where D33 refuses the same struct from a local, a call, `*ps`, a global or a capture — RESOLVED

> ✅ **RESOLVED in v6.7.14** (VC-12, `f0f9ffa16` (the user's decision D34, 2026-10-16: A — refuse by name). `_fla_addr` asks `_sarg_svec_err` when the parameter records no struct — the one line the filing proposed, gated on a `*V`; an operator's right operand shares it. The filed repro (`rd(w.s)`, `s: Pt`, `p: *f64v2`) exited 42 on x86_64, IR=3, aarch64, cx and PE with no diagnostic. It now prints `9:18: cannot pass 's' to a parameter that is a pointer to a vector type in a call to 'rd'` once, on every leg and the four hosts. The same holds wrapped, through a `*W`, for a global's, capture's or nested field, into a method's, generic's, `#inline` or operator fn's `*V` parameter, and at top level. `rd(&w)`, `rd(&w + 0)` and `rq(w.s)` into `*Pt` still pass. Rows: `simd_pointer_param.sh` SF1 (the filed repro verbatim) – SF11 and SFok. Mutation M-SF RED 40. CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-16 on the 6.7.13 vectors lane (unit V3, after the D33 bite,
issues/archived/2026-10-15-struct-into-vector-pointer-parameter-accepted.md): the repro compiles with no diagnostic and exits 42
on x86_64, x86_64 `CYRIUS_IR=3`, aarch64 (qemu), cx and PE (wine) — `rd` reads the field's struct bytes as an `f64v2`.
The lane base (before D33) gives the same 42 on all five.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (vectors lane, wave 3, unit V4; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Decision (user, 2026-10-16, at the 6.7.14 open):** D34 — A.
**Severity:** Low — no fault (the address is a real object's); a type mismatch D33 names for every other struct source.
**Kind:** language — beyond D33's filed surface (a local, a call result, `*ps`, a global, a capture), so not absorbed:
D33 A ("refuse by name") would cover it if the user reads a field as one of its sources.
**Discovered:** 2026-10-16, the 6.7.13 vectors lane (V3), probing D33's sources.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/simd.cyr"
struct Pt { x; y; }
struct W { s: Pt; k; }
fn rd(p: *f64v2): i64 { return load64(p); }
fn main(): i64 {
    var w: W;
    w.s.x = 42; w.s.y = 7;
    return rd(w.s);            # a struct FIELD into `*f64v2`: rd(s) on a local is refused (D33)
}
var rc = main();
syscall(60, rc);
```

```
x86_64 42, IR=3 42, aarch64 42, cx 42, PE 42      (no diagnostic)
the same shape from a local (`var s: Pt; .. rd(s)`), 6.7.13 after D33, every target:
error:<source>:5:58: cannot pass 's' to a parameter that is a pointer to a vector type in a call to 'rd'
```

## Root cause

A whole struct-typed field argument to an address-passed parameter takes `_fla_push_arg` → `_fla_addr`
(src/frontend/parse_fn.cyr), which checks the field's struct against the parameter's recorded struct itself
(`GFPSID` > 0 and different → "a different struct type") and never calls `_sarg_type_err`, where D33's `*V` arm
(`_sarg_svec_err`) lives — a `*V` records no struct, so the field passes unchecked.

## The question

Refuse a struct field into a `*V` parameter by name, as D33 refuses every other struct source (one line in
`_fla_addr`: when `GFPSID <= 0`, `_sarg_svec_err(S, fi, argc, _fla_name)`), or keep accepting it?

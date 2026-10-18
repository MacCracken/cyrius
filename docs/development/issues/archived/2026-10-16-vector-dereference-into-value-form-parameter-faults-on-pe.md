# A `*V` dereference passed to a value-form vector parameter (`lanes(*pb)`, `pb: *f64v2`, `fn lanes(x: f64v2)`) is refused on x86_64 / aarch64 / cx and compiles to a page fault on PE — RESOLVED

> ✅ **RESOLVED in v6.7.14** (VC-5, `3a07bf012`, and the review fix VC-4r, `986123203`, with a gate-line fix in `2dac1d544` (the user's decision D32, 2026-10-16: A — copy through the pointer on every target). `_sar_one` takes a whole `* E` (`_sar_deref`): it parses E, reads its vector from the step word or an `&x`, checks it by the local's class rule, and copies the 16 / 32 bytes through the pointer where the argument stands. Windows pushes the pointer (its callee copies from it), snapshotted first when a later argument may write through it. The filed repro (`lanes(*pb)`) was refused on x86_64, IR=3, aarch64 and cx (`4:85: .. got `*pb``) and was a page fault on PE (exit 5). It now exits 42 on all five. So do `(*pb)`, `**ppb`, `*gp(pb)`, `*&b`, an f64v4, a closure's `*pb` and an `#inline` fn's. Another class is refused with the local's words; an f32v4 `*pf` into `x: f64v2` passes by that rule — wider than D32's option text, and listed. A `*q` of no vector keeps the by-name refusal, whose list now names "a dereference of a pointer to its type (`*p`)". VC-4r: `|k| li(lanes(*pb), k)` read a clobbered copy until a closure's frame took the `_flc_hwm` high-water. Rows: `simd_pointer_param.sh` VZd1 (the filed repro verbatim), VZd2 (eleven shapes), VZdY1 – VZdY3 and VCi2, on five legs; `crossos/simd_pointer_param.tcyr` `sp_drows`. Mutations M-VZd1 – M-VZd3 RED. CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-16 on the 6.7.13 vectors lane (unit V2, after D30's bite) and on its base
compiler (V1) alike.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (vectors lane, wave 3, unit V2; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Decision (user, 2026-10-16, at the 6.7.14 open):** D32 — A.
**Severity:** Medium — PE compiles valid-looking source to a crash with no diagnostic; the other targets refuse it.
**Affects:** PE (the crash); x86_64 / aarch64 / cx (refused); every value-form vector parameter.
**Discovered:** 2026-10-16, the vectors lane (V2). D30's PE parity arm (`_sarg_pe_vword`, parse_fn.cyr) refuses a WORD
pushed to a Win64 value-form parameter (the filing's pw.cyr), but a dereference never reaches it: `_try_push_struct_addr_arg`
sends a leading `*` to `_sarg_deref` → `_push_struct_expr_arg`, which pushes the value it read (lane 0) itself. Related
decision: D34 (`archived/2026-10-13-vector-dereference-into-vector-local-decision.md`: `var v: f64v2 = *p;` copies the vector
through the pointer) — a value-form parameter is the callee's vector local, so the same question reaches here.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/simd.cyr"
fn lanes(x: f64v2): i64 { if (load64(&x) == 999) { return 0; } return load64(&x) * 10 + load64(&x + 8); }
fn main(): i64 { var b: f64v2 = f64v2_make(4, 2); var pb: *f64v2 = &b; return lanes(*pb); }
var rc = main(); syscall(60, rc);
```
```
V2:   x86_64 / IR=3 / aarch64 / cx: error:<source>:4:85: a value-form vector argument to 'lanes' is a local of its type
      or a call declared to return it (by name, a method, or fncallN / callptr with the callee written `&f`) - got `*pb`
      PE (wine): compiles, exit 5 (a page fault: lane 0, 4, taken as the vector's address)
base: x86_64 / IR=3 / aarch64 / cx: error:<source>:4:85: value-form SIMD arg must be a local IDENT (caller-side
      scratch + addr-eval path not in v5.10.38 scope); PE: exit 5
```

## Root cause

Win64 passes a value-form vector parameter by address (struct mask). For a whole `*pb`, `_sarg_deref` parks the pointer
only when the parameter is a `*V` or (since D31) a pointer of another kind / a by-value struct (`_dro_vt_for`); for a
value-form vector parameter nothing parks it, and `_push_struct_expr_arg` pushes the loaded word.

## Proposed fix

A question for the user, following D34: either pass `pb` itself on Win64 (the address the by-address parameter copies
from) and receive `*pb` into the vector second pass's slots on SysV / AAPCS64 / cx (copy through the pointer) — or
refuse it by name on PE too (`_dro_vt_for` arming for a value-form parameter, `_dro_vcheck` refusing with
`_sar_err`'s words). Recommended: the first, as D34 decided for the vector local. Rows beside simd_pointer_param.sh's VZ
rows on x86_64 / IR=3 / aarch64 / cx / PE.

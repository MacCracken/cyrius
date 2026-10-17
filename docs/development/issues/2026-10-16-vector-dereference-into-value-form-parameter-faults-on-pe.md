# A `*V` dereference passed to a value-form vector parameter (`lanes(*pb)`, `pb: *f64v2`, `fn lanes(x: f64v2)`) is refused on x86_64 / aarch64 / cx and compiles to a page fault on PE — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-16 on the 6.7.13 vectors lane (unit V2, after D30's bite) and on its base
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

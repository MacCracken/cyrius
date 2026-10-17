# On PE a struct local passed to a value-form vector parameter (`lanes(p)`, `p: Pt`, `fn lanes(x: f64v2)`) is passed — the callee reads the struct's bytes as the vector — where x86_64 / aarch64 / cx refuse it — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-16 on the 6.7.13 vectors lane (unit V2) and on its base compiler (V1) alike.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (vectors lane, wave 3, unit V1; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Severity:** Low — no fault (the address is a real object's); a type mismatch PE does not name where the other three
refuse it by name.
**Affects:** PE only; every value-form vector parameter.
**Discovered:** 2026-10-16, the vectors lane (V2), probing D30's PE parity arm (`_sarg_pe_vword`, which refuses a WORD
pushed to a Win64 value-form parameter — the issue's pw.cyr — but not a struct, whose address is pushed). Related, not
the same shape: staged `2026-10-16-pe-16-byte-value-form-vector-argument-unchecked.md` (a vector local of another type).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/simd.cyr"
fn lanesn(x: f64v2): i64 { if (load64(&x) == 999) { return 0; } return load64(&x) * 10 + load64(&x + 8); }
struct Pt { x; y; }
fn main(): i64 { var p: Pt; p.x = 4; p.y = 2; return lanesn(p); }
var rc = main(); syscall(60, rc);
```
```
x86_64 / IR=3 / aarch64 / cx: error:<source>:5:62: value-form SIMD arg must be a 16-byte vector
PE (wine): compiles, exit 42 (the struct's two words read as the f64v2's lanes)
```

## Root cause

On Win64 a value-form vector parameter is address-passed under the struct mask; `_try_push_struct_addr_arg`
(parse_fn.cyr) pushes a struct local's address after `_sarg_type_err`, which compares struct ids only (the parameter
records none), so nothing checks that the parameter is a vector. SysV / AAPCS64 / cx run `_simd_arg_typecheck`.

## Proposed fix

On PE, a struct value (local, by-value parameter, global, call result, `*ps`) into a value-form vector parameter
(`_pvf_param`) is refused with the SysV words — the mirror of D27's "a vector is not a `*Pt`" and the issue
`archived/2026-10-15-struct-into-vector-pointer-parameter-accepted.md` (D33, a struct into `*V`). Rows on PE beside
simd_pointer_param.sh's VZ rows.

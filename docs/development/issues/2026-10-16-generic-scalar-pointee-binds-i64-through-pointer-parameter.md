# A scalar pointer (`*i32`, `*f64`, `&h`) through a generic's `p: *T` binds i64, not its pointee: `second(pa)` with `pa: *i32` steps 8 bytes — DECISION — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-16 by the 6.7.14 generics lane (unit G5) on the lane's tree after the D8 (a)
commit (`4e039c6e`), x86_64; identical on the slot-open compiler (2600f67f's build/cycc).
**Placement:** 6.7.15 — repair 5 (generics lane, wave 1, unit G4; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Decision (user, 2026-10-18, at the 6.7.15 open):** D11 — (a) Yes, through `p: *T` and `pp: **T` alike.
**Discovered:** 2026-10-16, 6.7.14 generics G5, implementing D8 (a) (issues/archived/2026-10-14-generic-pointer-parameter-binds-only-from-pointer-local-decision.md):
the user's decision binds a `p: *T` parameter's T to what a `*S` STRUCT pointer points at; a scalar pointee was outside
the filed surface and still infers i64.
**Severity:** Medium — silent: the call runs the i64 base, so `sizeof(T)` is 8, `p + 1` steps 8 bytes and `*p` reads 8,
over an `i32` array; the explicit `second<i32>(pa)` is right.
**Kind:** language — which fn an existing call runs (the base or a scalar instance), so the user's call.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
fn gsz<T>(x: *T): i64 { return sizeof(T); }
fn second<T>(p: *T): i64 { var q = p + 1; return *q; }
fn m(): i64 {
    var a: i32[4];
    a[0] = 7; a[1] = 9; a[2] = 11; a[3] = 13;
    var pa: *i32 = &a;
    var h: f64 = 1.5;
    return gsz(pa) * 10000 + gsz(&h) * 1000 + gsz<i32>(pa) * 100 + second(pa) * 0 + second<i32>(pa);
}
fn m2(): i64 { var a: i32[4]; a[0] = 7; a[1] = 9; a[2] = 11; a[3] = 13; var pa: *i32 = &a; return second(pa); }
syscall(60, m() % 256);
```

```
m():  exit 89   = (8 * 10000 + 8 * 1000 + 4 * 100 + 9) % 256: gsz(pa) 8, gsz(&h) 8, gsz<i32>(pa) 4, second<i32>(pa) 9
m2(): exit 11   (`second(pa)` inferred: the base steps 8 bytes and reads a[2]'s word; 9 is a[1])
```

## The question

Does a `p: *T` parameter bind a SCALAR pointee — `pa: *i32` binds `i32`, `&h` / a `*f64` binds `f64` — as D8 (a) binds
a struct pointee? (a) yes, for every scalar a type argument may be (i8 / i16 / i32 / i64 / f64; `*u8` .. `*u64`, `*f32`,
`*bool` are no type arguments and stay i64, or are refused); (b) no — keep i64 and document it (the guide's pointer
paragraph names struct pointees only).

## Root cause

`_infer_conc_at` (src/frontend/parse_fn.cyr) binds through `p: *T` only a struct: `_ic_ptr_slot` answers a slot type
`0 - sid`; a `*i32` local's slot is a pointer with a step mark (`_sl_marks`), and `&h` reaches `_ic_addr`, whose
`_gsc_addr_of` reads struct locals and globals only. A `*f64` reads `_load_lt` as a pointer word, not F64_TYID.

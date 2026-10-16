# A vector call result or `*pv` into a pointer of another kind (`*Pt`, `*i64`), a vector local into a by-value struct parameter, and a vector METHOD or explicit-instance call result into `*V`, pass lane 0's bits as the address — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-15 on the 6.7.12 fixfirst lane (unit X1, after the D27 bite, which covers a
vector LOCAL into another pointer kind and a by-name / `&f` call result and `*pv` into `*V`) and on the slot-open
compiler (`7f57e532`): every shape below compiles with no diagnostic and faults.
**Placement:** 6.7.13 — repair 3: struct values (vectors lane; re-placed at the 6.7.13 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.13 open):** D31 — A.
**Discovered:** 2026-10-15, the fixfirst lane, probing D27's neighbours beyond the filed surface of
`2026-10-13-vector-value-into-pointer-parameter-passes-lane-bits.md` (a named local into `*Pt` / `*i64`, a call result
and `*pv` into `*V`, `*f32v8`).
**Severity:** Medium — compiles clean and faults on every target, no diagnostic.
**Affects:** every target, every vector type.

## Reproduction

Each `main` below, with this head:

```cyrius
include "lib/syscalls.cyr"
include "lib/simd.cyr"
struct Pt { x; y; }
struct S2 { k; }
impl S2 { fn mv(self, a, b): f64v2 { return f64v2_make(a, b); } }
fn rp(p: *Pt): i64 { return p.x; }
fn ri(p: *i64): i64 { return *p; }
fn bv(p: Pt): i64 { return p.x; }
fn rd(p: *f64v2): i64 { return load64(p); }
fn mkv(a, b): f64v2 { return f64v2_make(a, b); }
fn mkg<T>(a: T, b: T): f64v2 { return f64v2_make(a, b); }
```

| # | `fn main(): i64 { .. }` | x86_64 | IR=3 | aarch64 | cx | PE |
|---|---|---|---|---|---|---|
| 1 | `return rp(mkv(42, 7));` (a call result into `*Pt`) | 139 | 139 | 139 | 253 | 5 |
| 2 | `return ri(mkv(42, 7));` (into `*i64`) | 139 | 139 | 139 | 253 | 5 |
| 3 | `var b: f64v2 = f64v2_make(42, 7); var pb: *f64v2 = &b; return rp(*pb);` | 139 | 139 | 139 | 253 | 5 |
| 4 | `var b: f64v2 = f64v2_make(42, 7); var pb: *f64v2 = &b; return ri(*pb);` | 139 | 139 | 139 | 253 | 5 |
| 5 | `var b: f64v2 = f64v2_make(42, 7); return bv(b);` (a vector local into a by-value struct) | 139 | 139 | 139 | 253 | 42 (by accident) |
| 6 | `var s: S2; return rd(s.mv(42, 7));` (a vector METHOD result into `*V`) | 139 | 139 | 139 | 253 | 7 (wrong) |
| 7 | `return rd(mkg<i64>(42, 7));` (an explicit-instance call result into `*V`) | 139 | 139 | 139 | 253 | 5 |

The slot-open compiler gives the same (x86_64 139 for each).

## Root cause

D27 (`src/frontend/parse_fn.cyr`): `_sarg_vec_call` takes a whole call into a `*V` parameter only — by name (`IDENT (`,
`_vrcv_vcall`) or `fncallN(&f, ..)` / `callptr(&f, ..)` — so a method (`s.mv(..)`) or an explicit instance
(`mkg<i64>(..)`) is pushed as its value, lane 0 (rows 6-7: the receive paths do not take them either —
`2026-10-14-explicit-instance-vector-result-not-received.md`, `2026-10-13-vector-call-results-the-receives-do-not-take.md`).
`_dlo_vec` parks `*pv` only for a `*V` parameter, and `_vec_kind_err` refuses only a named vector LOCAL into another
pointer kind (`_sarg_vec_ptr`, `_sarg_vec_other`), so rows 1-4 keep the value push. Row 5: a by-value struct parameter
over 8 B is address-passed, and `_sarg_vec_ptr` returns `_TARGET_PE` for any parameter that is no `*V` and no pointer —
the value push off Win64.

## The question (rows 1-5; rows 6-7 are D27's own rule once the sources are typed)

D27 refused a vector local into another pointer kind by name. Do the other vector values (rows 1-4) and a by-value
struct parameter (row 5) follow it — refused by name ("a vector value is not a `*Pt`") — as the natural extension?

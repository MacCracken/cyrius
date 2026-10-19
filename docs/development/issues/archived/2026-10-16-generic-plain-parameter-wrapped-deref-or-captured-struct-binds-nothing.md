# Through a generic's plain `x: T` / `p: *T` parameter, a struct argument in parentheses, a whole dereference and a closure-captured struct bind nothing (a struct carrier binds all three since 6.7.11) — RESOLVED

> ✅ **RESOLVED in v6.7.15** (GN-15, `7c56f28e5` (the user's decision D12 (a), 2026-10-18: as the plain spelling), and its review fix GN-15r, `e1ef54e6e`: `_ic_arg` steps into a whole-argument wrap, reads a whole dereference through `x: T` as the struct it reaches, and `_ic_cap` binds a captured struct value. Each row of the filed table that exited 8 exits 24 (`gs((l))`, `gs(*p)`, the captured `gs(l)`, `gsz((p))`, `gsz((&GS))`), and the captured `gsz(l)`, refused "cannot pass 'l' to a parameter that is not a pointer to its struct type", compiles and returns 24, passing the capture's copy's address — on x86_64, IR=3, aarch64, cx and PE. A parenthesised scalar binds as its plain spelling too (`g((h))` with `h: f64` is the f64 instance, 7 -> 3) — beyond D12's text, which named struct spellings. A captured f64 through `x: T` still binds i64 (filed: docs/development/issues/2026-10-18-generic-captured-f64-binds-i64-through-plain-parameter.md, 6.7.16, a decision). Rows: `generic_ptr_param_infer.sh` WD0 - WD6 (the filed table verbatim), WDT, WDS1, WDS2 and WDV (the new `tests/tcyr/crossos/generic_wrapped_argument_binding.tcyr`, 19 rows); mutations MW1 - MW4 each RED. CHANGELOG [6.7.15])

**Status:** ✅ **RESOLVED in v6.7.15** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-16 by the 6.7.14 generics lane (unit G5) on the slot-open compiler (2600f67f's
build/cycc) and on the lane's tree after the D8 (a) commit (`4e039c6e`): identical, x86_64.
**Placement:** 6.7.15 — repair 5 (generics lane, wave 1, unit G4; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Decision (user, 2026-10-18, at the 6.7.15 open):** D12 — (a) Yes, as the plain spelling.
**Discovered:** 2026-10-16, 6.7.14 generics G5, probing D8 (a)'s spellings
(issues/archived/2026-10-14-generic-pointer-parameter-binds-only-from-pointer-local-decision.md); outside its filed surface.
**Severity:** Low — silent where it compiles (the i64 base runs: `sizeof(T)` 8 for 24); a loud refusal for a captured
struct into `p: *T`. Workaround: spell the type argument (`gs<S>((l))`), or bind to a local first.
**Affects:** every target (frontend); ≤ 6.7.13 and the 6.7.14 lane tree.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
struct S { v; w; x; }
var GS = S { 5, 8, 3 };
fn gsz<T>(x: *T): i64 { return sizeof(T); }
fn gs<T>(x: T): i64 { return sizeof(T); }
fn m(): i64 { <row> }
alloc_init();
syscall(60, m());
```

```
<row>                                                                  exit (24 = T bound to S)
var l = S { 1, 2, 3 }; return gs(l);                                   24   (the control: a struct local)
var l = S { 1, 2, 3 }; return gs((l));                                 8
var p: *S = &GS; return gs(*p);                                        8
var l = S { 1, 2, 3 }; var f = || gs(l); return fncall0(f);            8
var l = S { 1, 2, 3 }; var f = || gsz(l); return fncall0(f);           rc 1: error:<source>:7:53: cannot pass 'l' to a
                                                                       parameter that is not a pointer to its struct type
                                                                       in a call to 'gsz' - pass &l for its address
var p: *S = &GS; return gsz((p));                                      8    (D8 (a): `gsz(p)` is 24)
return gsz((&GS));                                                     8    (D8 (a): `gsz(&GS)` is 24)
```

Through a struct carrier the same spellings bind (6.7.11, guide § Generic Functions: "Parentheses around the WHOLE
argument and a whole dereference of such a pointer bind `T` as the plain spelling does").

## Root cause

`_infer_conc_at` (src/frontend/parse_fn.cyr) reads a NAME, a call, a float literal and (6.7.14) `&name` at the
argument's first token: a `(` or a `*` there answers i64, and a capture is read only through `p: *T` and only when it
is a `*S` (`_ic_cap`); the carrier reader `_gsc_arg` has `_gsc_wrap` / `_gsc_deref` arms for the first two.

# The struct assignment's and the small-struct return's refusals name a method result by its mangled fn name (`'Pt_dup'`, `` `Pt_t1` ``) — RESOLVED

> ✅ **RESOLVED in v6.7.15** (VC-10, `c9e95759d` + `fb97cf7d9`, and VC-11, `112c75d1f` — no decision needed: diagnostics only. Every struct refusal at a destination prints the method result through `_fn_src_name`. `_err_ident_fn` keys the report on the record's own name; `_ess_fi`, `_rcv_fi` and `_spi_pfi` carry the fn; `_refuse_toplevel_struct_call` resolves its callee. On x86_64, IR=3, aarch64, cx and PE, the filed repro prints "got `Pt.t1` (a `T1`)" and "cannot copy 'Pt.dup' into a variable of a different struct/vector type: 'w'". The field, `*Q`, `: i64`, assignment, literal-element and top-level refusals print the same spelling, and a top-level explicit instance prints `mkg<i32>`. A free fn whose name looks mangled keeps it. VC-11: the refused `w = s.dup();` ends its statement, so the spurious "assigning non-pointer to typed pointer" beside it (met in passing) is gone. Rows: `struct_arg_type_refused.sh` DN1 / DN1b (the filed repro verbatim) – DN13, DNK1 – DNK4 and DNW1 – DNW3, on x86_64, aarch64, cx and PE. The method rows of seven other gates moved to the source spelling (`call_result_field.sh`'s in `fb97cf7d9`). Mutations: RED 15 (DN), RED 1 (DNK1), RED 2 (DNW). CHANGELOG [6.7.15])

**Status:** ✅ **RESOLVED in v6.7.15** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-17 on the 6.7.14 vectors lane (unit V4, after a4d4e8b58, which names a
method-result ARGUMENT as the source spells it in the struct-type and `*V` argument refusals): two neighbouring
destinations still print the struct-call record's fn name. Frontend: x86_64, aarch64, cx and PE alike.
**Placement:** 6.7.15 — repair 5 (vectors lane, wave 2, unit V4; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Severity:** Low — a diagnostic names `Pt_dup` where the source says `s.dup()`; the position and the refusal are right.
**Kind:** bug (diagnostic).
**Related:** docs/development/issues/archived/2026-10-16-struct-argument-refusal-names-method-result-by-mangled-name.md (the
ARGUMENT side, fixed by a4d4e8b58: the struct-call record keeps its fn, `_sc_fi`, and `_sarg_ident_err` prints it
through the frontend lane's `_fn_src_name`); docs/development/issues/archived/2026-10-15-call-diagnostics-name-method-by-mangled-name.md
(the CALLEE side, fixed by the frontend lane, cb75b8b7).

## Reproduction

```cyrius
struct Pt { x; y; }
struct Q { a; b; c; }
struct T1 { w; }
struct T2 { w; }
impl Pt { fn dup(self): Pt { return self; } fn t1(self): T1 { var t: T1; return t; } }
fn rt(s: *Pt): T2 { return s.t1(); }
fn run(): i64 {
    var s: Pt;
    var w: Q;
    w = s.dup();
    return 0;
}
syscall(60, run());
```

```
x86_64, aarch64 (cross), cx, PE (cross) — identical:
error:<source>:6:28: a fn returning the struct `T2` takes a value of that struct, or a pointer to one — got `Pt_t1` (a `T1`)
error:<source>:10:16: cannot copy 'Pt_dup' into a variable of a different struct/vector type: 'w'
```

`Pt.t1` / `Pt.dup` would be the source spelling the argument and callee refusals print since a4d4e8b58 / cb75b8b7.

## Root cause

Both read the struct-call record's name `_sc_fn` (the resolved callee, for a method the mangled `T_m`):
`_ret_small_val` -> `_ret_sid_refuse(S, st, _ess_nm, ..)` with `_ess_nm = _sc_fn` from `_ret_expr_sid`
(src/frontend/parse_fn.cyr), and the assignment's `_AGG_ASSIGN_TYPE_ERR(S, .., noff, _sc_fn)` (src/frontend/parse.cyr,
the `_sc_whole` arm near line 4314). Other `_sc_fn` readers to check with them: `_fsc_type_err(S, _sc_fn, fnoff)`
(parse_decl.cyr, a field destination), `_asa_refuse(.., _sc_fn, ..)`, `_rcv_ann_refuse(.., _sc_fn, ..)`,
`_refuse_toplevel_struct_call(S, _sc_fn)`.

## What a fix needs

The record's fn is kept since a4d4e8b58 (`_sc_fi`, and `_ess_fi` for `_expr_struct_sid`); each refusal above prints
`_fn_src_name(S, _sc_fi, _sc_fn)` — printed on its own, not as one of ERR_IDENT's two offsets, since the helper writes at
one scratch (`_sarg_ident_err`'s shape). Rows naming `Pt.dup` / `Pt.t1` at each destination; a local named `Pt_dup`
keeps its name.

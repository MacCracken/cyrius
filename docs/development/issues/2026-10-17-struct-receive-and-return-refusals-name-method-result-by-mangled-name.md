# The struct assignment's and the small-struct return's refusals name a method result by its mangled fn name (`'Pt_dup'`, `` `Pt_t1` ``) — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-17 on the 6.7.14 vectors lane (unit V4, after a4d4e8b58, which names a
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

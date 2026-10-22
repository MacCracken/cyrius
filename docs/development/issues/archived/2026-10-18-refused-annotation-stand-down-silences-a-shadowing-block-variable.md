# The refused-annotation stand-down matches by (fn, name): a same-named untyped variable in a nested block has its genuine "no struct type in scope" error silenced — RESOLVED

> ✅ **RESOLVED in v6.7.16** (FE-4, `63f383897` — no decision needed (diagnostics only; refused before and after). `_ann_refd_mark` (src/frontend/parse_fn_def.cyr) records the refused declaration's slot, pending until its registration binds it (`_ann_refd_bind`, from `_sl_last_marks`, `_w16_local_init`, `_param_record` and `_gv_last_marks`), and `_ann_refd_said` stands down only on that slot (a record nothing bound matches by name, as before). The filed repro now prints both errors, "4:12 unknown type 'Foo' for variable 'x'" and the inner x's "5:35 no struct type in scope for 'x'" (it printed only the first), on x86_64, aarch64, cx, PE and Mach-O; the refused x's own uses stay silent; a shadowed refused parameter, a top-level block's global, a refused late struct's annotation and a refused struct's literal the same. Rows: `tests/gates/frontend/struct_result_type_refused.sh` SH1 (the repro verbatim) – SH12; mutations: the tree before and `_ann_refd_bind` a no-op RED 10, `_param_record` not binding RED SH4, `_gv_last_marks` not binding RED SH5 / SH6; U13 – U28 green. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 receives lane (l6715-receives at b7932c673, unit R2), x86_64;
the frontend, every target.
**Placement:** 6.7.16 — Break 2, repair 6 (frontend lane, wave 1, unit F2; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Severity:** Low — the program is refused either way (rc 1) and its first error, the annotation's, is printed; a
second, genuine error on a DIFFERENT variable is counted but not printed.
**Kind:** bug (diagnostic).
**Discovered:** 2026-10-18 by unit R2 while fixing issues/archived/2026-10-17-refused-annotation-type-cascades-at-field-uses.md.
That fix marks a variable whose annotation was refused with the frontend lane's shared stand-down (`_ann_refd_mark` /
`_ann_refd_said`, src/frontend/parse_fn_def.cyr, from 6.7.15's late-declaration-refusal fix), which records
(the current fn — or top level — , the name) and stands down every `.field` / `.m()` / field-store report on that name
in that fn. The triage's plan for the receives issue suggested clearing the record on a successful redeclaration or
checking that the slot is still the refused one; the shared helper does neither, and a same-scope redeclaration is
refused anyway ("duplicate variable"), so only a nested block's shadow differs.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct Q { a; b; }
fn main(): i64 {
    var x: Foo = 5;
    if (1) { var x = 7; return x.a; }
    return 0;
}
syscall(60, main());
```

```
error:<source>:4:12: unknown type 'Foo' for variable 'x'
```

Before the receives fix (and on 4862a462e) the inner, untyped `x`'s `x.a` was reported too —
`error:<source>:5:35: no struct type in scope for 'x'; a '.field' access needs its struct declaration` — which is a
genuine error about a different variable. The same holds for the frontend lane's marks (a variable annotated with a
refused late declaration's struct, `var q = Q { 5 };` of a refused struct). A local named like a refused GLOBAL is not
affected (a local resolves to its own fn's scope: tests/gates/frontend/struct_result_type_refused.sh row U28).

## Root cause

`_ann_refd_said(S, noff, idx)` compares only the scope (`_cur_fn_ix`, or -2 for a global) and the name; the resolved
slot `idx` is used only to pick the scope. Recording the slot the refused declaration occupies (its local index, or
the global's) and comparing `idx` with it — or clearing the record when a declaration of the same name succeeds in the
fn — would leave a shadowing variable's own errors reported. Both lanes' callers (`_tn_refuse_var`, `_dl_refd_ann`,
`_slit_stray`'s mark) share the one helper, so the fix is in it.

# The explicit method spelling `x.m<..>(..)` (6.7.14, D7 (a)) is not recognised by the lookaheads that key a method call as `x.m(`: `var a, b = p.mm<i64>(3);` is "multi-value destructure needs a call on the right-hand side" — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-16 by the 6.7.14 generics lane (unit G4) on its tree, after the explicit-
method-type-arguments bite (issues/archived/2026-10-11-method-call-explicit-type-arguments-misdiagnosed.md, the user's D7 (a)).
**Placement:** 6.7.15 — repair 5 (generics lane, wave 1, unit G5; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Discovered:** 2026-10-16, 6.7.14 generics G4. D7 (a) made `p.id<f64>(h)` call the f64 instance. The bite covered
the method arm, a chain's leaf (`_rlf_more` / `_fld_meth_inline`), the statement router (`_stmt_dot_chain_call`),
the untyped declaration's f64 (`_var_rhs_mchain`), the struct `return` (`_ret_expr_head`), and the stub / bound scan
(`_gs_mfwd`); measured working there: an expression, `var a = p.id<f64>(h);`, a receive / annotation / assignment /
argument / chain / return of an 8 / 16 / 24 B struct, a `*P` receiver, a `*P` field hop, a statement, a bounded
member, two type parameters, `p.pick<T>(t)` in a generic. The other lookaheads that recognise a method call by the
exact tokens `name . name (` (`_tok_method_open`, src/frontend/parse.cyr, and its callers) do not see the `<..>`.
**Severity:** Low — a loud refusal of a spelling that compiled nowhere before 6.7.14; the inferred spelling works.
**Affects:** the 6.7.14 lane tree; every target (frontend).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
struct P { k; }
impl P {
    fn id<V>(self, x: V): V { return x; }
    fn mm<V>(self, x: V): (V, i64) { return (x, 7); }
}
fn main(): i64 { var p: P = P { 1 }; var a, b = p.mm<i64>(3); return a + b; }
syscall(60, main());
```

```
actual:   error:<source>:7:49: multi-value destructure needs a call on the right-hand side
expected: exit 10, as the inferred `var a, b = p.mm(3);` gives (measured: 10)
```

## Root cause

`_dt_call_open` (src/frontend/parse_decl.cyr) finds the destructure's call by `_tok_method_open(S, ti)` (`x.m(`, its
`(` at `ti + 3`). The same token test, with `ti + 3` as the `(`, is the method arm of: `_pair_unwrap` / `_tok_ret_callee`
/ `_ret_is_variant` / `_pair_callee_at` (parse.cyr: a pair-returning method, `?`), `_dyn_src_mcall` and the dyn source
reader (parse_types.cyr), `_var_rhs_msid` (an 8 B struct method result's type: the explicit spelling is typed by
`_sc_small_whole` instead — measured right), `_vmc_fi` (a vector-returning method), `_tup_arg_mv_err` /
`_tup_cap_err` / `_dt_struct_err` / `_mv_span` / `_ret_mv_small` (the multi-value refusals' wording). Only the
destructure was measured failing; the others are unmeasured.

## Fix direction

One helper — the `(` of a method call at `ti`, `x.m(` or `x.m<..>(` (the bite's `_mchain_targs`) — used by
`_tok_method_open`'s callers in place of `ti + 3`, and the callee resolved at the explicit instance (the bite's
`_meth_xinst`) where they resolve one (`_pair_callee_at` -> `_mcall_gen`). Rows: the repro (10); a pair-returning
method with `?`; a vector-returning method; each refusal's wording on the explicit spelling.

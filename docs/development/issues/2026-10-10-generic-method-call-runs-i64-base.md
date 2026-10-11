# A generic METHOD called as `p.m(x)` with a struct for its type parameter runs the i64 base (the dead stub) — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-10 against 6.7.8 @ 484763ed with the tree's `build/cycc` and its cross
compilers: the repro exits 7 on x86_64, aarch64 (qemu), cx (cxvm) and PE (wine), where 77 is right. The direct call
`P_pick(p, q)` of the same method is right on every target.
**Placement:** 6.7.11 — Break 2, repair 1, the generics / call-path lane (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-11 — never 7.x. (High: a silent wrong value)
**Discovered:** 2026-10-10 by the 6.7.8 checked-`dyn` lane's bite D2 (writing an acceptance row for a generic trait
member, `p.bnd(p)` with `fn bnd<V: Show>(self, v: V)`, which returned 0).
**Severity:** Medium — a silent wrong value on valid source, no diagnostic.
**Affects:** cycc 6.7.0 – 6.7.8 (measured with the installed 6.7.0, 6.7.3 and 6.7.7 compilers; an inherent `impl P {`
needs 6.7.0).

## Summary

A generic method (`impl P { fn pick<V>(self, w: V): i64 { .. } }`, or the same in `impl Tr for P`) called through the
method syntax, `p.pick(q)`, with a STRUCT argument for its type parameter, calls the generic's i64 BASE — and a base
whose body cannot be an i64 instance (`w.b` on an i64) is the dead stub, which returns 0. The free-call spelling of
the same method, `P_pick(p, q)`, infers `V = Q` and calls the `Q` instance. A scalar argument (`p.k(9)` with
`fn k<V>(self, v: V)`) happens to be right, because the i64 base is that instance — but a scalar into a generic that
HAS no scalar instance is silent too: `p.pick(9)` returns 0, where `P_pick(p, 9)` is refused by name ("generic
'P_pick' has no i64 (or other scalar) instance: it uses its type parameter as a struct ...").

## Reproduction

`docs/development/issues/repros/2026-10-10-generic-method-call-runs-i64-base.cyr`:

```cyrius
include "lib/syscalls.cyr"
struct P { v; }
struct Q { a; b; c; }
impl P { fn pick<V>(self, w: V): i64 { return w.b; } }
fn main(): i64 {
    var p = P { 5 };
    var q = Q { 1, 7, 3 };
    var a: i64 = p.pick(q);
    var b: i64 = P_pick(p, q);
    return a * 10 + b;
}
var rc = main();
syscall(60, rc);
```

```
actual:   exit 7  (a = 0: `p.pick(q)` ran the base's dead stub; b = 7)
expected: exit 77 (both spellings call pick$Q)
```

Run it from the repo root: `cat <repro> | build/cycc > /tmp/r && chmod +x /tmp/r && /tmp/r; echo $?`.

## Root cause

The method arm of `_field_load_on` (`src/frontend/parse_decl.cyr`, the `BUILD_METHOD_NAME` → `FINDFN` → `_sc_pre_m` →
`_owncall_args_at` → `ECALLFIX` sequence) calls the method's fn-table entry as found. It never asks whether the
callee is generic (`GFTP`), so no type argument is inferred from the call's arguments and no instance is minted —
PARSE_FNCALL's `_gen_call_head` / `_gen_resolve_call` path (which the free spelling `P_pick(p, q)` takes) has no
counterpart there.

## Proposed fix

In the method arm, when the callee is generic, infer its type arguments from the arguments as PARSE_FNCALL does (the
receiver is parameter 0, so a type parameter on `self` is the receiver's type) and call the instance; a shape that
cannot be inferred is refused by name, as on a free call (so `p.pick(9)` above becomes the free call's refusal: a
program that compiles today stops compiling — that half is the user's call). The lane that takes it must respect `_field_load_on`'s
cybs reference ceiling (it is a giant fn: one extracted helper call, not inline code). Rows: the repro on the four
targets; a bounded `<V: Show>` member (`v.show()` through the instance); a 24-byte struct argument; a method of
`impl Tr for P`; a chain `mk().pick(q)`; a scalar argument unchanged.

## Consumer-side workaround

Call a generic method by its fn name, `P_pick(p, q)` (or `P_Trait_pick(p, q)`), when a type argument is a struct.

## An f64 `V` is taken (appended 2026-10-11, 6.7.9 critical lane bite 9)

[The generic-call issue](2026-10-10-generic-call-f64-result-untyped.md)'s fix gave the method arm its inference hook:
`_mcall_gen` (parse_fn.cyr), called once in `_field_load_on` right after the callee is resolved (and from
`_var_rhs_msid` for a `var w = p.m(..);` binding), infers each type parameter from the method's arguments (parameter
k is position k - 1, `_call_arg_pk`) and calls the instance — but ONLY when one binds `f64` (`p.id(h)` calls
`P_id$f64`). A struct binding, this issue, still returns the base: extending `_mcall_gen`'s `c0 > 0 || c1 > 0` line to
instantiate (and the refusal half above) is this issue's fix; the repro above still exits 7.

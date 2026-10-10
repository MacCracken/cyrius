# A method call's result keeps its last argument's f64 type — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-09 against 6.7.6 @ e44470b7 with the tree's `build/cycc`. With
`fn m(self, d: f64): i64` returning 21, `p.m(1.5) * 2` warns "f64 arithmetic with a non-f64 right operand" and
evaluates to 0. The free-fn spelling `m2(&p, 1.5) * 2` is 42. Re-verified 2026-10-10 against 6.7.8 @ 484763ed: the
repro still exits 1 on x86_64, aarch64 (qemu), cx and PE (wine). ⚠ The Proposed fix's premise is wrong — see
*An f64-returning method is never typed f64* below (appended by the 6.7.8 dyn lane's D0).
**Placement:** 6.7.10 — Break 2, repair 1, the call-arguments lane (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-09 — never 7.x.
**Discovered:** 2026-10-09 during the 6.7.7 B6 (default and named arguments) planning (repro `method_f64_arg_leak.cyr`).
**Severity:** Medium — a silent wrong value on an integer method result. The spurious warning is the only sign.
**Affects:** cycc 6.7.0 – 6.7.6. Measured on 6.7.0, 6.7.3 and 6.7.6; earlier compilers reject the repro's inherent
`impl P {`, which needs 6.7.0. The free-fn path has had the reset since v6.4.56 (D3).

## Summary

Parsing a call's arguments leaves the expression type (ESTYPE) at the type of the last argument parsed. PARSE_FNCALL
resets it after the call, because a call's result is i64 unless its return type says otherwise. The method-call arm
in `_field_load_on` has no such reset. After `p.m(1.5)` the result is therefore still typed f64, and an outer operator
takes the f64 arm: `p.m(1.5) * 2` multiplies the bit patterns of 21 and 2 as doubles. Both are subnormals, so the
product is 0.0, whose bits are 0.

## Reproduction

`docs/development/issues/repros/2026-10-09-method-call-result-keeps-last-arg-f64-type.cyr`:

```cyrius
struct P { x; }
impl P { fn m(self, d: f64): i64 { return 21; } }
fn m2(p, d: f64): i64 { return 21; }
fn main(): i64 {
    var p = P { 1 };
    var r = p.m(1.5) * 2;
    var r2 = m2(&p, 1.5) * 2;
    var e = 0;
    if (r != 42) { e = e | 1; }
    if (r2 != 42) { e = e | 2; }
    return e;
}
var r = main();
syscall(60, r);
```

```
actual:   warning:<source>:11:25: f64 arithmetic with a non-f64 right operand ; exit 1 (r = 0)
expected: no warning ; exit 0 (r = r2 = 42)
```

Run it from the repo root: `cat <repro> | build/cycc > /tmp/r && chmod +x /tmp/r && /tmp/r; echo $?`.

## Root cause

- `src/frontend/parse_fn.cyr:4589-4593`: PARSE_FNCALL ends with `SESTYPE(S, 0);` under the comment "v6.4.56 D3 — a
  call result's type is i64, not its LAST argument's expr-type (which the arg parse leaked)".
- `src/frontend/parse_decl.cyr:1645-1661`: the method arm of `_field_load_on` (`_CHECK_ARITY`, ECALLPOPS, the call,
  ECALLCLEAN, `_sc_post`, `_call_ret_ps`, `_method_chain`) has no matching reset.

## Proposed fix

Add `SESTYPE(S, 0);` after `ECALLCLEAN(S, m_int_argc);` in the method arm. The f64-returning method's re-tag must
still apply afterwards, as the D1 seam does for a free fn. Check the other call arms that marshal arguments themselves
for the same missing reset (`_struct_call_emit`, the PE vector receives). Add a gate row for `p.m(1.5) * 2` and for an
f64-returning method.

This changes codegen for existing programs whose method calls end in an f64 argument. The changed programs are the
ones that compute a wrong value today.

## Consumer-side workaround

Bind the result first (`var t = p.m(1.5); var r = t * 2;`), or call the method by its mangled name (`P_m(&p, 1.5)`),
which takes PARSE_FNCALL's path.

## An f64-returning method is never typed f64 (appended 2026-10-10, 6.7.8 dyn lane D0)

The Proposed fix above says "the f64-returning method's re-tag must still apply afterwards, as the D1 seam does for a
free fn". **There is no such re-tag on the method path.** The free call ends with `_call_ret_marks(S, fi)`
(`src/frontend/parse_expr.cyr:2468`; called at `:2825`): an f64 return (GFRS −9) is brought from xmm0 into rax
(`EMOVQ_A_X0`) and typed `F64_TYID`, then `_call_ret_ps`. The method arm of `_field_load_on` calls only
`_call_ret_ps(S, mfi)` (`src/frontend/parse_decl.cyr:1708`, after `ECALLCLEAN` `:1706` and `_sc_post` `:1707`), so a
method declared `: f64` gives an UNTYPED word — the reverse of the leak this file reports.

`docs/development/issues/repros/2026-10-09-method-call-result-keeps-last-arg-f64-type-f64-return.cyr`:

```cyrius
struct P { v; }
impl P { fn area(self): f64 { return 2.5; } }
fn main(): i64 {
    var p = P { 1 };
    var a: f64 = p.area() + 1.0;
    if (a == 3.5) { return 42; }
    return 1;
}
var rr = main();
syscall(60, rr);
```

```
actual:   warning:<source>:5:32: integer arithmetic with an f64 right operand ; exit 1 (x86_64, aarch64-qemu, cx, PE-wine)
expected: no warning ; exit 42
```

So the fix here is the free call's pair, in the free call's order: `SESTYPE(S, 0)` (the half this file reports —
PARSE_FNCALL's reset, `src/frontend/parse_fn.cyr:6075`) and then `_call_ret_marks(S, mfi)` in place of
`_call_ret_ps(S, mfi)` (it calls `_call_ret_ps` itself; PARSE_FACTOR calls it right after PARSE_FNCALL returns,
`parse_expr.cyr:2825`). `SESTYPE(S, 0)` alone would leave the f64 return untyped, and `_call_ret_marks` alone resets
nothing for a non-f64 return. Checked in a scratch tree on 2026-10-10 (x86, not committed): with those two lines in
place of `_call_ret_ps(S, mfi);`, this file's repro exits 0 and the f64-return repro exits 42, with no warning. A gate
row for `p.area() + 1.0` joins the two rows named above.
Both halves change what a compiling program computes; the placement stays 6.7.10. The 6.7.8 `dyn` call types its own
result (`_call_ret_marks` on the trait member's prototype), so it does not wait on this fix.

## A STRUCT last argument leaks too (appended 2026-10-10, 6.7.8 dyn lane D2)

The same missing reset with a struct as the last argument is a loud failure on valid source, not a wrong value: the
leaked expression type is the struct, so an outer operator dispatches the struct's operator fn.

```cyrius
include "lib/syscalls.cyr"
struct P { v; }
impl P { fn m(self, q): i64 { return 2; } }
fn main(): i64 { var p = P { 5 }; return p.m(p) * 10; }
syscall(60, main());
```

```
actual (6.7.8 @ 484763ed, x86_64): warning: undefined function 'P_mul' ... error: refusing to emit binary with 1
        reachable undefined function(s)
expected: exit 20 (the free spelling `fn m(a, q: P): i64` called as `m(1, p) * 10` builds and runs)
```

The fix above (`SESTYPE(S, 0)` before `_call_ret_marks`) covers it; add it as a third gate row.

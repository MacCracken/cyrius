# A method call's result keeps its last argument's f64 type — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-09 against 6.7.6 @ e44470b7 with the tree's `build/cycc`. With
`fn m(self, d: f64): i64` returning 21, `p.m(1.5) * 2` warns "f64 arithmetic with a non-f64 right operand" and
evaluates to 0. The free-fn spelling `m2(&p, 1.5) * 2` is 42.
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

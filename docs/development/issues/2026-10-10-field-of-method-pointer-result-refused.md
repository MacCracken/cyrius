# `.field` on a METHOD's `*T` result (`h.get().b`) is refused, where a free fn's `get2(h).b` reads it — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-10 against the merged 6.7.8 tip (l678-int @ 85ee576f) with its
`build/cycc`: `h.get().b` with `fn get(self): *P` is refused "cannot take a field of the result of 'H_get': it does not
return a struct"; `get2(&h).b` with `fn get2(h: *H): *P` builds, as do `var q: *P = h.get(); q.b` and
`H_get(h).b` (exit 44). The same refusal with the installed 6.7.0, 6.7.3, 6.7.5, 6.7.6 and 6.7.7 compilers.
**Placement:** 6.7.10 — repair 1 (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-10 — never 7.x (the fix
is the user's call, asked at that release's open: refused source starts compiling).
**Discovered:** 2026-10-10 by the 6.7.8 checked-`dyn` lane, bite D6 (a dyn method call inherits the method arm's rule:
`o.me().b` through a dyn is refused the same way).
**Severity:** Low — loud: valid source is refused (with a reason that is wrong: the method returns `*P`); no wrong
value.
**Affects:** cycc 6.7.0 – 6.7.8 (every target; the method arm is shared frontend code)

## Summary

Since 6.6.17 a free call's `*T` result takes a field directly — `get2(&h).b` parks the pointer and reads the field
through it (`_call_ptr_field`). The METHOD arm never got that case: after a method call, a `.field` is read only on
a STRUCT result (in its temp); any other result is refused with "it does not return a struct". The method's declared
`*P` return is known (the same table the free arm reads), so the refusal is a missing arm, and its text is wrong.
The direct spelling of the same method (`H_get(h).b`) is a free call and works.

Related, not the same defect: [`gp().n = 5` refused](2026-10-08-field-store-through-pointer-returning-call-refused.md)
— the STORE through a free call's `*T` result (6.7.12).

## Reproduction

`docs/development/issues/repros/2026-10-10-field-of-method-pointer-result-refused.cyr`:

```cyrius
include "lib/syscalls.cyr"
struct P { a; b; }
struct H { p: *P; }
impl H { fn get(self): *P { return self.p; } }
fn get2(h: *H): *P { return h.p; }
fn main(): i64 {
    var p = P { 3, 4 };
    var h = H { &p };
    var x = get2(&h).b;                  # accepted: 4
    var y = h.get().b;                   # refused: "cannot take a field of the result of 'H_get': it does not return a struct"
    return x * 10 + y;                   # want 44
}
var rc = main();
syscall(60, rc);
```

```
actual:   error:<source>:10:20: cannot take a field of the result of 'H_get': it does not return a struct
expected: builds; exit 44
```

## Root cause

`_method_chain` (`src/frontend/parse_decl.cyr:1526`) takes `sid = GFRS(S, fi)` — the method's STRUCT return — and
when it is 0 calls `_call_fld_err` (`src/frontend/parse_expr.cyr:2444`). It never consults the pointer-return table
(`_fn_rpsid`) that the free-call arm `_call_ptr_field` (`src/frontend/parse_decl.cyr:1648`) reads to park a `*T`
result (`_ptr_park`) and load the field through it (`_field_load_on`).

## Proposed fix

In `_method_chain`, when the method has no struct return but a `*T` one (`_fn_rpsid[fi] > 0`), park rax as
`_call_ptr_field` does and continue the chain through `_field_load_on` on the pointee type — a field, a further
method, a subscript, at any depth. Keep the refusal for a result that is neither, and keep the top-level refusal only
where a frame is actually needed (a pointer needs none). Rows: the repro; a chain `h.get().q.b` and
`h.get().m()`; a field store `h.get().b = 5` (decide with the free-call store issue above); the dyn spelling
`o.me().b`; a generic method returning `*T`.

## Consumer-side workaround

Bind the pointer first (`var q: *P = h.get(); q.b`) or call the method by its fn name (`H_get(h).b`).

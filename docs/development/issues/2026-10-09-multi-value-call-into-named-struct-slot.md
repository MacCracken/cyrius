# A multi-value call where a named struct over 8 B is expected is taken as its address — four shapes compile clean — OPEN

**Status:** 🟡 **OPEN** — reproduced 2026-10-09 against the merged 6.7.7 tip (`int` @ 06bd8981, `build/cycc`
1,916,288 B) by building each repro with the tree's compiler (`cat repro | build/cycc`) and running it: the argument,
method-argument and declaration shapes compile with no diagnostic and exit 139 (SIGSEGV); the field store exits 30
where 34 is right. The same four results on x86_64 and on aarch64 (a cross compiler built from the merged tree, run
under qemu-aarch64), and on the 6.7.6 tag's `build/cycc`. The free-call argument also crashes on 6.6.0, 6.6.10 and
6.7.0. A tuple parameter / tuple field given the same call is refused by name (6.7.7's R17).
**Placement:** 6.7.10 — Break 2, repair 1 (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-09 — never 7.x.
The multi-value receives and call arguments lanes own these sites. Refusing the four shapes changes what compiles, so
the fix's shape is a one-line ask at 6.7.10's open: refuse by name (default) or build the struct from the values.
**Discovered:** 2026-10-09 by the 6.7.7 B4 (tuples) lane, bite T3 (out of scope for tuples: R17 covers only a tuple
parameter).
**Severity:** High — a silent miscompile: a clean build that crashes or stores a wrong field, with no diagnostic.
**Affects:** cycc ≤ 6.7.6 and the merged 6.7.7 (measured 6.6.0, 6.6.10, 6.7.0, 6.7.6 tag, 6.7.7 tip); the method form
from 6.7.0 (inherent `impl`).

## Summary

A call that returns several values (`fn mk(a): (i64, i64)`, or an undeclared `return (a, b);`) leaves them in the
return registers. A named struct over 8 B is handled by ADDRESS: a by-value parameter receives the struct's
address, and a struct local or field is copied from one. When such a destination gets a multi-value call, nothing
recognises the call, so its FIRST value is used as the struct's address (or as one word):

1. **By-value struct parameter, free call** — `take(mk(3))` with `fn take(t: P)`: rc 139.
2. **The method form** — `take(b.mk(3))` with `impl B { fn mk(self, a): (i64, i64) }`: rc 139.
3. **A struct-typed declaration** — `var p: P = mk(3); return p.a;`: rc 139 (by code reading, the local takes 3 as
   its address, the pointer-mode handle form).
4. **A struct-typed field** — `h.p = mk(3);` with `struct H { p: P; }`: exits 30 (`p.a` = 3, `p.b` = 0); 34 is what
   the source means.

The assignment `var p: P; p = mk(3);` is in the same family. It warns "assigning non-pointer to typed pointer" and
then exits 30, so it is not silent.

The tuple destinations refuse the same call by name (6.7.7, B4 R17): `take(mk(3))` into `fn take(t: (i64, i64))` gives
``a multi-value call 'mk' is not a tuple argument - bind it first: `var t: (i64, i64) = mk(..);`, then pass `t` ``,
and `h.p = mk(3);` into a tuple field gives the field form. The guide's *Refused by name* table refuses the reverse
direction too, ``var t: (i64, i64) = mk();`` when `mk` returns `P` ("a struct return is not multiple values").

## Reproduction

`docs/development/issues/repros/2026-10-09-multi-value-call-into-named-struct-{1-argument,2-method-argument,3-declaration,4-field-store}.cyr`:

```cyrius
struct P { a; b; }
fn mk(a): (i64, i64) { return (a, a + 1); }
fn take(t: P): i64 { return t.a * 10 + t.b; }
fn f(): i64 { return take(mk(3)); }
syscall(60, f());
```

```sh
for n in 1-argument 2-method-argument 3-declaration 4-field-store; do
  cat docs/development/issues/repros/2026-10-09-multi-value-call-into-named-struct-$n.cyr | build/cycc > /tmp/mv && chmod +x /tmp/mv
  /tmp/mv; echo "$n rc=$?"
done
```

| Shape | Expected | x86_64 (6.7.7 tip, 6.7.6 tag) | aarch64 (qemu, 6.7.7 tip) |
|---|---|---|---|
| 1 `take(mk(3))` | refusal (or 34) | rc 139 | rc 139 |
| 2 `take(b.mk(3))` | refusal (or 34) | rc 139 | rc 139 |
| 3 `var p: P = mk(3);` | refusal (or 3) | rc 139 | rc 139 |
| 4 `h.p = mk(3);` | refusal (or 34) | 30 | 30 |

The undeclared callee `fn mk(a) { return (a, a + 1); }` in shape 1 also gives rc 139. Control: a callee declared
`: P` (`fn mk(a): P { var p = P { a, a + 1 }; return p; }`) gives 34 in shape 1.

## Root cause

Every named-struct destination identifies a struct-valued source by the callee's return struct id being positive. A
declared multi-value return records `MULTIRET_SID` (`0 - 40`, `src/frontend/parse_types.cyr:1053`), and an undeclared
`return (a, b)` records nothing. So none of these destinations sees the call. Only the tuple destinations test for
`MULTIRET_SID`, and each of those exits when its destination is not a tuple. Line numbers are from the merged tree:

- **Argument, free call**: `_try_push_struct_addr_arg` (`src/frontend/parse_fn.cyr:1540`).
  - The type check `_sarg_call_sid` → `_sarg_call_rs` (`:1479`–`:1496`) returns 0 when `rs <= 0`.
  - `_tup_arg_call` (`:1624`) exits at `_tup_is(S, ps) == 0` (`:1626`).
  - `_arg_call_class` (`:4441`) → `_ret_agg_class` (`:4233`, `sid <= 0` → 0) makes `:1569` return 0.
  - The caller (`_call_arg_one`, `:4168`) then pushes the call's value (`rax`, the first value) as the address.
- **Argument, method**: `_push_struct_expr_arg` (`:4755`). `_tup_arg_mrc` (`:1649`) exits at `:1653` (not a tuple).
  `_sc_post_small` records only a tuple-bound span for a `MULTIRET_SID` result (`_mrc_note`, `:4533`), so `_sc_whole`
  finds no struct, and the value is pushed.
- **Declaration**: `_scv_call_check` (`parse_fn.cyr:4625`) and `_gen_decl_check` (`src/frontend/parse_decl.cyr:5328`)
  both exit at `rs <= 0`. The value becomes the local's pointer (the pointer-mode handle form).
- **Field store**: `_fsc_src` (`parse_decl.cyr:976`). `_tup_fsc_call` exits at `:996` (not a tuple field).
  `_fsc_call` exits at `:913` (`rs <= 0`). `_fsc_expr` then stores from `rax`.
- **Assignment** (warned): `_try_struct_call_assign` (`src/frontend/parse.cyr:2845`) exits at `cls == 0`.

## Proposed fix

Default (one-line ask at 6.7.10's open, because each shape compiles today): refuse a multi-value call as a
named-struct source by name, at the four sites, with R17's wording:

```
a multi-value call 'mk' is not a struct 'P' argument - bind it first: `var a, b = mk(..);`
```

The field, declaration and assignment forms get the same message, with a field / declaration wording (`_tamv_fld`
already switches R17's text). One predicate, "the whole source is a call whose callee returns several values", serves
all four. It is `GFRS(S, fi) == MULTIRET_SID`, plus the undeclared `return (a, b)` callee. That callee needs pass 1
to record its arity, which is fix 1 of
[`2026-10-09-multi-value-receive-reads-stale-return-registers.md`](2026-10-09-multi-value-receive-reads-stale-return-registers.md)
(same release, same lane), so the two land together and the gate covers both forms.

The alternative is the user's call: build a temp of the struct from the values and pass its address, so a
`(i64, i64)` call fills a two-field `P`. That makes a tuple-shaped return convert to a named struct, which the guide
refuses in the other direction.

Gate: a row per shape (free, method, declaration, field, plus the warned assignment), each run on x86_64 and aarch64.
Add a mutation that drops the predicate.

## Consumer-side workaround

Bind the values first and build the struct: `var a, b = mk(3); var p = P { a, b }; take(p);`. Or declare the callee
`: P` and return a `P` local.

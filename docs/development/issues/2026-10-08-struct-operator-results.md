# Struct-operator results: six typing / return-shape defects around struct operands — OPEN

**Status:** 🟡 **OPEN** — all six reproduced 2026-10-08 against 6.7.6 @ 2fb6ad8b with `build/cycc` (repros below, each
run and its exit recorded); items 2–5 also reproduce on the installed 6.6.20, 6.7.0, 6.7.3 and 6.7.5 compilers; item 1
is new in 6.7.6 (6.7.5 refused the shape with `expected ';', got '-'`).
**Placement:** unpinned — 6.x-line backlog — never 7.x.
**Discovered:** 6.7.6 lane E2 (repros `~/.cache/c6/b1f_E2/p/`, `q/`); filed 2026-10-08 from roadmap.md.
**Severity:** Medium — silent wrong values and SIGSEGVs on code that compiles clean; each shape has a workaround
(annotate the variable, name the operand in a variable, return a local).
**Affects:** cycc 6.7.6 (item 1); cycc 6.6.20 – 6.7.6 at least (items 2–5, not bisected further); item 6 since
closures captured by value (v6.3.8), written into the guide as behaviour at 6.7.5.

## Summary

Six defects in how a struct operand, an operator result or a struct-returning fn's return value is typed. The 6.7.6
L/R arcs (a struct call / method / operator result as the LEFT operand dispatches; parentheses around a struct return)
left them behind:

1. **An untyped `var r = mk3(4) - s;` is typed `P3`** although `P3_sub` returns an integer: `r.x` compiles and
   dereferences -5 (SIGSEGV). `var r = a - s;` with a local `a` is typed correctly (`r.x` → "no struct type in scope for
   'r'"). Also `var r = mk2(1) == p; return r;` in a fn returning `Pt` SIGSEGVs: `r` is typed `Pt` and returned as a
   16-byte local from an 8-byte slot.
2. **After an INTEGER `+` / `-` / `*` whose right operand is a struct, the result keeps the struct's type** (and its
   slot): `n - s + 10` calls `P3_add(&s, 10)` — the `n - s` value is discarded and the callee dereferences 10
   (SIGSEGV). Live, not only `-`: `n + s + 10` and `n * s + 10` dispatch `P3_add` too.
3. **`-s + t` ignores the minus**: it calls `P3_add(&s, &t)`, exactly as `s + t` does.
4. **`return (a, b);` in a struct-returning fn takes the multi-value path**: for a 24-byte struct the caller's retptr
   buffer is never written (reads 0, 0, 0); for an 8-byte struct the second value is dropped silently (`q.v` = a).
   The 16-byte case happens to work (rax:rdx is that class's ABI).
5. **`return mk2(1) == p;` in a 9–16 B struct fn leaves the second register unwritten** — rax is the comparison, rdx
   is `mk2`'s stale second word. Any non-overloadable operator after a leading pair call does it: `==`, `<`, `&`, `<<`,
   `&&` (`%` leaves the idiv remainder in rdx). The >16 B class refuses the same shape.
6. **A write to a captured NAME inside a closure says "undefined variable 'x'"**, though `x` is defined, captured
   and readable in the same body (`|d| { return x + d; }` builds and returns 7). The guide records the message as the
   behaviour ("A captured NAME is not an lvalue in the closure: `x += d`, like `x = x + d`, is `undefined variable
   'x'`", guide § Compound assignment); the message names the wrong refusal.

## Reproduction

One file per item in `docs/development/issues/repros/`, each with expected / actual in its header; run from the repo
root (item 6 includes `lib/`):

```sh
for f in docs/development/issues/repros/2026-10-08-struct-operator-results-*.cyr; do
  cat "$f" | build/cycc > /tmp/r 2>/tmp/r.err && chmod +x /tmp/r && /tmp/r; echo "$(basename "$f"): $?"; done
```

| # | repro | expected | actual (6.7.6 @ 2fb6ad8b) |
|---|-------|----------|---------------------------|
| 1 | `…-1-untyped-var-typed-from-leading-call.cyr` | `no struct type in scope for 'r'` | builds; exit 139 |
| 2 | `…-2-integer-op-keeps-right-struct-type.cyr` | integer `+ 10`, no `P3_add` call | exit 139 (SIGSEGV in `P3_add`) |
| 3 | `…-3-unary-minus-on-struct-dropped.cyr` | not `s + t` | exit 6 (= `s.x + t.x`) |
| 4 | `…-4-tuple-return-in-struct-fn.cyr` | refused, as `return (5);` is | builds; exit 0 (q = 0, 0, 0) |
| 5 | `…-5-pair-return-leading-call-operator.cyr` | refused, as `return mk2(1).x;` is | builds; exit 41 (q.y = mk2's y) |
| 6 | `…-6-captured-name-write-undefined.cyr` | a diagnostic naming the real refusal | `error:<source>:11:25: undefined variable 'x'` |

Item 2 with a non-dereferencing operator (`fn P3_add(a, b): i64 { if (b == 10) { return 1; } return 50; }`) returns
1 for each of `n - s + 10`, `n + s + 10`, `n * s + 10`: the `+ 10` is the call. With `fn P3_add(a, b): i64 { return
load64(a) * 10 + b; }`, `n - s + 2` (n = 3, s.x = 5) returns 52: the left operand is `&s`, not `n - s`.

## Root cause

1. `_var_rhs_call` (`src/frontend/parse_decl.cyr:5026`) answers 1 for any initializer that STARTS with `name(` and is
   not followed by `.field` (`_call_dotted`); PARSE_VAR's inference (`parse_decl.cyr:5920`–`5924`) then takes the
   callee's `GFRS` as the variable's struct. `mk3(4) - s` and `mk2(1) == p` start with the call. 6.7.6 added
   `_call_ends_at` (`src/frontend/parse_fn.cyr:2852`) for exactly this distinction in the receives; the inference never
   asks it.
2. The integer arms of `_PEXPR_IMPL` (`src/frontend/parse_expr.cyr:6030`–`6033`, `6058`–`6061`) and PARSE_TERM's `*`
   arm (`parse_expr.cyr:5388`–`5416`) parse the right operand (`_RHS_T` / `_RHS_F`) and never clear the estype it set,
   so the next operator's `_op_lst(S, _xbeg)` (`parse_expr.cyr:5715`) reads the RIGHT operand's struct as the whole
   left operand's type and dispatches; `_op_lhs_sv` (`parse_expr.cyr:5699`) then addresses the left operand from the
   `GESVAR` slot the right operand left (s), not from rax.
3. Unary minus (`parse_expr.cyr:2488`, `_neg_int` at `:1299`) negates rax but leaves the operand's estype and
   `GESVAR` (s's slot); `EMIT_OP_DISPATCH` → `_op_lhs_sv` (`parse_expr.cyr:5699`) re-addresses the operand from that
   slot for a struct over 8 B, so the negated value is discarded. (Read from the code; the 8 B and 16 B operand paths
   were not traced.)
4. PARSE_RETURN's multi-return arm (`src/frontend/parse_fn.cyr:1009`–`1060`) runs before the struct-return classes
   and refuses only a vector return (`_refuse_vector_tuple_return`, `parse_fn.cyr:3574`); a struct-returning fn's
   tuple goes out in rax:rdx whatever its class.
5. `_pair_ret_call_ok` (`parse_fn.cyr:3488`) accepts a call to a same-struct pair fn at the cursor without checking
   that the call ENDS the return value; `_ret_struct_pair` (`parse_fn.cyr:1923`) then hands the whole expression to
   the scalar path. `+ - * /` are caught first by `_ret_expr_head`; every other operator is not.
6. The plain-assignment arm of `_PARSE_STMT_IMPL` (`src/frontend/parse.cyr:4378`–`4398`) tries FINDLOCAL then
   FINDVAR and reports "undefined variable" with no capture lookup (`_cl_snap_find` / `_cl_cap_find`, which the read
   path at `parse_expr.cyr:2778`–`2795` uses). `x += d` reports the same message (its code site not traced).

## Proposed fix

1. In the var-decl inference, require `_call_ends_at(S, ti, 5)`; an operator expression's result type is the operator
   fn's `GFRS` (the `_sc_*` record the operator receive already keeps), else untyped.
2. Clear the estype (`SESTYPE(S, 0)`) after each integer arm's right operand — the result of an integer op is an
   integer. Whether `integer OP struct` should be refused outright is a language question (the user's).
3. `-s` on a struct: either dispatch a unary operator fn, refuse it, or make it an integer negation that clears the
   struct type. All three change what `-s + t` does today — **the user's decision**.
4. Refuse a tuple return in a struct-returning fn of the retptr (> 16 B) and ≤ 8 B classes with the existing
   struct-return diagnostic; whether the working 16-byte `return (a, b);` stays legal is **the user's decision**.
   Either refusal makes code that compiles today stop compiling.
5. `_pair_ret_call_ok`: add `_call_ends_at(S, GTI(S), _ret_term)`, so the shape reaches `_refuse_pair_return`.
   **Refuses code that compiles today — the user's call** (roadmap.md said so).
6. Look the name up as a capture before the "undefined variable" report and say what is refused (e.g. "'x' is captured
   by value; a captured name is not assignable in a closure — copy it into a local"), and update the guide's sentence.
   Making a captured name assignable (writing the closure's own copy, as `h.n += d` already does) is a language change
   — **the user's decision**.

Each fix lands with a `tests/gates/codegen/struct_value_codegen.sh` row (the L / R families) and, where it runs, a
`tests/tcyr/crossos/struct_value_codegen.tcyr` row.

## To re-check with this bite

The CHANGELOG [6.6.20] pre-existing list also names `(s - t) - t` and `a - bump(b)` as operator-result left / right
operand shapes, and `h.s.dup()` as a parse error. Their status at 6.7.6 was not checked when this was filed.

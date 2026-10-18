# A third type parameter is accepted at the declaration and silently unrecorded; every explicit three-argument use is a parse error — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-18 by the review of the 6.7.15 generics lane (the nested-shift fix,
issues/2026-10-16-nested-type-arg-shift-close-then-comma-drops-next-arg.md, turned
`sizeof(Three<P<P<R>>, i16, i32>)` from a silent wrong 28 into the parse error every three-argument use already
gave). Pre-existing: the lane tree and the slot-open compiler b2e1f4c48 give identical results below.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 generics review, wave 1; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
**Severity:** Low (the review's grading) — but the inferred form computes a wrong value in silence: `sizeof(C)` is 8 for
a 24-byte struct argument, so integration may raise it.
**Kind:** bug / language (the guide says "At most two type parameters are recorded", but nothing refuses a third by
name; whether a third is refused or supported is the user's call).

## Reproduction

The third parameter is accepted and binds nothing (i64):

```cyrius
struct S { a; b; c; }
fn g3<A, B, C>(a: A, b: B, c: C): i64 { return sizeof(C); }
fn g2<A, B>(a: A, b: B): i64 { return sizeof(B); }
fn main(): i64 { var s = S { 1, 2, 3 }; return g3(1, 2, s) + 100 * g2(1, s) / 24; }
```

```
$ build/cycc < g3.cyr > b && ./b; echo $?
108
```

(`g2(1, s)` binds B = S: 24, so 100; `g3(1, 2, s)` reads `sizeof(C)` as 8, where 24 was written: 124 expected.)

Every explicit three-argument spelling is a parse error rather than a refusal by name:

```cyrius
struct Three<A, B, C> { a: A; b: B; c: C; }
fn main(): i64 { var t: Three<i8, i16, i32>; return 0; }
```

```
error:<source>:2:38: expected '=', got ','
error:<source>:2:43: undefined variable 'i32' (missing include or enum?)
```

```cyrius
struct Three<A, B, C> { a: A; b: B; c: C; }
fn main(): i64 { return sizeof(Three<i8, i16, i32>); }
```

```
error:<source>:2:45: expected ')', got ','
```

```cyrius
fn g3<A, B, C>(a: A, b: B, c: C): i64 { return sizeof(C); }
fn main(): i64 { return g3<i32, i16, i8>(1, 2, 3); }
```

```
error:<source>:2:40: undefined variable 'i8' (missing include or enum?)
error:<source>:2:41: a tuple `( .. )` is a value only as a `var` initializer, assigned to a tuple variable or field, as a tuple argument, or after `return` - here one value is expected
error:<source>:2:50: expected ')', got ';'
```

And the bare `var t: Three;` compiles (`sizeof(Three)` 24, all i64).

## Root cause

The generic fn / struct header readers capture two type-parameter names (`_tp_c0` / `_tp_c1`, `GSTP`'s two slots) and
skip the rest of the `<..>` list; every type-argument reader (`_gen_ann_sid`, `_parse_one_type_arg`,
`_gen_resolve_call`, `_ret_targ_parse`, ...) reads at most two arguments (`_ta_comma` once) and leaves a third `,` to
the enclosing expression.

## Fix direction

The user decides: refuse a third type parameter at the declaration by name ("a generic takes at most two type
parameters"), or record N. Either way the inferred call must not bind a parameter to i64 in silence.

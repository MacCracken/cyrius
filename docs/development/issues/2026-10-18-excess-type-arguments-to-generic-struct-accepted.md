# Excess type arguments to a generic struct are accepted silently — `var b: Box<i64, i64>;` with `struct Box<T>` compiles — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-18 by the review of the 6.7.15 structs lane (in passing), re-measured by its fix
step on the lane head 342244fa8 and the lane base 8b4d44602 alike (x86_64): rc 0, no diagnostic.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 structs review, wave 2; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
**Severity:** Low — accepted bad syntax: the extra argument is dropped and the one-parameter instance is used, so
nothing computes wrongly at the written name, but a typo'd or stale argument list is never reported.
**Kind:** bug / language — the guide states no rule on type-argument count. Its neighbours are
issues/2026-10-18-third-type-parameter-accepted-and-unrecorded.md (a THIRD type PARAMETER at a declaration) and
issues/2026-10-18-non-generic-type-arguments-unrefused-in-remaining-positions.md (`<..>` on a NON-generic name, 6.7.15's
D6); neither covers more arguments than a generic struct declares parameters.

## Reproduction

A local:

```cyrius
struct Box<T> { v: T; n; }
fn main(): i64 { var b: Box<i64, i64>; b.n = 3; return b.n; }
syscall(60, main());
```

```
$ build/cycc < ta.cyr > ta && ./ta; echo $?
3           # compiles, no diagnostic
```

A parameter:

```cyrius
struct R2 { a; b; }
struct Box<T> { v: T; n; }
fn g(x: R2, y: Box<i64, i64>): i64 { return x.a + y.n; }
fn main(): i64 { var r: R2; r.a = 1; r.b = 2; var b: Box<i64>; b.n = 3; return g(r, b); }
syscall(60, main());
```

```
$ build/cycc < ta2.cyr > ta2 && ./ta2; echo $?
4
```

`sizeof(Box<i64, i64>)` is 16 (rc 0) — `Box<i64>`'s size.

## Root cause (by the shapes; the readers not instrumented)

The type-argument readers (`_gen_ann_sid`, `_parse_one_type_arg`, `_gtype_sid_def`, ...) read up to two arguments (the
`GSTP` two slots, `_ta_comma` once) whatever the struct declares, and bind the struct's parameters from the first ones;
nothing compares the count read with the struct's own parameter count, so a second argument to a one-parameter struct
is read and dropped.

## Fix direction

Refuse it once, at the extra argument, with words naming the struct and its count ("'Box' takes 1 type argument, 2
given"), in the same readers 6.7.15's D6 refusal (`_ngt_refuse`) sits in — the wording / reach is the user's call
alongside the third-type-parameter filing. Rows: the two repros (a local, a parameter), `sizeof(Box<i64, i64>)`, a
global, a return type, a `*Box<i64, i64>` pointer; controls `Box<i64>` and a two-parameter struct with two arguments.

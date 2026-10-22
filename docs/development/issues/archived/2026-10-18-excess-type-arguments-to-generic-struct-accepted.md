# Excess type arguments to a generic struct are accepted silently — `var b: Box<i64, i64>;` with `struct Box<T>` compiles — RESOLVED

> ✅ **RESOLVED in v6.7.16** (GS-7, `e65308eb2`, and GS-7r `ca1c163da` — the user's decision D5, 2026-10-19 at the 6.7.16 open: refuse once, at the first extra argument, for structs and generic fn calls alike. Every type-argument list reader reads the arguments its generic declares (`_ta_rest`) and refuses the first extra one (`_ta_extra`), stepping the rest. Both filed programs, verbatim, are refused with one line — ta.cyr `2:34: 'Box' takes 1 type argument, 2 given` (it exited 3), ta2.cyr at 3:25 (it exited 4) — on x86_64, aarch64, cx and PE; `sizeof(Box<i64, i64>)`, a global, a return and a `*Box<i64, i64>` local the same, and `g<i32, Pt>(5)` on `fn g<T>` is `'g' takes 1 type argument, 2 given` (it exited 4). Nothing cascades — in a trait signature since GS-7r, where the impl check and a formed dyn no longer add a line. Silent under `--syntax-only`. Rows: the new `generic_type_arg_count_refused.sh` (R1 / R2 the filed programs verbatim, P1 – P15, F1 – F6, B1, X, E1, the controls, A); `traits_checked.sh` TRR3 – TRR6; `dyn_checked.sh` F8p1, F8p3. Mutant: the lane's previous compiler → RED 26. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found 2026-10-18 by the review of the 6.7.15 structs lane (in passing), re-measured by its fix
step on the lane head 342244fa8 and the lane base 8b4d44602 alike (x86_64): rc 0, no diagnostic.
**Placement:** 6.7.16 — Break 2, repair 6 (gensig lane, wave 2, unit GS3; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Decision (user, 2026-10-19, at the 6.7.16 open):** D5 — Refuse once, at the first extra argument, for structs and generic fn calls alike.
**Severity:** Low — accepted bad syntax: the extra argument is dropped and the one-parameter instance is used, so
nothing computes wrongly at the written name, but a typo'd or stale argument list is never reported.
**Kind:** bug / language — the guide states no rule on type-argument count. Its neighbours are
issues/archived/2026-10-18-third-type-parameter-accepted-and-unrecorded.md (a THIRD type PARAMETER at a declaration) and
issues/archived/2026-10-18-non-generic-type-arguments-unrefused-in-remaining-positions.md (`<..>` on a NON-generic name, 6.7.15's
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

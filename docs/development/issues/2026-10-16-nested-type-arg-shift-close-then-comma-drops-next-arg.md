# A nested type argument closed by `>>` (or `>>>`) and followed by `,` swallows the next argument: `g2<P<P<R>>, i16>` binds B to i64 — OPEN

**Status:** 🟡 **OPEN** — found 2026-10-16 by the 6.7.14 generics lane (unit G1), writing a deeper-nesting row for
issues/2026-10-14-two-param-generic-nested-instance-names-collide.md. Pre-existing: identical on the slot-open
compiler (2600f67f's build/cycc) and on the lane tree after the nested-name fix.
**Placement:** 6.7.15 — repair 5 (generics lane; filed from the 6.7.14 generics lane, placed at the 6.7.14 wave-1 integration, 2026-10-17) — never 7.x.
**Severity:** High — a silent miscompile: the second type argument is dropped and its parameter is bound to the i64
base, no diagnostic. The trigger is a nested generic type argument whose closing `>`s lex as one `>>` / `>>>` token and
that is NOT the last argument of its list.
**Affects:** cycc since nested type arguments with `_ta_pending_gt` (v6.3.33) through the 6.7.14 slot open; every
target (the type argument is read in the frontend).

## Reproduction

```cyrius
struct P<T> { v: T; }
struct R<T> { v: T; w; }
fn g2<A, B>(a: *A, b: *B): i64 { return sizeof(A) * 100 + sizeof(B); }
var x = g2<P<P<R>>, i16>(0, 0);
syscall(60, x - 1600);
```

```
$ cat n7.cyr | build/cycc > n7 && ./n7; echo $?
8
```

Expected 2 (`P<P<R>>` is 16 B, `i16` 2 B: 1602 - 1600). B was bound to i64 (8). The coverage dump names the
instance `g2$P$P$R$i16` on the slot-open compiler and `g2$P$<P$R>$i16` on the 6.7.14 lane tree — a ONE-parameter
name whose fragment is a `P` instance minted with a second argument (`P$<P$R>$i16`), not `g2$<P$P$R>$i16`.

| shape (in the repro, `x - 1600` the exit) | got | want |
|---|---|---|
| `g2<P<P<R>>, i16>(0, 0)` (above) | 8 | 2 |
| `g2<P<P<P<R>>>, i16>(0, 0)` (`>>>`) | 8 | 2 |
| `sizeof(Two<P<P<R>>, i16>)` (`struct Two<A, B> { a: A; b: B; }`) | 24 | 18 |
| `var t: Two<P<P<R>>, i16>; ... return sizeof(Two<P<P<R>>, i16>);` in a fn | 24 | 18 |
| `g2<P<P<R> >, i16>(0, 0)` (the closes spaced apart) — control | 2 | 2 |
| `g2<i16, P<P<R>>>(0, 0)` (the nested argument last) — control; the value, not `x - 1600` | 216 | 216 |

## Root cause

`_parse_one_type_arg` (src/frontend/parse_fn.cyr): after the recursive inner argument returns, it tests
`if (PEEKT(S) == 31)` for a SECOND argument of this level BEFORE `_consume_gt(S)` pays the `>` this level is owed. When
the inner argument's close was `>>` (`_consume_gt` set `_ta_pending_gt = 1`: this level is already closed), the cursor
sits on the `,` of the ENCLOSING list — so `, i16` is read as `P`'s second argument (`in1`), `P` is instantiated with
it, `_consume_gt` then pays the owed close, and the enclosing list meets `>` after one argument: `g2`'s B is unbound
and the call takes the i64 binding.

## Fix direction

Read a second argument only while this level is still open: `if (_ta_pending_gt == 0) { if (PEEKT(S) == 31) { … } }`.
Rows: each shape in the table on every leg (x86_64, IR=3, aarch64, cx, PE), the struct form's field layout, the
controls unchanged; a mutant (the guard removed) RED.

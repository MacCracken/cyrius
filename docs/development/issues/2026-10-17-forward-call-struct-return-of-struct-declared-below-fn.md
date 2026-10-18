# A call ABOVE a fn whose RETURN type names a struct declared BELOW that fn takes the pass-1 signature with no struct: `var t: Pq = mk(10);` faults (139) at 8, 16 and 24 B, an untyped `var t = mk(10);` is "no struct type in scope", and a struct named like a vector is refused "vector return type does not match" — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-17 by the 6.7.14 vectors lane (unit V5), checking the D41 bite
(issues/2026-10-16-struct-named-like-a-float-vector-is-a-vector-only-as-a-parameter.md) with the struct declared after
its uses. Identical on the lane's base compiler (3478087aa's build/cycc) and on its tree after the D41 bite
(609c18166). Not that item's: any struct name does it.
**Placement:** 6.7.15 — repair 5 (vectors lane; filed from the 6.7.14 vectors lane, placed at the 6.7.14 wave-3 integration, 2026-10-17) — never 7.x.
**Severity:** Medium — compiles clean and faults on every target (x86_64, IR=3, aarch64, cx, PE); the untyped and the
vector-named shapes are false refusals of valid programs.
**Kind:** bug — the RETURN-side twin of issues/2026-10-17-forward-call-struct-parameter-of-struct-declared-below-fn.md
(the parameter side; same root, a struct the pass-1 prescan has not reached). That filing's rows are parameters only.

## Reproduction

```cyrius
fn main(): i64 { var t: Pq = mk(10); return t.a; }
fn mk(n): Pq { var s: Pq; s.a = n; s.b = 2; s.c = 3; return s; }
struct Pq { a; b; c; }
syscall(60, main());
```

```
x86_64 139, x86_64 CYRIUS_IR=3 139, aarch64 (qemu) 139, cx 0, PE (wine) 5        want 10
```

The same with `struct Pq { a; b; }` (16 B) or `struct Pq { a; }` (8 B): x86_64 / IR=3 / aarch64 139, cx 254, PE 5.
Untyped — `fn main(): i64 { var t = mk(10); return t.a; }`, the rest the same:

```
error:<source>:1:44: no struct type in scope for 't'; a '.field' access needs its struct declaration (missing include?)
```

Named like a vector (`sed s/Pq/f32v4/g` of the first repro — the program's struct everywhere, the user's D41 A):

```
error:<source>:1:31: vector return type does not match the declared type
```

Controls, each 17 / 10: `mk` defined ABOVE `main` with the struct still last (`var s = mk(7); var t: Pq = mk(10);
return s.a + t.a;`: 17 on every leg — pass 2 re-reads the definition before the call), or the struct declared first.

## Root cause

`_prescan_fn_sig` (src/frontend/parse_fn.cyr, the pass-1 scan `_tl_scan1`) records each fn's return as it meets the
fn: `_classify_return_type` asks `FINDSTRUCT` first, and a struct declared below the fn is not registered yet, so the
return is no struct (a plain word, the retptr default of the rough scan) — or, for a name a vector type has, the
VECTOR (`f32v4`'s descriptor). A call parsed in pass 2 before the fn's own pass-2 definition reads that record: no
hidden result pointer / pair, so the struct receive reads a word as the struct's address (139), the untyped receive
has no struct type, and the vector-named one meets the vector receive's type check.

## Fix direction

The parameter side's: register every struct (name and size) before the pass-1 signature prescan reads a return type —
a struct pre-pass, or a second signature pass once pass 1 has seen every struct — so the prescan and the definition
agree whatever the order. One fix for both filings. Rows: the three repros, 8 / 16 / 24 B, a method's return, a
generic instance `Box<Pq>` declared below, the vector-named struct (D41); the struct declared above (unchanged).

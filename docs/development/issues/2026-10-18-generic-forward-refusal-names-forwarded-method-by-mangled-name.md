# The bounded-forward refusal names the generic METHOD it forwards to by its mangled name (`it forwards its type parameter to 'P_bk'`, and its note) — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 generics lane (l6715-generics at d76d2e5cb, unit G6), x86_64
(the frontend: every target alike). Found while landing
issues/2026-10-17-generic-refusals-name-a-generic-method-by-its-mangled-name.md, whose fix names the CALLED generic as
the call spells it (`generic 'P.fw' has no i64 instance ...` for `p.fw(5)`); the second name of the forward refusal —
the generic the refused one forwards its T to — and the note under it were outside that issue's filed surface.
**Placement:** unplaced — filed from the 6.7.15 generics lane (wave 1; filed at its integration, 2026-10-18); the user places what 6.7.15 files — never 7.x.
**Severity:** Low — diagnostics only: the program is refused, at the right place; the text names `P_bk` where the
source says `p.bk(t)`.
**Kind:** bug (diagnostic).

## Reproduction

```cyrius
trait Show { fn show(self): i64; }
impl Show for f64 { fn show(self): i64 { return 5; } }
struct P { k; }
impl P { fn bk<V: Show>(self, v: V): i64 { return 1; } }
fn o1<T>(p: P, t: T): i64 { return p.bk(t); }
fn main(): i64 { var p: P; p.k = 1; return o1(p, 5); }
syscall(60, main());
```

```
error:<source>:6:47: generic 'o1' has no i64 instance: it forwards its type parameter to 'P_bk'
    ...
  note: the bound on type parameter 'V' of 'P_bk' needs `impl Show for i64`, and there is none
```

Expected: `... it forwards its type parameter to 'P.bk'` and `... of 'P.bk' needs ...`, as every other call-site
diagnostic names a method since 6.7.14 (`_fn_src_name`).

## Root cause

`_refuse_bnd_fwd` (src/frontend/parse_fn.cyr) passes `L64(_fnt_names + (_bbs_fwd - 1) * 8)` as the refusal's second
name, and its two notes print `L64(_fnt_names + r * 8)` for the chain's root `r` — the fn table's names.

## Fix direction

Name both through `_fn_src_name(S, fi, nm)`. ⚠ `_fn_src_name` writes at one GNPOS scratch, and the refusal's FIRST name
can be a `_fn_src_name` spelling too (6.7.15's `_gen_ident_err`, a method call): the second must be printed after the
first is written out (or copied), never passed in as a scratch offset computed before it — and the error's identity
must stay on the table names (`_gen_ident_err` keys on `noff`; a scratch offset in an identity merges two different
refusals at one token). Rows beside generic_method_infer.sh N3 (the forward target a method, the note's root a method;
a free forward target keeps its name).

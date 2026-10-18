# The generics refusals name a generic METHOD by its mangled fn name (`generic 'P_pick' has no i64 ... instance`, `generic 'P_bm': its type argument does not implement trait 'Show'`) — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-17 on the 6.7.14 frontend lane (l6714-frontend, unit F5) and on the lane's
base compiler (f793b013), x86_64 (the frontend: every target alike).
**Placement:** 6.7.15 — repair 5 (frontend lane; filed from the 6.7.14 frontend lane, placed at the 6.7.14 wave-1 integration, 2026-10-17) — never 7.x.
**Discovered:** 2026-10-17 by the 6.7.14 frontend lane, unit F5, implementing
issues/archived/2026-10-15-call-diagnostics-name-method-by-mangled-name.md, which gave every other call-site diagnostic the
source spelling (`S.ri`, `g<i32>`) through one helper, `_fn_src_name(S, fi, noff)` (src/frontend/parse_fn.cyr).
**Severity:** Low — the diagnostic names `P_pick` where the source says `p.pick(5)`; the position is right.
**Kind:** bug (diagnostic).
**Why filed, not fixed in F5:** this message family is the generics lane's — its 6.7.14 unit G4 (branch
l6714-generics, 2e26e069) pins the text `P_pick` in tests/gates/frontend/generic_method_infer.sh rows E5 / E6 (the stub
and bound refusals of `p.pick<i64>(9)` / `p.bm<i64>(3)`). Changing the words on the frontend lane turns those rows red
at integration; the change belongs after the merge, with the rows moved in the same commit.

## Reproduction

```cyrius
struct A { x; }
struct P { k; }
impl P { fn pick<T>(self, t: T): i64 { return t.x; } }
trait Show { fn show(self): i64; }
impl P { fn bm<T: Show>(self, t: T): i64 { return 1; } }
fn main(): i64 { var p: P; p.k = 1; var r = p.pick(5); return r + p.bm(3); }
syscall(60, main());
```

```
error:<source>:6:51: generic 'P_pick' has no i64 (or other scalar) instance: it uses its type parameter as a struct (a '.field' on a T-typed value, directly or in a generic it forwards T to) — pass a struct argument, or name a struct type argument
error:<source>:6:71: generic 'P_bm': its type argument does not implement trait 'Show'
  note: the bound on type parameter 'T' needs `impl Show for i64`, and there is none
```

Expected: `generic 'P.pick' ...`, `generic 'P.bm': ...` (a free generic keeps its name: `generic 'g' ...`).

## Root cause

The refusals print the fn table's name: `_refuse_gen_stub(S, noff)`, `_refuse_bnd_base(S, fi, noff)`,
`_refuse_gen_inst(S, noff, spec)` and `_bnd_check_fn`'s ERR_IDENT (`gnoff`), called from `_mcall_gen` /
`_mcall_inst` and the free-call paths with `L64(_fnt_names + fi * 8)` — `P_pick` for a method.

## Fix direction

Pass the name through `_fn_src_name(S, fi, noff)` at each (the method record GFMETH is already there), and move
generic_method_infer.sh's E5 / E6 (and any other row pinning `P_..` in these texts) to `P.pick` / `P.bm`.

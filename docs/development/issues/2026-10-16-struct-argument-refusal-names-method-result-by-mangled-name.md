# Struct- and vector-pointer argument refusals name a method-result argument by its mangled fn name (`'S2_dup'`) — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-16 on the 6.7.13 vectors lane (after D33's bite, `f2279be5`) and on the lane
base (`f59668ad`): the struct-type refusal (6.7.3's arm) names the argument `s.dup()` as `'S2_dup'` on both; D33's new
"pointer to a vector type" refusal inherits it. Frontend: every target alike.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (vectors lane, wave 3, unit V4; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Related:** docs/development/issues/2026-10-15-call-diagnostics-name-method-by-mangled-name.md (the CALLEE side,
`in a call to 'S_ri'`; placed 6.7.14 repair 4). This is the ARGUMENT side of the same class — one helper (a fn index ->
its source spelling) fixes both; integration may fold this file into that one.
**Discovered:** 2026-10-16, the review of the 6.7.13 vectors lane (D33).
**Severity:** Low — a diagnostic names `S2_dup` where the source says `s.dup()`; the position is right.
**Kind:** bug (diagnostic).

## Reproduction

```cyrius
struct Pt { x; y; }
struct Q { a; b; }
struct S2 { k; }
impl S2 { fn dup(self): Pt { var p: Pt; p.x = self.k; p.y = 2; return p; } }
fn rq(p: *Q): i64 { return p.a; }
fn rd(p: *f64v2): i64 { return load64(p); }
fn run(): i64 {
    var s: S2; s.k = 40;
    var a = rq(s.dup());
    return rd(s.dup()) + a;
}
syscall(60, run());
```

```
the lane (x86_64):
error:<source>:9:23: cannot pass 'S2_dup' to a parameter of a different struct type in a call to 'rq'
error:<source>:10:22: cannot pass 'S2_dup' to a parameter that is a pointer to a vector type in a call to 'rd'
the base (f59668ad): the first line alone (D33's refusal is new)
```

## Root cause

The struct-argument refusals (`_sarg_type_err` and D33's `_sarg_svec_err`, src/frontend/parse_fn.cyr) print the
argument `anoff` that `_push_struct_expr_arg` passes them: `_sc_fn`, the struct-call record's name offset, which
`_sc_post` / `_sc_post_small` set to the resolved callee's name — for a method the mangled `T_m`; the source spelling
`s.dup()` is not kept.

## What a fix needs

Name a method-result argument as written (`s.dup()`, or `S2.dup`) — the same helper the callee-side issue proposes;
rows asserting the spelling in both refusals.

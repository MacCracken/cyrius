# A parenthesised `: stack` pair call escapes every pair check: `var v = (f(7));`, `x = (f(7));`, `h.a = (f(7));`, `P { (f(7)), 3 }` keep the tag silently, and `var v = (f(7))?;` takes the boxed `?` and SIGSEGVs — RESOLVED

> ✅ **RESOLVED in v6.7.13** (MV-8, with the lane-gate fix MV-19 (the user's decision D19, 2026-10-15: A, parentheses transparent to every pair check): parentheses around a whole `: stack` pair call are transparent to every pair check, in the parser and the token passes alike, through one helper, `_pair_unwrap` (linear in the depth since MV-19). Filed repro 1, `var v = (f(7))?;`, crashed (139 / 139 / cx 1 / PE 5) and propagates: 77 on x86_64, aarch64, cx and PE. Filed repro 2's four wrapped stores, which each kept the tag (0), are each refused "bind both" on all four. So is every other filed one-slot store: `x += (f(7))`, `a[0] = (f(7))`, `*p`, `store64`, a positional / named / nested literal element and a global. `?` on a wrapped generic or method call propagates (242). `return (f(x));` forwards the pair in either definition order, without the false mixed-return warning. `g((f(7)))` still receives the tag (6.7.11's D22). Rows: `frontend/stack_enum_lossy_context.sh` axis PW (PW1 / PW2r the repros verbatim, PW2 – PW17), `frontend/stack_enum_mixed_return_warning.sh` `pw_*` (x86 + aarch64) and `crossos/method_pair_result.tcyr` `pw_free` / `pw_meth` / `pw_impl` / `pw_fwd` (0 on ecb / ach / cass / pi); mutations MPW1 – MPW5 RED. Filed beside it (6.7.14, language questions): `2026-10-15-paren-wrapped-pair-operand-store-keeps-tag.md` (`var v = (f(7) + 1);` keeps the tag) and `2026-10-15-paren-wrapped-call-destructure-refused.md` (`var a, b = (f(7));`). CHANGELOG [6.7.13])

**Status:** ✅ **RESOLVED in v6.7.13** (see the banner). Was: 🟡 **OPEN** — reproduced 2026-10-14 on the 6.7.11 returns lane tip (l6711-returns, `build/cycc` the fixpoint
of 4288c67f + the review's doc fix) and on the lane base 0f733aea (the slot-open cycc, 2,114,376 B), x86_64. The pair
flag and every check below are shared frontend state, so the aarch64 / cx / PE compilers take the same path.
**Placement:** 6.7.13 — repair 3: struct values (multivalue lane; re-placed at the 6.7.13 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.13 open):** D19 — A.
**Severity:** High — valid `?` code crashes at run time with no diagnostic, and every lossy one-slot store the
unwrapped spelling refuses compiles clean and keeps the tag (the payload, an `Err`'s error code, is gone).
**Affects:** every compiler since the pair checks (v6.5.67 bind, 6.6.0 assignment / `?`, 6.7.7 stores, 6.7.11 the
struct-literal element) — pre-existing; outside every filed surface of the 6.7.11 returns lane.
**Discovered:** 2026-10-14, the 6.7.11 returns lane's review (of 43066167, the struct-literal element refusal).

## Reproduction

`?` on a wrapped pair call crashes; the unwrapped `t2` is right:

```cyrius
enum Res: stack { ROk(v); RErr(e); }
fn f(x) { return ROk(x); }
fn t1() { var v = (f(7))?; return ROk(v); }
fn t2() { var v = f(7)?; return ROk(v); }
fn main(): i64 { var c, d = t2(); var a, b = t1(); return b * 10 + d; }
syscall(60, main());
```

Compiles clean (rc 0, no diagnostic), exits **139** on the lane tip and on the base. Right: 77.

Every lossy store, wrapped, compiles clean and keeps the tag:

```cyrius
enum Res: stack { ROk(v); RErr(e); }
fn f(x) { return ROk(x); }
struct P { a; b; }
fn t1(): i64 { var v = (f(7)); return v; }
fn t2(): i64 { var x = 0; x = (f(7)); return x; }
fn t3(): i64 { var h: P; h.a = (f(7)); return h.a; }
fn t4(): i64 { var p = P { (f(7)), 3 }; return p.a; }
syscall(60, t1() * 1000 + t2() * 100 + t3() * 10 + t4());
```

Compiles clean, exits **0** (each slot holds the tag `ROk` = 0), lane tip and base alike. `x += (f(7));` and
`a[0] = (f(7));` the same (0). The unwrapped controls are refused by name, as documented:

```
error:<source>:3:22: a `: stack` enum returns two values — bind both: `var tag, val = f();`
    fn t1(): i64 { var v = f(7); return v; }
                         ^
error:<source>:4:31: a `: stack` enum returns two values — bind both: `var tag, val = f();`
    fn t2(): i64 { var x = 0; x = f(7); return x; }
                                  ^
```

In a struct literal, `H { f(7), 3, 5 }` and `P { b: 3, a: f(7) }` are refused (6.7.11) while `H { (f(7)), 3, 5 }`
and `P { (f(7)), 3 }` are not.

## Root cause

`_callee_returns_pair_at(S, ti)` (src/frontend/parse.cyr) asks `_pair_callee_at` for the callee whose first token is
at `ti`; with `(` there it finds none and answers 0. Every consumer reads the call at the cursor without stepping over
a whole-value wrap (the 6.7.6 "parentheses are transparent" rule, `_pwrap_k`):

- `_tpair` in `_PARSE_TERM_IMPL` (fed by `_callee_returns_pair`) is 0 for the `(f(7))` term, so `?` takes the BOXED
  lowering and dereferences the tag as a pointer — the SIGSEGV the 6.6.0 comment above `_refuse_single_pair_bind`
  warns of;
- `_refuse_single_pair_bind` (`var v = ..`), `_refuse_lossy_pair` (assignment, field / element / `*p` / `OP=`
  stores, `store64`) and the 6.7.11 struct-literal element check see `(` first and pass;
- `_call_is_propagated(S, ti)` scans from the wrap's `(`, so for `(f(7))?` its "token after the closing paren" is the
  inner call's `)`, not the `?`.

## Fix

Peel a whole-value wrap before asking: `_callee_returns_pair_at` (or its callers) steps `_pwrap_k` parentheses whose
close ends the operand, and `_call_is_propagated` looks for `?` after the wrap's close. The refusals then fire with
their documented text and `(f(7))?` propagates as `f(7)?` does. Rows: each shape above (bind, assignment, field,
element, `OP=`, `*p`, `store64`, positional / named / nested struct-literal element, a global), `?` on a wrapped free
call, generic call and method call, in tests/gates/frontend/stack_enum_lossy_context*.sh; a crossos row for the `?`
run result.

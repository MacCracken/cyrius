# A generic call's `T = f64` result is an untyped word when T is inferred or only the return type — `gid(h) * 2.0` multiplies bits — RESOLVED

> ✅ **RESOLVED in v6.7.9** (the critical lane's bite 9, l679-crit; CHANGELOG [6.7.9]) a generic call whose `T = f64` is inferred or names `T` only in its return is an f64 (the user's decision 1(e)): a whole f64 argument (an f64 local or parameter, an f64 global, a float literal, a call returning f64 — a generic one at its f64 instance) binds `T = f64` and calls the f64 instance, as `g<f64>(..)` does (`_infer_conc_at_cursor` / `_gen_infer_tp`, parse_fn.cyr); an instance's `: T` at `T = f64` is an f64 return (-9, xmm0 on x86; `_gtype_tp_ret`), settling the -8 / -9 ABI; the inferred call is typed from the instance it reaches (`_gcall_ret_f64`, from `_call_scale_fix`), the explicit one by `_call_ret_marks` (`_explicit_generic_call`), and a generic METHOD binds an f64 `V` the same way (`_mcall_gen`: the method arm and `var w = p.id(h);`). The repro exits 0 (was 7) with no warning on x86 / IR=3 / aarch64 (qemu) / cx / PE (wine); `tests/tcyr/crossos/generic_f64_result.tcyr` (44 rows, 28 red before) on x86 / IR=1 / IR=3 / DCE=1 / aarch64 / cx / PE through `frontend/generic_f64_result.sh`, mutation-proven eleven ways. A 1061-source differential compiles byte-identically except the repro and one values file (`gget<f64>`, now typed at the call).

**Status:** ✅ **RESOLVED in v6.7.9** — see the banner above and *Resolution* below (reproduced on the 6.7.9 lane tip @
fd1cc8f7 before the fix: the repro exits 7 with three warnings; the explicit controls were right only when inlined —
`gid3<f64>(h, 1, 2) * 2.0`, never inlined, was integer arithmetic too). As filed: 🟡 OPEN — reproduced 2026-10-10 against the merged 6.7.8 tip (l678-int @ 85ee576f, `cycc_merged`
2,053,536 B) with the tree's compiler and the cross compilers built from it: the repro exits 7 on x86_64, aarch64
(qemu), cx (cxvm) and PE (wine), where 0 is right, and each failing row warns "integer arithmetic with an f64 right
operand". The installed 6.6.20, 6.7.4 and 6.7.7 compilers also exit 7. The C2 lane reported the explicit, return-only
shape; verifying it found that EVERY inferred call is affected too (`gid(h) * 2.0`).
**Placement:** 6.7.9 — the repair batch, the critical / high lane (user, 2026-10-11) — never 7.x.
**Discovered:** 2026-10-10 by the 6.7.8 C2 lane, bite C2-4a (reported only, `~/.cache/c6/c2/changelog_handoff.md` §
*C2-4a — out of scope*: `gg<f64>(&B, 2) * 2.0`); the inferred shapes were found verifying it for this filing.
**Severity:** Medium — a wrong value on source that compiles, with a spurious warning as the only sign (the method
issue's grading); every generic returning `T` at `T = f64` meets it unless the result is bound to an `f64` first.
**Affects:** cycc 6.6.20 – 6.7.8 measured (6.6.20, 6.7.4, 6.7.7, the merged 6.7.8 tip); not bisected further.

## Summary

A call's f64 result must be typed f64 (`SESTYPE(F64_TYID)`) so the next operator takes the float arm. For a generic fn
returning `T`, that happens only on the explicit spelling with a `T`-typed parameter (`gid<f64>(h)`,
`gid2<f64>(h, 1)`). Two shapes leave the result an untyped word holding the double's bits:

1. **Any INFERRED call** — `gid(h) * 2.0` with `fn gid<T>(x: T): T` and `h: f64`; `gid2(h, 1) * 2.0`.
2. **An explicit call whose `T` is only the return type** — `gg<f64>(&h) * 2.0` with `fn gg<T>(q): T`.

The outer `* 2.0` then multiplies the bit pattern as an integer. `var v: f64 = gid(h);` followed by `v * 2.0` is right
(the annotation types the variable); `var v = gid(h);` is an untyped word.

## Reproduction

`docs/development/issues/repros/2026-10-10-generic-call-f64-result-untyped.cyr`:

```cyrius
include "lib/syscalls.cyr"
fn gg<T>(q): T { return load64(q); }
fn gid<T>(x: T): T { return x; }
fn gid2<T>(x: T, k): T { return x; }
fn main(): i64 {
    var h: f64 = 1.5;
    var bad = 0;
    if (gg<f64>(&h) * 2.0 != 3.0) { bad = bad | 1; }      # explicit, T only in the return
    if (gid(h) * 2.0 != 3.0) { bad = bad | 2; }           # inferred
    if (gid2(h, 1) * 2.0 != 3.0) { bad = bad | 4; }       # inferred, an integer last argument
    if (gid<f64>(h) * 2.0 != 3.0) { bad = bad | 8; }      # control
    if (gid2<f64>(h, 1) * 2.0 != 3.0) { bad = bad | 16; } # control
    return bad;
}
var rc = main();
syscall(60, rc);
```

```
expected: exit 0
actual:   exit 7 (rows 1, 2, 4; three "integer arithmetic with an f64 right operand" warnings) on all four targets
```

Run it from the repo root: `cat <repro> | build/cycc > /tmp/r && chmod +x /tmp/r && /tmp/r; echo $?`.

## Root cause

`src/frontend/parse_expr.cyr`:

- **Inferred (shape 1):** PARSE_FACTOR's call arm runs `PARSE_FNCALL(S, noff)` (which resolves the generic to its
  instance) and then `_call_ret_marks(S, FINDFN(S, noff))` (`:3849`). `FINDFN(noff)` is the generic BASE, whose return
  `T` is recorded as the i64 base's, not `-9`, so `_call_ret_marks` (`:2634`, `GFRS == 0 - 9`) never types the result.
- **Explicit (shape 2):** `_explicit_generic_call` (`:2560`) calls the instance and then only `_call_ret_ps(S, _spec)`
  (`:2597`) — no `_call_ret_marks` on the instance. Why the explicit spelling WITH a `T` parameter is typed right
  (the controls) is not traced; speculation: something in the instance call path types it from the parameter, which a
  return-only `T` does not have.

## Proposed fix

Type a call's result from the fn the call REACHES: have PARSE_FNCALL (or `_gen_resolve_call`) leave the resolved
instance's fi where the factor reads it, and call `_call_ret_marks` on that fi in both the inferred arm (`:3849`) and
`_explicit_generic_call` (`:2597`), making sure the instance's return sid is `-9` at `T = f64` (an f32 `T` checked the
same way: `gid(f) * 2.0` with `f: f32` warns the same "integer arithmetic" today). Rows: the repro's five rows plus `T = f32`, a `*T` return, a generic method
(`p.m(h)`, after [the method issue](2026-10-09-method-call-result-keeps-last-arg-f64-type.md)), a forward call to an
instance, at the four targets; the `var v = gid(h);` binding typed f64.

## The method spelling needs its own arm (appended 2026-10-11, 6.7.9 critical lane bite 8)

[The method issue](2026-10-09-method-call-result-keeps-last-arg-f64-type.md) is fixed: a method call's result is
typed as a free call's (`_mcall_ret`: the reset, then `_call_ret_marks`). One consequence lands here. With
`impl P { fn id<V>(self, w: V): V { return w; } }` and `h: f64`, `p.id(h) * 2.0` was 3.0 before that fix only because
the method arm handed the LAST argument's type to the result (`p.id2(h, 1) * 2.0` was already integer arithmetic);
it is now integer arithmetic with a kind-2 warning, exactly as `P_id(&p, h) * 2.0` and `gid(h) * 2.0` (shape 1)
are. Measured on the bite-8 tree (x86_64): `p.id(h)`, `p.id(1.5)`, `p.id2(h, 1)` and `P_id(&p, h)` each `* 2.0`
are integer arithmetic; `p.sc(h) * 2.0` with a plain `fn sc(self, w: f64): f64` is right.
⚠ "Type the result from the fn the call REACHES" types nothing on the method spelling: the method arm calls the
generic's i64 BASE ([2026-10-10-generic-method-call-runs-i64-base.md](2026-10-10-generic-method-call-runs-i64-base.md),
placed 6.7.11), whose return is not -9. So this issue's generic-method row (`p.m(h)`) needs `V`'s binding from the
method's arguments at the method arm (or that issue's instance), not only the free call's instance — or the method
spelling stays wrong through 6.7.11.

## Resolution (6.7.9, the critical lane's bite 9)

Why the explicit controls were right: only by the inline replay. `gid<f64>(h)`'s instance is one statement, so the
call replays its body, and `return x` (x typed f64 in the instance) leaves its f64 type on the expression — the
PARSE_FNCALL inline path returns without the reset. Measured: the same spelling on a three-parameter generic (never
inlined), `gid3<f64>(h, 1, 2) * 2.0`, was integer arithmetic; so was the explicit `gk<i64>(..) * 2.0` of a generic
with a concrete `: f64` return (the explicit arm never ran `_call_ret_marks`, and the double stayed in xmm0). And the
inferred shape was worse than untyped: `gid(h)` never reached an instance — an f64 argument inferred i64, so the call
ran the i64 base, and `dbl(h)` with `return x + x` added the double's bits (the base IS the i64 instance).

- **What binds `T = f64`** (`_infer_conc_at_cursor`, parse_fn.cyr): an f64 local or parameter (`_load_lt` = F64_TYID; a
  `*f64` stays a pointer), an f64 global (`_infer_conc_global`), a float literal (`_ic_flit`), and a call returning f64
  — already -9 for a `: f64` fn, and now a generic call at its f64 instance (`_ic_call_rs`: `gid(gid(h))`) — each as the
  WHOLE argument (`_gen_arg_whole`, the struct rule: `g(h * 2.0)` stays i64). `_gen_infer_tp` marks `_gi_sc` for -9, so
  `_gen_call_head`, `_gen_resolve_call` and `_tc_generic_divert` (a tail call diverts to the normal path) all reach
  the instance through 6.7.8's `_gen_sc_inst` path, which also keeps a stub generic's i64 refusal. An `f32` is not a
  type argument (nor a return type), so `g(f)` with `f: f32` keeps `T = i64`; the gate's W rows pin both edges.
- **The ABI, settled**: `_gtype_tp_ret` answers -9 for `T = f64`, so an instance's `: T` is recorded and parsed as a
  written `: f64` — its returns box into xmm0 at the landing (`_ret_box_f64`), an inlined replay of it too, and every
  call site reads it back (`_call_ret_marks`). The rough scan's struct-stash test reads only a positive answer.
- **Typing the result from the fn the call REACHES**: the inferred arm types from FINDFN's entry (the base), so
  `_call_scale_fix` — which already resolves the reached instance (`_pair_gen_inst`) for every whole call — now calls
  `_gcall_ret_f64`: an instance returning -9 whose base does not is moved and typed there (no new reference in
  `_PARSE_FACTOR_IMPL`). `_explicit_generic_call` runs `_call_ret_marks` on the fn it calls (the instance, or the base on
  the all-i64 path) in place of `_call_ret_ps`.
- **The method spelling**: the method arm called the generic's i64 base (the other issue below). `_mcall_gen`
  (parse_fn.cyr) infers each type parameter from the method's arguments — `self` is parameter 0 and not in the list,
  so parameter k is position k - 1 (`_call_arg_pk`, `_call_arg_for`'s positional offset) — and calls the f64 instance
  when one binds f64; one line in `_field_load_on` (cybs's per-fn ceiling) and one in `_var_rhs_msid`, so `var w =
  p.id(h);` is an f64 binding (that line's f64 half, `var a = p.area();` for a plain `: f64` method, was the repair
  made in passing just before). A STRUCT `V` is not taken on this arm: that stays
  [2026-10-10-generic-method-call-runs-i64-base.md](2026-10-10-generic-method-call-runs-i64-base.md) (6.7.11), which
  can extend `_mcall_gen`.
- **Warnings move with the type**: `gid(h) * 2` now draws the kind 1 that `h * 2` draws, `2 * gid(h)` a kind 2, and
  `p.id(h) * 2.0` none.
- **A bound is met at the type the call binds** (6.7.1's rule, `_bnd_check_fn` at instantiation): with `fn gb<T:
  Show>(x: T)`, `gb(h)` now calls `impl Show for f64`'s method (it called the i64 impl on the double's bits), and with
  only `impl Show for i64` it is refused by name — "needs `impl Show for f64`" — exactly as `gb<f64>(h)` always was
  (it compiled before and ran the i64 impl on the bits). The method spelling `p.bm(h)` is the same. This is the one
  shape that compiled before and does not now; the gate's B rows pin it. No tree source meets it.
- **Measured narrow**: a differential compile of 1061 tree sources (the `.tcyr` corpus, `lib/`, `programs/`,
  `benches/`, `fuzz/`, the repros, the compiler forks) is byte-identical, diagnostics included, except the filed repro
  and `tests/tcyr/crossos/pointer_subscript_values.tcyr`, whose `gget<f64>(&BUF, 2)` (T only in the return) is now
  typed at the call (its rows pass before and after).

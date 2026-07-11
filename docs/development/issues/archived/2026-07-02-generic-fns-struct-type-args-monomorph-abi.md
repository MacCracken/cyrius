# Generic FUNCTIONS with STRUCT type-arguments need a monomorphized struct-ABI (follow-on)

> **STATUS (2026-07-07): NARROWED to the multi-tparam residual.** The single-type-param
> cases SHIPPED — struct-return + inferred-lookahead **v6.3.38 (B1/B2)**, struct-by-value
> param + the −3 guard drop **v6.3.39 (B3)**. The only OPEN scope is the **mixed
> multi-type-param** combo (`wrap<i64,Point>` / `Two<Point,i64>` with a generic fn),
> intentionally rejected as unproven. Stays the demand-gated prerequisite ahead of
> trait-bounded generics (no dedicated slot). Roadmap wording corrected at
> roadmap_6.md + roadmap-future.md (was "the open B3 bug", which shipped).

**Filed:** 2026-07-02 (v6.3.33 generics-tail slot)
**Severity:** N/A for default builds (`CYRIUS_MONOMORPH=1` is opt-in experimental; default codegen byte-identical — differential 306/306). Blocks the experimental struct-type-arg-on-generic-fn surface.
**Component:** `src/frontend/parse_fn.cyr` `_instantiate_generic_fn` (token-replay monomorphization) + the struct by-value param / retptr ABI.

## What works (v6.3.33)

Generic **structs** with struct type-args fully work: `var h: Holder<Point>` (nested field
access `h.v.x`), `Two<i64, Point>` (multi-type-param with a distinct struct 2nd param),
`Box<Pair<i32>>` (nested generic). Generic **functions** work for **scalar** type-args:
`add<i32>`, `firstof<i64, i32>`, `maxof<i64>` (incl. control-flow in the body).

## What's guarded off

A generic **function** instantiated with a **struct** type-arg — `id<Pair<i32>>(p)`,
`wrap<i64, Point>(0, p)` — is HARD-ERRORED (v6.3.33): `_instantiate_generic_fn` returns `-3`
when `conc0 > 0 || conc1 > 0` (a struct sid), and the call site (`parse_expr.cyr`) emits
`"generic fns with STRUCT type-arguments are a follow-on (monomorphized struct-ABI); use a
generic struct or scalar type-args"`. This replaced a **silent miscompile**: pre-guard,
`wrap<i64, Point>` returned 60 instead of 42 — the by-value struct param + struct-return retptr
were not rebound per instance.

## Root cause / why it's a real follow-on

The token-replay path (`_instantiate_generic_fn` re-invokes `PARSE_FN_DEF` on the base tokens
with `T→conc` bound) re-parses the signature + body correctly, but a **struct-typed param** flows
by value (16-byte inline / retptr shift) and a **struct-typed return** allocates caller-side space
+ passes `&space` as the hidden first arg. Those ABI decisions (`_cur_fn_ret_sid` / retptr stash /
by-value copy) were computed for the BASE (i64) instance and don't re-derive when `T` becomes a
struct in the replayed instance — so the emitted prologue/epilogue + arg shuffle are wrong.

Two observable sub-symptoms:
1. `var q = id<Pair<i32>>(p)` (inference) — the caller's inferred-struct-local lookahead
   (`parse_decl.cyr` ~1556, reads the callee `GFRS`) sees the BASE fn's return (i64/scalar), not
   the instance's struct sid, so `q` isn't typed as a struct → `q.a` is a parse error. (Explicit
   `var q: Pair<i32> = id<Pair<i32>>(p)` compiled + ran correct — 42 — for the single-param case,
   which is why the guard is deliberately broad: reject ALL struct-type-arg fn instances for a
   CONSISTENT surface rather than "single works / multi miscompiles".)
2. `var q: Point = wrap<i64, Point>(0, p)` (explicit) — compiled but returned the wrong value
   (struct-return / by-value-struct-param ABI not rebound).

## Fix (a dedicated slot)

Make `_instantiate_generic_fn` re-derive the struct ABI per instance: when a bound `T` resolves to
a struct sid, set the instance fn's `GFRS` / `_cur_fn_ret_sid` / retptr-stash + by-value param
layout from the concrete struct (not the base), and teach the caller's inferred-struct-local
lookahead to compute a generic call's instance return type. Then drop the `-3` guard. Add fixtures
for `id<Struct>` (return), `wrap<i64, Struct>` (mixed param), and struct-in / struct-out combos.

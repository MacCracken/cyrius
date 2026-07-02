# Monomorph inline instance emission clobbers a live local when it follows a branch

**Filed:** 2026-07-02 (v6.3.33 generics-tail slot — surfaced by adversarial verification)
**Severity:** N/A for default builds (`CYRIUS_MONOMORPH=1` is opt-in experimental; default codegen
byte-identical). A wrong-value miscompile in the gated monomorphization path.
**Component:** `src/frontend/parse_fn.cyr` `_instantiate_generic_fn` (the closure-style, jump-over
INLINE instance emission) × branch/register state.
**Pre-existing:** reproduces identically on the v6.3.10 engine — confirmed on the committed HEAD
`build/cycc` (1011688 B) and on the v6.3.33 fixed compiler. NOT introduced by the v6.3.33 fixes
(nested field-access width / special-type guard) — those touch unrelated code paths.

## Minimal repro (exit should be 37, actual 7)

```
fn idg<T>(a: T): T { return a; }
fn main(): i64 {
    var r = 30;
    if (r > 1000000) { r = r + 900; }     # branch (condition can be trivially false)
    r = r + idg<i32>(7);                   # r loaded, then FIRST-USE inline instance emit, then +
    return r;                              # got 7 → r was clobbered to 0 across the call
}
```

`r = r + idg<i32>(7)` returns 7, not 37: the value of `r` loaded before the call is lost across the
inline emission of `idg`'s instance, so the `+` adds to 0.

## Trigger boundary (all four required)

1. A **branch** precedes the call (`if`; a `while` does NOT trigger it — `③a` returns 37).
2. The generic fn's instance is emitted **inline on first use** at this call site. Pre-instantiating
   the same instance earlier makes it a dedup hit → correct (`③c` returns 37).
3. The call is a generic **fn** (closure-style jump-over emission). A generic **struct** after the
   same branch is fine — structs are registration-only, no inline codegen (`③d` returns 37).
4. The result is combined with a value that is **live across the call** in the same expression
   (`r = r + call()`). Assigning to a fresh local (`var q = call(); return s + q`) is fine
   (`③b` returns 107) — nothing needs to survive the inline emission in a register.

## Root-cause direction

`_instantiate_generic_fn` emits the specialized body INLINE into the caller's stream (EJMP0 over the
body, emit prologue/body/epilogue, EPATCH the jump), then emits the call. It saves/restores per-fn
codegen state (`_cur_fn_regalloc`, locals snapshot, `rp_vec`, `_cur_fn_has_closure=1`, cursor). The
failure is that an operand register holding a value **live across this call site** (the LHS of the
`+`) is not spilled/preserved across the inline body emission — but only once a preceding branch has
put the register allocator into the state that assigns `r` to that register. A normal call spills
in-flight operands; the inline instance injection appears to clobber without spilling. Likely fix:
spill/reload the in-flight expression operand around the inline instance emission (or force the
instance to be emitted at a safe point, e.g. hoist first-use instantiation out of the expression),
and/or make the closure-style save/restore cover the caller's in-flight operand register.

## Not a `_generics_tail` deliverable

The tail deliverables (nested `Box<Pair<i32>>`, multi-param `Two<i64,Point>`, control-flow in generic
bodies) all work and are distinguishingly tested. This is an orthogonal branch × inline-emission
register bug — its own focused fix + a `tcyr` covering `if`-then-first-use-generic-fn-call.

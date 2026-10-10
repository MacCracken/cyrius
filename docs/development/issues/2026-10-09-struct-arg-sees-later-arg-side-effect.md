# A by-value struct argument over 8 bytes sees a later argument's side effect — RESOLVED

> ✅ **RESOLVED in v6.7.7** (462e6112; CHANGELOG [6.7.7]) an argument the callee copies in its prologue is copied where it stands when a later argument may write it (`_sarg_snap`; a vector, `_simd_arg_snap`) — every argument source, call form and backend (`by_value_arg_copy.sh`, `crossos/by_value_arg_evaluation_order.tcyr`).

**Status:** ✅ **RESOLVED in v6.7.7** — see the banner above (filed OPEN 2026-10-09 against 6.7.6 @ e44470b7).
**Placement:** 6.7.7 — shipped (integration lane: call arguments).
**Discovered:** 2026-10-09 during the 6.7.7 B6 (default and named arguments) planning (repro `sord.cyr`). B6's named
arguments are evaluated as written and inherit this unchanged.
**Severity:** Low — a by-value parameter observes a mutation made after its argument was evaluated. It needs an
argument with a side effect on an earlier struct argument.
**Affects:** cycc ≤ 6.7.6. Measured with the installed 6.6.5, 6.6.10, 6.6.16, 6.7.0 and 6.7.3 compilers and the tree's
6.7.6 (exit 3 on each); 6.6.0 crashes on the repro.

## Summary

A parameter declared with a plain struct type over 8 bytes is a value. The caller passes the struct's ADDRESS, and
the callee copies it into its own frame in its prologue (6.6.16, `_sptr_params_localize`). The copy therefore happens
after every argument has been evaluated.

So an argument evaluated later that writes the struct is visible to the callee, and the parameter holds the struct as
it is at the call, not as it was when its argument was written. `rd(b, bump(&b))` reads 11; a call whose struct
argument comes last, or whose struct is 8 bytes or smaller, reads 1. Win64's value-form vectors, which also travel by
pointer and are copied in the prologue, are likely affected the same way (not probed).

## Reproduction

`docs/development/issues/repros/2026-10-09-struct-arg-sees-later-arg-side-effect.cyr`:

```cyrius
struct Big { a: i64; b: i64; c: i64; }
struct Mid { a: i64; b: i64; }
struct Sm { a: i64; }
fn bump(p): i64 { store64(p, load64(p) + 10); return 0; }
fn rd(s: Big, z): i64 { return s.a; }
fn rm(s: Mid, z): i64 { return s.a; }
fn rs(s: Sm, z): i64 { return s.a; }
fn main(): i64 {
    var b: Big = Big { 1, 2, 3 };
    var m: Mid = Mid { 1, 2 };
    var s: Sm = Sm { 1 };
    var e = 0;
    if (rd(b, bump(&b)) != 1) { e = e | 1; }
    if (rm(m, bump(&m)) != 1) { e = e | 2; }
    if (rs(s, bump(&s)) != 1) { e = e | 4; }
    return e;
}
var r = main();
syscall(60, r);
```

```
actual:   rc 0, exit 3 (the 24-byte and 16-byte rows read 11)
expected: exit 0 (every row reads 1)
```

Run it from the repo root: `cat <repro> | build/cycc > /tmp/r && chmod +x /tmp/r && /tmp/r; echo $?`.

## Root cause

- `src/frontend/parse_fn.cyr:1547` `_try_push_struct_addr_arg`: a parameter in `_pm_struct` (a by-value struct over
  8 B) receives the argument's address.
- `src/frontend/parse_fn.cyr:1999-2014` (the 6.6.16 C7 comment) and `_sptr_params_localize`: the callee copies through
  that address in its prologue, after all the arguments were evaluated.

## Proposed fix

Snapshot the struct at its argument's position whenever a later argument of the same call might write it: copy into a
caller-frame temporary (the `_struct_call_into_temp` / `_agc_copy_bytes` machinery the struct-call arguments already
use) and pass the temporary's address.

To keep the common case free, the copy is needed only when an argument after the struct argument is not side-effect
free, which in practice means it contains a call or an assignment. At top level (no frame) the hidden-global temporary
form applies.

Add a gate row with the repro on x86, aarch64 and PE.

## Consumer-side workaround

Evaluate the side-effecting argument first, into a local (`var z = bump(&b); rd(b, z);`), or pass the struct last.

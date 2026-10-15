# `g<f64v2>(b)` with `fn g<T>(p: *T)` reports a second error from D27's refusal (naming the instance `g$i`) after the type-argument refusal — a cascade — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-15 on the 6.7.12 fixfirst lane (x86_64; frontend, every target alike): two error lines where the slot-open compiler (`7f57e532`) printed one. A diagnostic cascade D27 (`2026-10-13-vector-value-into-pointer-parameter-passes-lane-bits.md`) introduced.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (generics lane; filed from the 6.7.12 fixfirst lane, placed at the 6.7.12 integration, 2026-10-15) — never 7.x.
**Discovered:** 2026-10-15, the review of the 6.7.12 fixfirst lane.
**Severity:** Low — a second, misleading error on input already refused (no binary either way).
**Kind:** bug (diagnostic).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/simd.cyr"
fn g<T>(p: *T): i64 { return load64(p); }
fn main(): i64 {
    var b: f64v2 = f64v2_make(42, 7); return g<f64v2>(b);
}
var rc = main();
syscall(60, rc);
```

```
fixfirst lane:
error:<source>:5:53: generic type-args must be a scalar (i8/i16/i32/i64) or a struct; Result/Option/Tagged/cstring/f64v2/f64v4 are unsupported
error:<source>:5:55: cannot pass 'b' to a parameter that is not a pointer to its vector type in a call to 'g$i' - pass &b for its address
slot-open 7f57e532: the first line only
```

(Plain `g(b)` refused by name — "... in a call to 'g' - pass &b for its address" — is consistent: a generic takes no
vector type argument; it faulted before, x86_64 139.)

## Root cause

`_vec_kind_err` (src/frontend/parse_fn.cyr) deliberately sets no panic latch (`_had_error` only), so that one compile
reports every refused vector argument; it therefore also fires after an unrelated refusal of the same call. Here the
refused type argument leaves the call on the `i64` instance (`g$i`), whose `p: *T` is `*i64`, and D27's other-pointer
refusal reports `b` against it.

## Proposed fix

Skip `_vec_kind_err` (and A2's different-vector-type refusal) for a call whose own type arguments were refused — a
per-call latch set by the type-argument refusal, cleared at the call's open — so the call reports one error. Row beside
simd_pointer_param.sh Y12: `g<f64v2>(b)` refused once.

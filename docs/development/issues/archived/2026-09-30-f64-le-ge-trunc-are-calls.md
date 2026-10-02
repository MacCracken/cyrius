# `f64_le`, `f64_ge` and `f64_trunc` are function calls, 2–3× the cost of the builtins they wrap

**Status:** ✅ **RESOLVED v6.6.13** (bite I5) — `f64_le`, `f64_ge` and `f64_trunc` are compiler builtins (x86 `roundsd $3`, aarch64 `frintz`, cx opcode 0x6E); the `lib/math.cyr` wrappers are retired and the three names are reserved. See CHANGELOG [6.6.13].
**Placement:** **6.6.13**, bite I5 (memory fixes + reported-issue repair, set by the user 2026-10-01) —
see `roadmap.md` § 6.6.13. Builtins, after an ecosystem survey for local definitions of the three names.
**Discovered:** 2026-09-30, abaco 2.4.9 (its `f64_round_half_away` doubled in cost, 8 → 15 ns,
when it moved to `f64_trunc` + `f64_ge`).
**Severity:** Low — performance only; results are correct. (Not > 2× on whole consumer paths,
but 2–3× per call.)
**Affects:** cyrius 6.6.12 `lib/math.cyr`: `f64_le` (:771), `f64_ge` (:776), `f64_trunc` (:803).

## Summary

`f64_lt`, `f64_gt`, `f64_eq`, `f64_floor` and `f64_abs` are compiler builtins. `f64_le` and
`f64_ge` are ordinary functions that call two of them (`f64_lt(a,b) == 1` then `f64_eq`), and
`f64_trunc` is a function that branches to `f64_ceil` or `f64_floor`. Each costs a call frame.
The `:767-770` comment explains why `f64_le` must not be the bare `<=` operator (the 2026-06-24
NaN issue) — that stays right; the cost is only the call.

Measured, 2×10^8 iterations each, DCE build, x86_64, cyrius 6.6.12 (ns per iteration, loop
overhead ~1 ns included):

| expression | ns/iter |
|---|---|
| `f64_le(x, y)` | 4.71 |
| `f64_lt(x, y) == 1 \|\| f64_eq(x, y) == 1` (same result, NaN included) | 2.59 |
| `f64_trunc(x)` | 4.60 |
| `f64_floor(x)` (same result for x ≥ 0) | 1.42 |

In abaco, rewriting hot paths with the builtins took `round` from 15 back to 11 ns and
`time_constant` from 52 to 46 ns.

## Reproduction

The timing loop, built with `CYRIUS_DCE=1 cyrius build`, run under `time`; swap the marked line
for each row of the table:

```
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/math.cyr"
fn main() {
    var acc = 0;
    var x = f64_from(3);
    var y = f64_from(5);
    var i = 0;
    while (i < 200000000) {
        acc = acc + f64_le(x, y);          # <- the expression under test
        x = x ^ (i & 1);
        i = i + 1;
    }
    return acc & 1;
}
var r = main();
syscall(SYS_EXIT, r);
```

## Proposed fix

Make `f64_le`, `f64_ge` and `f64_trunc` builtins (or have the compiler inline these three
one-line wrappers), keeping their NaN semantics: `f64_le(a, b)` = `a < b || a == b` with IEEE
comparisons, false when either is NaN. `f64_trunc` can lower to `roundsd $3` (SSE4.1) or
`frintz` on aarch64.

## Consumer-side workaround

Write the builtin form inline in hot paths (abaco 2.4.9 does this in `src/dsp.cyr`:
`f64_round_half_away`, `amplitude_to_db`, `freq_to_midi`, `time_constant`, `batch_sum`, `f64_sinc`).

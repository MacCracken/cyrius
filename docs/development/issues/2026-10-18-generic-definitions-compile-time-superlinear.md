# Compile time grows ~4x per doubling of the number of generic fn definitions (1500 -> 3000 `fn oK<T>(x: T)`: 439 -> 1,972 ms), where non-generic fns are linear — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 by the 6.7.15 generics lane (unit G5) on the lane's tree at 3ad937529,
x86_64, best of 1 each (the shape is stable to ~5 %); the same scaling on the lane's earlier compilers.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.15 generics lane, wave 1; placed at its integration, 2026-10-18 — the user: what 6.7.15 files goes to repair 6) — never 7.x.
**Discovered:** 2026-10-18, 6.7.15 generics G5, building bound_forward_chain_scale.sh: the bounded chain's own
judgement is linear after the memo, but the same chain with NO bound (no judgement at all) doubled from 721 to 2,392 ms
(1500 -> 3000), so that gate measures a ratio against it instead of a doubling.
**Severity:** Low — performance only; a program with thousands of generic definitions compiles slowly (3000: ~2 s,
6000: ~8 s extrapolated).
**Kind:** compiler performance.

## Reproduction

```sh
awk -v n=1500 'BEGIN{for(i=0;i<n;i++) printf "fn o%d<T>(x: T): i64 { return 5; }\n", i; print "syscall(60, 7);"}' > g1500.cyr
awk -v n=3000 'BEGIN{for(i=0;i<n;i++) printf "fn o%d<T>(x: T): i64 { return 5; }\n", i; print "syscall(60, 7);"}' > g3000.cyr
# the same without <T> / `: T`, for the control
```

```
generic, never called     1500: 439 ms   3000: 1,972 ms   (4.5x)
non-generic control       1500:  43 ms   3000:    82 ms   (1.9x)
CYRIUS_MONOMORPH=0        1500: 441 ms   3000: 1,698 ms   (3.9x)
a forwarding chain (oK -> oK-1, no bound)   1500: 721 ms   3000: 2,392 ms
```

## Root cause

Not located. Ruled out (measured with a probe build): the stub-flag closure (`_gen_close`, src/frontend/parse_fn.cyr)
— it ran once for 1500 generics, with 1500 records (`_gen_record`); and monomorphisation (CYRIUS_MONOMORPH=0 scales the
same). Each generic definition, never called, costs time proportional to the number of generics before it: a
per-definition walk of a table that grows with the generics (a type-parameter, generic-meta or name table) is the
likely shape.

## Fix direction

Profile the 3000 case (a `perf`-less box: bisect with probe builds over the generic-definition path — `_capture_tparams`,
`_prescan_fn_sig`, `_gen_record`, the base emission in PARSE_FN_DEF); index the walk. Row: a scaling gate (generic
definitions at N and 2N under 3x, the globals_scale_linear.sh shape).

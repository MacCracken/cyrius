# Compile time is QUADRATIC in the number of globals — 70,000 exceeds two minutes — OPEN

**Status:** 🟡 open — measured during 6.6.6 (bite 19's review); identical on 6.6.5, so not a
regression from this release.
**Placement:** unpinned — 6.x line. A perf defect, not a correctness one.
**Discovered:** 2026-09-20

## Measured

Generated programs of N deferred globals (`var gN = f(N);`), same box, same compiler:

| globals | wall |
|---|---|
| 6,000 | ~0.9 s |
| 10,000 | ~2.6 s |
| 20,000 | ~11.3 s |
| 70,000 | > 120 s (timeout) |

Four-fold time for a doubling is the signature of a linear scan per registration.

## Why it matters

Generated code is the case: a table-driven consumer that emits one global per row hits this
long before it hits any documented cap (`gvar_toks` is 4,096 entries, and the var table is
1,048,576). The compiler does not say it is slow, it just takes minutes.

## Acceptance criteria

- The 20,000-global program compiles in time proportional to N, not N².
- A bench row (`benches/`) that records the shape, so the next regression is visible.
- Name the scan that was quadratic in the CHANGELOG — the fix is only trustworthy if the
  mechanism is stated.

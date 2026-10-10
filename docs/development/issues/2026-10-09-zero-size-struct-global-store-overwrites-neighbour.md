# A whole-struct store into a ZERO-size struct global writes 8 bytes over its neighbour — OPEN

**Status:** 🟡 **OPEN** — verified 2026-10-09 against the merged 6.7.7 compiler (l677-int @ 881895f6): the repro exits 0 where 77 is right (the 6.7.7 odd-size fix covers 3/5/6/7 B; width 0 still falls back to the 8-byte store).
**Placement:** 6.7.12 — Break 2, repair 3 (roadmap.md § *The releases after 6.7.7*) (the globals lane) — placed 2026-10-09 — never 7.x.
**Discovered:** the 6.7.7 odd-size-global lane (out of scope); filed 2026-10-09.
**Severity:** Low — zero-size structs are rare; silent corruption when they occur
**Affects:** cycc ≤ 6.7.7

## Reproduction

```
struct E { }
var G: E = E { };
var N1: i8 = 77;
fn run(): i64 { var l: E; G = l; return 0; }
var rr = run();
syscall(60, N1);
```
Exits 0 (want 77). `EVSTORE_W` width 0 falls back to the full store (`ESTOC` on x86).

## Proposed fix

Width 0 stores nothing — first proving no other global is registered with `_vars_base` width 0 for another reason.

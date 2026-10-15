# Under `--allow-undef`, an undefined `_str` / `_int` sibling still takes its base's call: `pr(s)` reaches the undefined `pr_str` and traps (rc 132) instead of calling the defined `pr` — OPEN (a decision) — RESOLVED

> ✅ **RESOLVED in v6.7.11** (GF-6: an overload sibling with no recorded definition never takes its base's call, the `_str` and `_int` arms alike — the user's decision (b), D8, 2026-10-13. The filed repro exits 11 with `--allow-undef` (it trapped: 132 on x86_64 / aarch64, 29 on PE) and its default build compiles and exits 11 (it was refused, 1 reachable undefined function), on x86_64, aarch64 and PE; in an `object;` unit `pr(s)` no longer binds to another object's `pr_str`. A defined sibling routes as before. Rows: `frontend/overload_arity_dispatch.sh` axis 8 (9 rows: the repro with and without the flag, the `_int` arm, return / var / assignment, `object;`, aarch64, PE). CHANGELOG [6.7.11])

**Status:** ✅ **RESOLVED in v6.7.11** (see the banner). Was: 🟡 **OPEN — a decision for the user.** Raised by the 6.7.9 quick lane (bite 20, the forward-sibling arity
fix), which kept today's behaviour because its filing asked to. Verified 2026-10-11 against the merged 6.7.9 tree
(`build/cycc` @ 27220379, 2,057,736 B): the repro builds with `--allow-undef` and exits 132 (SIGILL, the undefined
fn's trap); without `pr_str` anywhere in the source it exits 11; without `--allow-undef` the build is refused ("1
reachable undefined function"). The installed 6.7.0 and 6.7.8 compilers also exit 132.
**Placement:** 6.7.11 — repair 1, the generics / call-path lane (roadmap.md § *The releases after 6.7.8*; one line in
`_OV_ARITY_OK`, parse_fn.cyr) (the user's call, asked at that release's open) — placed 2026-10-11 — never 7.x.
**Discovered:** 2026-10-11 during 6.7.9's
[overload-router fix](2026-10-09-overload-router-forward-target-arity-unjudged.md) (its banner records this residue).
**Severity:** Low — reachable only under `--allow-undef`, where the program already calls an undefined fn somewhere.
**Affects:** cycc 6.5.1 (the arity gate's permissive arm) – 6.7.9, every target.

## Summary

The v5.10.25 overload router sends `base(s, ..)` with a Str first argument to a `<base>_str` sibling (and an
i64-returning call into a `: cstring` base to `<base>_int`). `_OV_ARITY_OK` lets a sibling with NO recorded
definition (no emitted body, pass 1's defaults row empty — GFDS 0) through unjudged, "routed as before 6.5.1, into the
undefined-function diagnostic". By default that diagnostic refuses the build, so the routing is invisible. Under
`--allow-undef` the build proceeds and the call that the source wrote to the DEFINED `pr` is sent to the undefined
`pr_str`, whose stub traps at run time.

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
include "lib/str.cyr"
fn pr(x): i64 { return 1; }
fn other(): i64 { return pr_str(0); }    # pr_str is named, never defined
fn main(): i64 { alloc_init(); var s: Str = str_from("ab"); return pr(s) * 10 + pr(5); }
syscall(60, main());
```

```sh
cat repro.cyr | build/cycc --allow-undef > /tmp/ov && chmod +x /tmp/ov && /tmp/ov; echo $?   # 132
# with the `other` line deleted: 11 (pr(s) calls pr)
```

## The decision

- **(a) Keep it (today):** an undefined sibling takes the call; `--allow-undef` builds trap there.
- **(b) An undefined sibling never takes the call** (the lane's recommendation): delete `_OV_ARITY_OK`'s permissive
  arm for a target with no definition (`if (L64(_fnt_offsets + fi * 8) < 0) { if (GFDS(S, fi) == 0) { return 1; } }`
  → `return 0` for that case), so `pr(s)` calls `pr` (exit 11). A default build changes in one shape, the repro's: an
  undefined sibling named only in unreachable code is made reachable by the routed call today, so the build is
  refused ("1 reachable undefined function"); under (b) it builds and calls `pr`.

(b) changes what an `--allow-undef` program computes (a trap becomes the base's value) and lets the repro's default
build through. Rows for either answer: axis 7
of `tests/gates/frontend/overload_arity_dispatch.sh` gains the repro with and without `--allow-undef`, and the `_int`
arm.

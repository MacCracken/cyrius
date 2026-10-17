# In a closure, a write to a captured name with a same-named GLOBAL compiles silently and writes the global — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-16 on the 6.7.13 receives lane tree (`l6713-receives` @ `360a6d05`), x86_64,
and on the installed 6.7.2, 6.7.5, 6.7.9 and 6.7.12 compilers: identical everywhere (6.6.0 cannot build the probe: the
tree's lib/ uses `const`).
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (receives + multi-value lane, wave 2, unit R1; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Discovered:** 2026-10-14 by the 6.7.13 receives-lane triage of
`issues/archived/2026-10-14-captured-name-refusal-fixit-reads-var-y-equals-y.md` ("met in passing, not filed"); filed 2026-10-16
by unit R4 after re-measuring it.
**Severity:** High — a silent wrong value: source the 6.7.11 rule refuses ("a captured name is not assignable in a
closure") compiles when a global has the name, and the store goes to the global while reads in the same body see the
capture.
**Affects:** every target (the shared frontend's assignment arms).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/alloc.cyr"
var y = 100;
fn main(): i64 {
    alloc_init();
    var y = 5;
    var f = |d| { y += d; return y; };
    var r = callptr(f, 2);
    var s = "";
    return r;
}
fn g(): i64 { return y; }
var r = main();
syscall(60, r * 10 + (g() - 100));
```

```
$ build/cycc < gy2.cyr > gy2 && ./gy2; echo $?
52
```

The closure returns 5 (its read of `y` is the capture) and the global goes 100 -> 102 (`g() - 100` = 2): 5 * 10 + 2.
With `y = y + d;` in place of `y += d;` it exits 213: the right-hand side reads the CAPTURE (5) and the store writes
5 + 2 into the GLOBAL, which goes 100 -> 7 (5 * 10 + (7 - 100) = -43, 213 as an exit code).
Without `var y = 100;` the same closure is refused, as the rule says:

```
error:<source>:6:25: 'y' is captured by value; a captured name is not assignable in a closure — copy it into a local (`var y_l = y;`)
```

Expected: refused with that error whether or not a global `y` exists: inside the closure `y` names the capture (the read
finds it first), so the write is a write to a captured name.

## Root cause

Every write arm resolves the destination as local, then GLOBAL, and only when both miss asks whether the name is a
capture: `_asg_capture_refused` (src/frontend/parse.cyr, `if (FINDVAR(S, noff) >= 0) { return 0; }` before
`_cl_snap_find`), the statement arm's `idx = FINDVAR(S, noff)` before `_asg_undef_report` -> `_asg_cap_name`, and
`_masg_resolve`'s `FINDVAR` before its `_asg_cap_name`. The read path (PARSE_FACTOR) checks the closure's captures
before globals, so the read and the write of the same name in the same body resolve to different variables. The same
order presumably governs a compound assignment, a classic-`for` init / step and `a, y = f()` (the paths
`closure_capture_name_write_named.sh` W1-W8 cover without a global); only the `y += d` and `y = y + d` shapes were measured.

## Proposed fix

In a closure body (`_cl_snap_find(S, noff) >= 0`, i.e. the name is an enclosing local the closure sees), take the
capture refusal before the global lookup in each write arm, so a same-named global never becomes the destination. Rows:
the repro above refused once (no binary); each W shape of `closure_capture_name_write_named.sh` with a same-named global;
a control where the closure does NOT see an enclosing `y` (the global write stays legal and lands in the global).

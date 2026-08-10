# A capturing closure SIGSEGVs when passed through another function — ✅ FIXED

**Status:** ✅ **FIXED** (6.5.17). All four filed programs and the captured-pointer
variant exit 42 on x86_64, aarch64 (qemu) and Windows PE (wine).

**Resolution.** The trigger was NOT "crossing a function boundary" — that was one of
eleven shapes. "Is this callee a closure?" was decided at COMPILE time from the
declaring local's `CLOSURE_TYID` SLTYPE, so the answer was lost the instant the value
moved: through a parameter, a return, a global, `store64`/`load64`, or a plain
`g = f` assignment. Minimisation reproduced the SIGSEGV with no function boundary at
all (`fn main(): i64 { var b = 41; var f = |x| b + x; return fncall1(f, 1); }`).

v6.5.17 moved the decision to RUN time: a capturing closure's value is its heap
environment object with bit 63 set, every indirect call site normalizes it
(`ECLTAG`/`ECLENV`/`ECLNORM` per backend), and the environment is passed as a hidden
TRAILING argument so one marshalling sequence serves closures and plain function
pointers alike. `fncallN` is lowered by the compiler to the same sequence — it could
not be fixed inside `lib/fnptr.cyr`, because the ladder shape needs a 7-argument call
and cybs caps at 6. `CLOSURE_TYID` is retired, which also fixes the pointer-scale leak
that made `(f + 1) - f` evaluate to 1,073,741,827.

⚠ The environment rides an argument REGISTER or not at all — under SysV a trailing
stack argument slides an ordinary callee's stack arguments. A capturing closure
therefore caps at 5 parameters (3 on Win64) and declaring more is now a compile error.

Gate: `tests/tcyr/crossos/closure_escape_dispatch.tcyr` (20 assertions), mutation-proven.
Full detail in `CHANGELOG.md`.

---

**Original filing follows.**

**Status:** 🔴 OPEN — compiles clean, dies at runtime. No diagnostic.
**Placement:** unpinned — 6.5.x line. Silent crash on a documented language feature, so it wants a
patch release rather than the backlog.
**Discovered:** 2026-08-10 from hisab, while checking a four-file claim that "Cyrius has no closures"
— which is false, and had never been run.
**Severity:** **High** — silent SIGSEGV on a feature the guide documents (§Closures, capture by
value, v6.3.8). A hard compile error would be strictly better than the current behaviour.
**Affects:** cycc **6.5.16** (confirmed). Not bisected against earlier pins.

## Summary

A capturing closure works when called in the function that built it. Pass the same closure to
another function and call it there, and the process segfaults. A **non**-capturing closure passed
the same way is fine, so the variable is capture-across-a-call-boundary.

## Reproduction

Four programs, `[deps] stdlib = ["syscalls", "io", "alloc", "math"]`, built with
`cyrius build src/t.cyr build/t` on 6.5.16. Each is otherwise identical.

```
# 1. non-capturing, passed through a fn      -> exit 42   OK
fn takes(f): i64 { return callptr(f, 1); }
fn main(): i64 { var f = |x| 41 + x; return takes(f); }

# 2. capturing, called inline                -> exit 42   OK
fn main(): i64 { var base = 41; var f = |x| base + x; return callptr(f, 1); }

# 3. capturing, passed through a fn          -> SIGSEGV (139)
fn takes(f): i64 { return callptr(f, 1); }
fn main(): i64 { var base = 41; var f = |x| base + x; return takes(f); }

# 4. same as 3 but fncall1 instead of callptr -> SIGSEGV (139)
fn takes(f): i64 { return fncall1(f, 1); }
fn main(): i64 { var base = 41; var f = |x| base + x; return takes(f); }
```

1 and 2 are the controls: each isolates one half of the failing case and both pass. 3 and 4 differ
from 2 only by crossing a function boundary, and from 1 only by capturing.

Also confirmed with a captured **pointer** (`var pts = alloc(32); var f = |i| load64(pts + i * 8);`):
called inline it returns the right element; passed through a function it segfaults.

## Root cause (speculation — flagged as such)

The guide says a capturing closure "*is*" its heap environment object `[fn_ptr, cap0, …]`, and that
`callptr` "auto-detects a captured closure and dispatches it (loads the fn pointer from the object
and passes the object itself as the hidden first argument)". The controls suggest that detection
works on the value while it is still the local the closure was assigned to, and stops working once
that value has been passed as an ordinary parameter — i.e. the callee sees the environment pointer
but dispatches it as a bare function pointer, jumping to whatever `cap0` happens to be. That the
crash is identical under `fncall1` points at the shared dispatch rather than at `callptr`.

**Not verified** — a consumer-side reading of the observable behaviour, not of the codegen.

## Proposed fix

None offered; this needs someone who knows the lowering. The useful constraint from out here is
that whatever makes `callptr` work at the definition site has to survive the value being copied
into a parameter slot — or the copy has to be rejected at compile time instead of crashing at run
time. A hard error would be far better than a segfault.

## Consumer-side workaround

Do not pass capturing closures across a function boundary. Either call them where they are built,
or hoist the captured state into a file-scope global and use a non-capturing closure.

## How this was found, and why it matters beyond the bug

hisab's own records asserted **"Cyrius has no closures"** in four places
(`dependency-watch.md`, `roadmap.md`, `src/collision_core.cyr`, and two CHANGELOG entries), and used
it as the stated reason for not adopting stdlib `vec_sort_by`. **That claim is false and had never
been run** — closures have existed since v6.3.8. The claim was inherited, repeated, and propagated.

Checking it turned up this defect. So the conclusion those files reached (don't adopt `vec_sort_by`
yet) happens to be right, but for a completely different reason than the one recorded — and it is
now recorded as a measurement with a repro instead of as a belief.


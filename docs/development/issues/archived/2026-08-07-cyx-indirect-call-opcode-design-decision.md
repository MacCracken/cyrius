# `.cyx` needs a PERMANENT indirect-call opcode — maintainer design decision

> ✅ **RESOLVED v6.5.13.** Opcode **105 (0x69)** minted and shipped — permanent, per the
> `.cyx` opcode-stability rule. The decision this file asked for was made and implemented;
> the radix-blind duplicate-opcode check in `tests/gates/codegen/cx_indirect_call.sh` axis 4
> guards against re-minting a number already in use (the decimal-only scan that missed the
> hex arms is exactly the mistake it exists to prevent).


**Filed:** 2026-08-07
**Reporter:** cyrius (raised out of the v6.5.11 catch-up triage)
**Cyrius version:** 6.5.11
**Affects:** `src/backend/cx/emit.cyr:408` (`ECALLIND`), `programs/cxvm.cyr` (interpreter), `lib/fnptr.cyr`
**Status:** 🔴 **BLOCKED ON A DESIGN DECISION — the maintainer's, not schedulable without it.**
**Pinned:** **next release** (post-6.5.11), as agreed 2026-08-07.
**Supersedes the fix half of:** `2026-07-30-cx-backend-has-no-indirect-call` (which stays open as the
bug record; see the two corrections below, both of which belong in that file).

## Why this is a decision and not a task

`.cyx` is a **shipped bytecode format with a versioned header**. An opcode number, once assigned, is
permanent in exactly the way binary names are permanent under CLAUDE.md's *"Version lives in VERSION
+ --version, never in binary names"* rule: every `.cyx` ever produced encodes it, and `cxvm` must
honour it forever. Picking the number, the operand encoding, and the calling convention is therefore
a one-way door, and it is the maintainer's call — which is the whole reason this is filed rather
than fixed.

## Current state (verified live at v6.5.11)

`src/backend/cx/emit.cyr:408`:

```
fn ECALLIND(S, idx): i64 {
    syscall(SYS_WRITE, 2, "error: callptr (indirect call) is not supported on the cx backend\n", 66);
    syscall(SYS_EXIT, 1);
    return 0;
}
```

⚠ **It HARD-ERRORS. It is not silently dead.** Both `2026-07-30-cx-backend-has-no-indirect-call` and
`roadmap.md:865` describe every fn-pointer stdlib path as dead on cx *"silently"*. That is wrong and
it changes the severity argument: a program that reaches `callptr` on cx fails loudly at COMPILE
time with the message above. It is invisible only when DCE drops the path as unreachable, i.e. when
the program never actually calls through the pointer.

## Opcode-space facts, for the decision

Measured from `programs/cxvm.cyr` at v6.5.11:

| | |
|---|---|
| opcodes in use | **54** |
| highest in the normal band | **129** |
| high/reserved band in use | **253, 254, 255** (253 = `movhk`, the v6.4.58 64-bit-immediate op) |
| free gaps in the low band | `3–15`, `21–31`, `38–47`, … |

So there is ample room; the choice is about *where* it belongs semantically, not about scarcity.

## What has to be decided

1. **Opcode number.** A low-band gap (e.g. `16`) groups it with the call family; a high-band number
   groups it with the v6.4.58 extension ops. Permanent either way.
2. **Operand encoding.** `.cyx` is `[opcode:8][a:8][b:8][c:8]` fixed-width. An indirect call needs a
   register holding the target — does it reuse `ECALLPOPS`' r3–r8 argument convention and take the
   target in `a`, or does it need a distinct shape?
3. **Target representation.** Native `callptr` targets a machine address. In `.cyx` there is no
   machine address — the callee must be a **function index** into the bytecode's own table. That is
   a semantic difference from every other backend, not just an encoding one, and it decides whether
   cx can ever host a fn pointer that came from outside the module.
4. **What happens to `callptr`-to-native.** The current comment says *"callptr targets native
   COM/DXGI; it is not expressible in cx."* If that stays true, the opcode covers only
   cyrius-internal fn pointers and `callptr`-to-native must keep hard-erroring — which is a
   legitimate outcome, but it should be stated rather than discovered.

## Blast radius

The whole allocator/callback layer. `lib/fnptr.cyr` is the substrate for `vec_sort_by`,
`vec_select_nth` and the `Allocator` vtable — and both v6.5.9's growable arena and v6.5.10's
`alloc_via` rework sit squarely in it. Any cx consumer using a custom allocator or a comparator
today hits the hard error.

## Acceptance, when it is scheduled

- The opcode emitted by `ECALLIND` and decoded by `cxvm` round-trips a `vec_sort_by` with a
  user comparator.
- Verified on **all four hosts** (the cx harness runs under `cxvm`, so a cx exit-code test lives in
  the cx harness, **not** in `tests/tcyr/` — see the v6.4.58 note).
- The `.cyx` version header is bumped if the format gains an opcode, so an old `cxvm` refuses a
  new `.cyx` rather than misreading it.

---

## Two corrections owed to `2026-07-30-cx-backend-has-no-indirect-call`

Found while premise-checking that file for this batch; both should be applied to it.

**1. Its headline repro is INVALID.** The file reports `run=124` (timeout) as evidence of a hang.
`programs/cxvm.cyr` takes **no argv** — `grep -c 'argv(' programs/cxvm.cyr` → **0**, and its own
usage line at `:2` reads `echo 'bytecode' | ./cxvm` / `cat prog.cyx | ./cxvm`. Invoking
`cxvm /tmp/x.cyx` therefore blocks reading stdin from the terminal until the timeout fires. Every
`run=124` in that file, **including its 2026-08-07 re-verification**, is that — not a hang in the
generated code. The bug it describes is real; the evidence for it is not.

**2. A separate, smaller cx defect turned up alongside it and needs its own file:** calling an
**undefined function** on cx silently restarts the program at offset 0 instead of faulting — a probe
printed its "before" marker ~700 times and never reached "after". That is a control-flow bug
independent of indirect call (it needs a hard error or a trap opcode) and should not ride on this
decision.

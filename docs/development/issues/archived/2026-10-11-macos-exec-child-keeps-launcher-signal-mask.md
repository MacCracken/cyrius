# On macOS an exec-family child still inherits a signal mask its parent inherited from a launcher — RESOLVED

> ✅ **RESOLVED in v6.7.12** (DW-5: `sys_sigprocmask` works on both Macs (the user's decision D3, 2026-10-15: a public shim) and is per-thread, as on Linux. It is Darwin's `__pthread_sigmask` (329) through the private alias 1329, routed on both Mach-O backends. Darwin reads the 32-bit set from the low half, and the shim zeroes `oldset`'s upper word. The user chose 329 on 2026-10-15 over the process-wide sigprocmask (48) the lane first routed, before any release shipped 48. `_proc_child_signals`' mask reset now runs on macOS. In the filed launcher repro, `sleep 3` now ends at SIGINT: ach 3.10 → 0.67 s and ecb 3.07 → 0.66 s, measured on the first route. On 329, every exec-family child reports an empty mask (exec_child_signal_state 21/21 on ach and ecb), and a second thread's mask stays 0 when the main thread blocks a signal. Rows: `crossos/sigprocmask_every_target.tcyr` (round-trip, upper word 0, a second thread unchanged), `crossos/exec_child_signal_state.tcyr` (the macOS mask rows) and `macho_route_parity.sh` axis 2b (the Darwin alias band on both backends). CHANGELOG [6.7.12])

**Status:** ✅ **RESOLVED in v6.7.12** (see the banner). Was: 🟡 **OPEN** — found 2026-10-11 by reading the code while fixing the exec-family signal reset (6.7.9, the
critical lane's bite 3). Not reproduced on hardware: the mask half of that fix is `#ifdef CYRIUS_TARGET_LINUX`, and
`sys_sigprocmask` declines on macOS (-78), so nothing in `lib/` can empty the mask there.
**Placement:** 6.7.12 — repair 2: the platform release (darwin lane; re-placed at the 6.7.12 open, 2026-10-15) — never 7.x.
**Decision (user, 2026-10-15, at the 6.7.12 open):** D3 — a public shim (sys_sigprocmask works on macOS).
**Discovered:** 2026-10-11 during 6.7.9's fix of
[`2026-10-09-exec-family-child-inherits-signal-mask-and-ignores.md`](2026-10-09-exec-family-child-inherits-signal-mask-and-ignores.md).
**Severity:** Low — it needs a launcher that blocks a signal before it starts a Cyrius program on macOS.
**Affects:** `lib/process.cyr` on macOS (x86_64 and arm64), every version through 6.7.9.

## Summary

6.7.9 makes every child the exec family starts (`run`, `run_capture`, `spawn`, `exec_*`, `exec_cmd`) begin with an
empty signal mask and SIGPIPE / SIGXFSZ at SIG_DFL (`_proc_child_signals`). The disposition half runs on Linux and
macOS. The mask half runs only on Linux: the macOS floor declines sigprocmask (6.6.5 — `sys_sigprocmask` returns -78).
A Cyrius program on macOS cannot block a signal itself, so it never adds to the mask. But a mask it INHERITED survives
execve (POSIX), so a launcher that blocks, say, SIGINT before it starts a Cyrius program hands that mask on through the
program to every child the exec family starts, which then cannot be interrupted by it.

## Reproduction

Needs a macOS host (ecb / ach). A launcher blocks SIGINT and execs a Cyrius program that runs a child through the exec
family. The child should have an empty mask; by the code it keeps SIGINT blocked:

```sh
# on ecb: the launcher blocks SIGINT, then execs the Cyrius program
python3 -c 'import os, signal; signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGINT}); os.execv("./prog", ["./prog"])'
# prog: exec_vec(["/bin/sh", "-c", "sleep 3"]) — then `kill -INT <sleep's pid>` from another shell.
# Expected (fixed): sleep ends at once. Actual (by the code): sleep runs its full 3 s.
```

## Root cause

`lib/process.cyr` `_proc_child_signals`: the `sys_sigprocmask(SIG_SETMASK, &empty, 0)` line sits under
`#ifdef CYRIUS_TARGET_LINUX`. On macOS there is no route to Darwin's `sigprocmask` (BSD syscall 48), deliberately:
`tests/gates/platform/macho_route_parity.sh` lists `SYS_RT_SIGPROCMASK` under "a real Darwin call exists but a bare
renumber would be WRONG" — Linux's call takes a 4th sigsetsize argument and a 64-bit sigset, Darwin's a 32-bit one, so
it "needs a shim, not a row". `lib/syscalls_linux_common.cyr`'s `sys_sigprocmask` returns -78 there.

## Proposed fix

The shim the parity gate asks for: a Mach-O route to Darwin's sigprocmask (48) behind a `sys_sigprocmask` macOS arm
that narrows the 64-bit set to Darwin's 32 bits on the way in and widens `oldset` on the way out (Darwin's `how` is
already 1 / 2 / 3 in the macOS `SigAction` enum); the parity gate's row moved from "needs a shim" to routed; and the
`#ifdef CYRIUS_TARGET_LINUX` taken off the mask reset in `_proc_child_signals`. ⚠ This changes what `sys_sigprocmask`
does on macOS (-78 → a working call), which is the user's call. Verify on ecb and ach:
`tests/tcyr/crossos/exec_child_signal_state.tcyr` gains a macOS mask row once the parent can block.

## Consumer-side workaround

None inside Cyrius on macOS. The launcher can unblock the signal before it starts the program.

# PE `sys_dup2` is a stub that answers `newfd` for every call: a closed fd's self-dup answers 99 where every POSIX target answers -9 (EBADF), and a redirect `sys_dup2(1, 50)` answers 50 with no fd 50 behind it — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 libfix lane (branch l6715-libfix, unit L1) with the lane's
`build/cycc_win_cross`, under wine and on real cass (Windows 11, `C:\cyrius-tests`).
**Placement:** 6.7.15 — repair 5 (libfix lane, wave 3, unit L3; placed at the wave-2 integration, 2026-10-18: a lib/ defect is always fixed) — never 7.x.
**Severity:** Low — a defect in lib/ (the stdlib answers differently per target for the same call, and a failed
redirect reads as a success). A portable `if (sys_dup2(a, b) < 0)` never sees the failure on Windows. In-tree callers
that redirect (lib/process.cyr, lib/regression.cyr, lib/pam.cyr) sit on POSIX-only paths or are already guarded
(`fl_poison_underwrite_classified.tcyr`, `flags.tcyr` skip their captures on PE). No boundary is crossed.
**Found:** in passing, pinning Windows' answer in `tests/tcyr/crossos/sys_dup2_same_fd.tcyr` (the 6.7.15 L1 row for
issues/2026-10-18-aarch64-sys-dup2-same-fd-answers-einval.md, which pins today's PE answer and does not change it).

## Reproduction

```cyr
include "lib/syscalls.cyr"
var r = sys_dup2(99, 99);
if (r < 0) { syscall(60, 100 - r); }
syscall(60, r);
```

```cyr
include "lib/syscalls.cyr"
var d = sys_dup2(1, 50);
var w = syscall(1, 50, "x\n", 2);
if (d != 50) { syscall(60, 3); }
if (w < 0) { syscall(60, 100 - w); }
syscall(60, w);
```

```text
                                   closed-fd self-dup        redirect, then write to fd 50
x86_64 Linux (build/cycc)          exit 109  (-9, EBADF)     prints "x", exit 2
PE (cycc_win_cross), wine          exit 99   (newfd)         exit 109  (dup2 said 50; the write: -9)
PE (cycc_win_cross), real cass     exit 99                   exit 109
```

## Root cause

lib/syscalls_windows.cyr:

```cyr
# Best-effort dup2 stub: returns the requested newfd (handle dup is rerouted).
fn sys_dup2(oldfd, newfd): i64 { return newfd; }
```

It issues nothing and answers `newfd`, i.e. success, whatever `oldfd` is. The comment's "handle dup is rerouted" is
not true of the tree: src/backend/pe/ has no route for dup2 (33) or DuplicateHandle / SetStdHandle. Every other PE
stub of this family fails closed — `sys_pipe` -1 (6.6.9), `sys_fork` -1, `sys_kill` -1, `sys_fcntl` -38 — and the cx
host dispatch already answers a guest's dup2 on a Windows host -38 for exactly this reason (programs/cxvm.cyr
`_cx_host_posix`: "dup2 the fd it was asked for").

## Fix direction

Either fail closed like its neighbours (-38, or -1 as `sys_pipe` / `sys_fork` do — the choice of value is the user's,
since it changes what a Windows program reads), or implement the std-handle cases (`newfd` 0 / 1 / 2 through
`SetStdHandle` on a `DuplicateHandle` of `oldfd`'s handle) and fail the rest. Either way the stale "handle dup is
rerouted" comment goes. Row: the pinned Windows group of tests/tcyr/crossos/sys_dup2_same_fd.tcyr moves to the
decided answer on cass.

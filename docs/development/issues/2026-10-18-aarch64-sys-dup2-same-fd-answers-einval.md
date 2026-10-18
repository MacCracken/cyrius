# aarch64 Linux `sys_dup2(fd, fd)` answers -22 (EINVAL) where x86_64 answers fd: the aarch64 peer issues dup3(old, new, 0), which refuses old == new — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 platform lane (branch l6715-platform, unit P4) with the
lane's x86_64 cycc and aarch64 cross compiler, under qemu-aarch64 and on real pi.
**Placement:** 6.7.15 — repair 5 (libfix lane, wave 2, unit L1; placed at the wave-1 integration, 2026-10-18: a lib/ defect is always fixed) — never 7.x.
**Severity:** Low — a defect in lib/ (the stdlib answers differently per target for the same call). POSIX dup2 with
equal descriptors returns the descriptor when it is open (and -EBADF when not); a portable `if (sys_dup2(a, b) < 0)`
reads a failure on aarch64 where x86_64 and macOS succeed. In-tree callers pass distinct fds today (not surveyed
beyond that). No boundary is crossed.
**Found:** in passing, reading the aarch64 peer while the cxvm host dispatch began serving a guest's dup2 through
`sys_dup2` (issues/2026-10-17-cxvm-forwards-guest-x86-numbers-through-host-renumbering.md): a cx guest's
`dup2(1, 1)` now answers 1 on the x86_64 cxvm and -22 on an aarch64 one, as native programs do.

## Reproduction

```cyr
include "lib/syscalls.cyr"
var r = sys_dup2(1, 1);
if (r < 0) { syscall(60, 100 - r); }
syscall(60, r);
```

```text
x86_64 Linux (build/cycc)                    exit 1
aarch64 (cycc_aarch64), qemu-aarch64         exit 122   (-22)
aarch64 (cycc_aarch64), real pi              exit 122   (-22)
```

## Root cause

lib/syscalls_aarch64_linux.cyr `sys_dup2` issues `syscall(SYS_DUP3, oldfd, newfd, 0)` on Linux (aarch64 has no dup2
syscall), and dup3(2) refuses `oldfd == newfd` with EINVAL by design — the one case where dup3 is not dup2 with flags.

## Fix direction

In the aarch64 peer's Linux arm: when `oldfd == newfd`, answer `oldfd` if it is open (e.g. `fcntl(oldfd, F_GETFD)`
>= 0) and -EBADF otherwise, as glibc's dup2 does on aarch64; else dup3 as now. Row: the repro exits 1 on aarch64
(qemu and pi), and a closed fd (`sys_dup2(99, 99)`) answers -9 on every target.

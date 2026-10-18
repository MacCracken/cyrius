# cxvm on macOS passes a guest's x86-Linux signal number to kill unmapped: SIGUSR1 10 is Darwin's SIGBUS, SIGCHLD 17 its SIGSTOP, SIGSTOP 19 its SIGCONT — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 platform lane (branch l6715-platform, after 0771db778),
cxvm built from the lane's tree for each host: x86_64 Linux (`build/cycc`), ecb (`CYRIUS_MACHO_ARM=1 cycc_aarch64`
+ `codesign -s -`), ach (`CYRIUS_MACHO=1 cycc`).
**Placement:** unplaced — filed from the 6.7.15 platform review (wave 1; filed at its integration, 2026-10-18); the user places what 6.7.15 files — never 7.x.
**Severity:** Medium — a portable cx program's `kill(pid, SIGCHLD)` STOPS the target on a Mac's cxvm and
`kill(pid, SIGSTOP)` continues it; `kill(pid, SIGUSR1)` delivers SIGBUS. No boundary is crossed (cxvm runs trusted
bytecode, and a guest can already signal anything cxvm's user can; no ledger id).
**Found:** the 6.7.15 platform lane's review, reading `_cx_host_posix` after the host-dispatch fix
(issues/2026-10-17-cxvm-forwards-guest-x86-numbers-through-host-renumbering.md), whose filed surface was
`kill(getpid(), 0)` only. Related, not the same: 2026-10-18-cxvm-darwin-errnos-reach-the-guest-unmapped.md (the
errno values, staged beside this; it names the signal class as "not measured").

## Reproduction

`sig.cyr`, compiled once with `cycc_cx` (`cycc_cx < sig.cyr > sig.cyx`, no diagnostic), the `.cyx` run on each
host's cxvm as `sh -c "./cxvm < sig.cyx; echo \$? > sig.rc"`:

```cyr
# kill(getpid(), 10): x86_64 Linux's SIGUSR1 (default action: terminate).
var p = syscall(39);
syscall(62, p, 10);
syscall(60, 0);
```

```text
x86_64 Linux cxvm  status=138 (USR1)
ecb cxvm           sh: line 1: 62338 Bus error: 10   ./cxvm < sig.cyx
                   status=138 (BUS)
ach cxvm           sh: line 1: 80571 Bus error: 10   ./cxvm < sig.cyx
                   status=138 (BUS)
ecb native `sh -c 'kill -USR1 $$'`  status=158 (USR1)   # Darwin's SIGUSR1 is 30
```

## Root cause

programs/cxvm.cyr `_cx_host_posix`: `if (sn == 62) { return sys_kill(a, b); }` — `b` is the guest's signal, spelled
from the x86_64-Linux peer's `Signal` enum (lib/syscalls_x86_64_linux.cyr: SIGUSR1 10, SIGUSR2 12, SIGCHLD 17,
SIGCONT 18, SIGSTOP 19). The Darwin values (lib/syscalls_macos.cyr and lib/syscalls_aarch64_linux.cyr's
`CYRIUS_TARGET_MACOS` Signal enum) are 30, 31, 20, 19, 17; that header explains ESYSXLAT renumbers syscall NUMBERS,
never argument values, and the 6.7.15 host dispatch maps `open`'s and `fcntl`'s flag bits but not a signal.
The portable ones (SIGHUP 1, SIGINT 2, SIGKILL 9, SIGTERM 15 …) agree, which hides it for most programs.

## Fix direction

Map the guest's Linux signal number to the host's in `_cx_host_posix` (a Linux -> host table, identity on Linux
hosts; a Linux signal Darwin lacks — SIGPWR, SIGSTKFLT, the realtime band — answers -EINVAL, as Darwin's kill does
for an unknown one). Rows: the repro above ends `USR1` (status 158) on ecb and ach; a fixture row in
tests/fixtures/cx_host_dispatch.cyr that sends SIGCHLD to a forked child and sees it still running (SIGCHLD's default
action is ignore), run by the cross-OS legs.

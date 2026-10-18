# cxvm hands the guest's x86-Linux syscall numbers to the host's `syscall()`, whose renumbering is built for the host stdlib's own numbers — on aarch64 Linux a guest `lseek` runs `getxattr` and a guest `fork` runs `close` (the parent takes the child branch), on arm64 macOS `kill` runs `lseek`, and several of D55's scalar-only calls SIGSYS-kill cxvm on the Macs — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-17 on the 6.7.14 stdlib lane (l6714-stdlib, unit L3), on pi, ecb, ach and
cass, with cxvm built from the lane's tree at HEAD (before D55) and after D55 (identical answers for every call below:
this is the pass-through path D55 keeps, not something D55 changed).
**Placement:** 6.7.15 — repair 5 (platform lane, wave 1, unit P4; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Severity:** Medium — a silent wrong call: on an aarch64 Linux host the guest's `lseek` (one of cxvm's own TRANSLATED
calls, dispatched explicitly in op 0x70) runs a different kernel syscall and answers -EFAULT, `kill(pid, 0)` runs
`lseek`, `exit_group(77)` exits 0; on arm64 macOS `kill` runs `lseek`. No diagnostic. cxvm runs trusted bytecode (no
boundary crossed, no ledger id). Found in passing while landing D55; a cxvm dispatch redesign, not a bite of D55's
filed surface (which is the refusal of untranslated numbers), so filed.

## Reproduction

Each probe is `var r = <call>; if (r < 0) { syscall(60, 200 + (0 - r) % 50); } syscall(60, r % 200);`, compiled once
with `cycc_cx` (a `.cyx` is portable), run on each host's own cxvm (built from programs/cxvm.cyr: `cycc_aarch64` for pi,
`CYRIUS_MACHO_ARM=1 cycc_aarch64` + `codesign -s -` for ecb, `CYRIUS_MACHO=1 cycc` for ach, `cycc_win_cross` for cass).
Exit 209 = -9 (EBADF), 214 = -14, 222 = -22, 140 = SIGSYS, 238 = -38.

```text
call (guest x86 number)        x86_64 Linux   pi (aarch64)        ecb (arm64 macOS)   ach (x86 macOS)   cass
getpid()            39         pid            pid                 pid                 pid               -38
getppid()           110        ppid           222 (-22)           140 SIGSYS          ppid              -38
close(-1)           3          209            209                 209                 209               1 (*)
kill(getpid(), 0)   62         0              209 (-9: lseek)     209 (-9: lseek)     0                 -38
dup(-1)             32         209            222                 140 SIGSYS          209               -38
fcntl(1, F_GETFL)   72         169            73                  137                 1                 -38
lseek(-1, 0, 0)     8          209            214 (-14)           140 SIGSYS          209               209
getuid()            102        uid            214 (-14)           140 SIGSYS          uid               -38
sched_yield()       24         0              222                 140 SIGSYS          140 SIGSYS        -38
epoll_create1(0)    291        3              214                 140 SIGSYS          140 SIGSYS        -38
exit_group(77)      231        77             0                   140 SIGSYS          77                -38
open("p", O_RDWR|O_CREAT=66)   3              3                   202 (-2)            202 (-2)          16
fork()              57         child pid      0 (runs close)      0 (runs close)      child pid         -38
```

The fork row is the worst: x86 57 is `close` on aarch64 (Linux 57, and the arm64-macOS chain's aarch64-Linux
`close 57 → 6` row), so the guest's fork answers 0 in the PARENT, which then runs the child branch.
`tests/tcyr/crossos/audit_walk_fifo.tcyr` on cx shows it: once 6.7.14's guest-brk heap lets it past alloc, it ends
`0 passed, 8 failed` on x86_64 Linux / ach and `1 passed, 7 failed` on Windows, but exits 10 mid-file with no summary
on pi and ecb (the "parent" runs the forked walker's exit). Probe: `var r = syscall(57); if (r == 0) { syscall(60, 50); }
… syscall(60, 1);` exits 50 on pi and ecb, 1 on x86_64 Linux and ach.

(*) `close` on Windows answers CloseHandle's BOOL — already staged as
`platform/2026-10-16-pe-close-returns-closehandle-bool.md`. On Windows every other pass-through number answers -38
(the argc-6 dynamic path has no PE route), before and after D55.

## Root cause

programs/cxvm.cyr op 0x70 issues the guest's number with `syscall(sn, …)`, a RUNTIME number. Each host's compiler
renumbers a runtime number through a chain built for that host's OWN stdlib numbering:
- aarch64 Linux: `ESYSXLAT`'s Linux arm (src/backend/aarch64/emit.cyr, after the Mach-O branch) maps only a hand list
  of x86 numbers (0, 1, 2, 3, 12, 60, 228, 9, 10, 11, 39, 22, the socket band, …). 8 (lseek), 24, 32, 62, 102, 110, 231,
  291 pass through unmapped and run the aarch64 syscall that has that number (8 = getxattr, 32 = flock, 62 = lseek).
- arm64 macOS: the Mach-O branch maps aarch64-LINUX numbers (the stdlib peer arm64 macOS uses) as well as some x86
  ones, so x86 `kill` 62 matches the aarch64 `lseek` 62 → BSD 199 row; unmatched numbers fault with the chain head's
  0xFFFF (SIGSYS) — by design for a native program, fatal for cxvm.
- both Macs: `open`'s FLAGS are the guest's Linux values (O_CREAT 0x40), which Darwin reads as another flag.
cxvm already routes getrandom and clock_gettime through the HOST's stdlib wrappers for exactly this reason (v6.6.8:
"the host's raw syscall does not keep the guest's Linux contract on every host"); lseek, open's flags and the D55
scalar list never got the same treatment.

## Fix direction

Serve each translated and scalar-listed call through the host's stdlib wrapper (`sys_lseek`, `sys_getppid`, `sys_kill`,
`sys_dup`, `sys_fsync`, `sys_fcntl`, `sys_flock`, `sys_getuid`, …, and `open` with the Linux flags mapped to the
host's), as `_cx_host_getrandom` / `_cx_host_clock_gettime` do, or answer -38 on a host where the call has no wrapper.
Rows: the table above gives the x86_64 Linux column on pi, ecb and ach (cass: the PE routes or -38), in a cx gate run on
the hosts (scripts/cross-os-selfhost.sh's cx fixture is the place: it runs only `write` today).

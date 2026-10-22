# On a macOS host cxvm hands the cx guest Darwin's errno values: `open(link, O_RDONLY|O_NOFOLLOW)` answers -62 (Darwin's ELOOP) where the .cyx ABI (x86_64 Linux) and every other host say -40 — RESOLVED

> ✅ **RESOLVED in v6.7.16** (PL-4, `e659a21dc` — no decision needed: the `.cyx` ABI is x86_64 Linux's. Every answer of cxvm's host dispatch leaves through `_cx_errno_linux`, which on a macOS host maps [-4095, -1] through a Darwin → Linux table by name (EDEADLK 11 → 35, ELOOP 62 → 40, ENOTEMPTY 66 → 39, ENOSYS 78 → 38, …; each Darwin-only errno at the nearest Linux code); cxvm's own refusals there are spelled `_cx_host_enosys()`, so a -38 never comes out -88. The filed repro (`eloop.cyr`) exits 40 on ecb and ach (it exited 62), as on x86_64 Linux and pi; `open_flags_per_target` reads 44 / 44 on each Mac's cxvm in the cx crossos leg (PL-8). Rows: `tests/fixtures/cx_host_dispatch.cyr` row 13 (ELOOP -40, ENOTEMPTY -39, `syscall(999)` -38), run by `cx_host_dispatch.sh` and the cross-OS legs (ecb / ach 77); mutants MU6 / MU7. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-18 on the 6.7.15 platform lane (branch l6715-platform, unit P4), with cxvm
built from the lane's tree (the host-dispatch fix, issues/archived/2026-10-17-cxvm-forwards-guest-x86-numbers-through-host-renumbering.md,
and the path calls, issues/archived/2026-10-16-cx-crossos-mkdir-symlink-rows-fail-and-no-gate-runs-them.md) for each host:
x86_64 Linux (`build/cycc`), pi (`cycc_aarch64`), ecb (`CYRIUS_MACHO_ARM=1 cycc_aarch64` + `codesign -s -`), ach
(`CYRIUS_MACHO=1 cycc`).
**Placement:** 6.7.16 — Break 2, repair 6 (platform lane, wave 1, unit P2; placed at the 6.7.16 open, 2026-10-19) — never 7.x.
**Severity:** Low — a portable cx program that compares an errno against its Linux value reads a different answer on a
Mac's cxvm. No boundary is crossed (cxvm runs trusted bytecode; no ledger id).
**Found:** in passing, running the three crossos files the path-call fix makes pass on cx
(pe_open_failure_errno, open_flags_per_target, atomic_write_temp_exclusive) on each host's cxvm: they pass in full on
x86_64 Linux and pi, and open_flags_per_target ends `38 passed, 6 failed (44 total)` on ecb and on ach — every
failure an -ELOOP row, `got -62, expected -40` (the file's `_eloop()` answers 62 only under `CYRIUS_TARGET_MACOS`,
and a cx build is `CYRIUS_TARGET_CX`).

## Reproduction

`eloop.cyr`, compiled once with `cycc_cx`, the `.cyx` run on each host's cxvm in an empty directory:

```cyr
# A cx guest's view of a host errno: open(link, O_RDONLY | O_NOFOLLOW) is -ELOOP, x86_64 Linux's 40.
var t = syscall(2, "eloop_t", 577, 420);   # O_WRONLY | O_CREAT | O_TRUNC
syscall(3, t);
syscall(87, "eloop_l");
syscall(88, "eloop_t", "eloop_l");
var fd = syscall(2, "eloop_l", 131072, 0); # O_RDONLY | O_NOFOLLOW
syscall(87, "eloop_l");
syscall(87, "eloop_t");
syscall(60, 0 - fd);
```

```text
x86_64 Linux cxvm exit=40
pi cxvm exit=40
ecb cxvm exit=62
ach cxvm exit=62
```

## Root cause

cxvm serves a guest call through the HOST's stdlib wrapper (6.7.15) and returns the wrapper's answer as it is. On a
Darwin host that answer is `-<Darwin errno>`: the Mach-O syscall path negates the BSD errno the kernel sets, and
the macOS peers keep Darwin's values (lib/syscalls_macos.cyr's `Errno` enum: EAGAIN 35; Darwin's ELOOP is 62,
ENOTEMPTY 66, ENAMETOOLONG 63, ENOSYS 78, ENOTSUP 45 …). The numbers that agree (EPERM 1, ENOENT 2, EBADF 9, EACCES
13, EEXIST 17, ENOTDIR 20, EISDIR 21, EINVAL 22) hide it for most rows. The .cyx ABI is x86_64 Linux's, so a guest
expects Linux's value on every host. The same class may hold for kill()'s signal numbers (Linux SIGUSR1 10 is
Darwin's SIGBUS) — not measured.

## Fix direction

Map a Darwin host's negative answer back to the Linux errno in cxvm's dispatch (`_cx_host_sys`, under
`#ifdef CYRIUS_TARGET_MACOS`) for the values that differ, and decide whether kill()'s signal numbers get the same
treatment (Linux numbers in, the host's out). Row: the repro above exits 40 on ecb and ach; open_flags_per_target on
each Mac's cxvm `44 passed, 0 failed`.

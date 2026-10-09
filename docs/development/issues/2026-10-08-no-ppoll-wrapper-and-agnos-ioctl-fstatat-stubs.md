# No stdlib `ppoll` wrapper, and the agnos peer lacks `sys_ioctl` / `sys_fstatat` stubs (asked by yukti) — OPEN

**Status:** 🟡 **OPEN** — re-verified 2026-10-08 against 6.7.6 @ 2fb6ad8b: a program calling `sys_ppoll(…)` is
refused on x86_64 and aarch64 Linux (`undefined function 'sys_ppoll'`; no peer defines it), and one calling
`sys_ioctl` / `sys_fstatat` is refused under `CYRIUS_TARGET_AGNOS=1` (both undefined) while the Linux build is rc 0.
yukti carries the stopgaps (`lib/yukti.cyr:64-70, 242-267, 314-345`).
**Placement:** 6.7.11 — Break 2, repair 2: the platform release (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-09 — never 7.x.
**Discovered:** yukti 2.3.12–2.3.14 ("Switch to the stdlib wrapper once one exists", `lib/yukti.cyr:322`);
filed 2026-10-08 from roadmap.md.
**Severity:** Low — API gaps with shipped fold-side stopgaps.
**Affects:** cycc ≤ 6.7.6 `lib/syscalls_*.cyr`.

## Summary

1. **ppoll.** No syscall peer wraps ppoll (or a multi-fd poll); the stdlib has only the single-fd
   `fd_wait_ready(fd, want_write, timeout_ms)` (`lib/syscalls_linux_common.cyr:1227`, a raw poll 7 that ESYSXLAT
   turns into ppoll on aarch64). The aarch64 peer declares `SYS_PPOLL = 1073` (private alias → 73,
   `lib/syscalls_aarch64_linux.cyr:130`, used only by `sys_pause`); the x86_64 peer declares no ppoll number. So yukti
   spells its one raw `syscall()` (`_yk_ppoll`, `lib/yukti.cyr:332-344`) with a LOCAL `enum YkSyscalls { SYS_PPOLL =
   271; }` on x86_64 (`:64-70`), and declines with -78 on macOS / -ENOSYS on agnos.
2. **agnos `ioctl` / `fstatat`.** The Linux peers define `sys_ioctl` (`lib/syscalls_linux_common.cyr:185`) and
   `sys_fstatat` (`:86`); Windows has fail-closed stubs (`lib/syscalls_windows.cyr:920, 933`, -38); the agnos peer
   (`lib/syscalls_x86_64_agnos.cyr`) defines neither, so portable code must `#ifdef CYRIUS_TARGET_AGNOS` every call —
   yukti's `_yk_ioctl` / `_yk_lstat` (`lib/yukti.cyr:242-266`).

## Reproduction

```sh
cd /home/macro/Repos/cyrius
printf 'include "lib/syscalls.cyr"\nvar st[256];\nvar a = sys_ioctl(0, 0x5401, &st);\nvar b = sys_fstatat(0 - 100, "/", &st, 0);\nsyscall(SYS_EXIT, 0);\n' > /tmp/yk.cyr
CYRIUS_TARGET_AGNOS=1 ./build/cycc < /tmp/yk.cyr > /dev/null   # rc 1: undefined 'sys_ioctl', 'sys_fstatat'
./build/cycc < /tmp/yk.cyr > /dev/null                          # rc 0
printf 'include "lib/syscalls.cyr"\nvar pfd[8];\nvar r = sys_ppoll(&pfd, 0, 0, 0, 8);\nsyscall(SYS_EXIT, 0);\n' > /tmp/pp.cyr
./build/cycc < /tmp/pp.cyr > /dev/null                          # rc 1: undefined 'sys_ppoll' (aarch64 cross: same)
```

## Root cause

Never added: the Linux arms were left to callers, and the agnos peer has no stub for numbers agnos does not
implement.

## Proposed fix

1. `sys_ppoll(fds, nfds, tsp, sigmask, sigsetsize)` in every peer, one definition with the arms inside (api-surface
   counts source text): x86_64 Linux 271 (add `SYS_PPOLL = 271` to the x86_64 peer), aarch64 the existing 1073 alias,
   macOS `-78` (Darwin has no ppoll and neither Mach-O backend routes it), Windows / agnos fail-closed `-38`. A
   peer-level `SYS_PPOLL = 271` duplicates yukti's local `enum YkSyscalls { SYS_PPOLL = 271; }`; a same-value
   duplicate enum member builds silently (measured: two enums both declaring it, rc 0), so the overlap is benign while
   the values agree. yukti's switch to the wrapper is its own release, after the cyrius release that ships it.
2. agnos peer: `fn sys_ioctl(fd, request, argp): i64 { return 0 - 38; }` and `fn sys_fstatat(dirfd, path, buf,
   flags): i64 { return 0 - 38; }` (fail closed, the Windows shape; a real `fstatat` over agnos's length-carrying
   `sys_lstat` / `sys_stat` is a later choice).
3. Per CLAUDE.md, each new wrapper gets a `tests/tcyr/crossos/` companion, run on ecb / ach / cass / pi.

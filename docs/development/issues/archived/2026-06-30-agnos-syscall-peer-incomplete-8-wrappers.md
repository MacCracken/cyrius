# stdlib — the AGNOS syscall peer is INCOMPLETE: 8 implemented kernel syscalls have no `sys_*` wrapper

**Status**: ✅ **CYRIUS DONE (v6.3.14, 2026-06-30)** — all 8 `SYS_*` constants (new `SysNrAgnosProc` enum) + `sys_*` wrappers added to `lib/syscalls_x86_64_agnos.cyr` (`sys_klug`#36, `sys_execwait`#37, `sys_fbinfo`#38, `sys_blit`#39 a4=r10, `sys_kbscan`#42, `sys_spawn_path`#43, `sys_sched_yield`#44, `sys_exec_redirect`#62). Verified: a `--agnos` program calling all 8 compiles + emits the right `syscall #N` for each. End-to-end value confirms when a base-system consumer (bote/t-ron/aegis) links + runs on agnos. The agnos-side originating record can close its half.
> Original filing below.

**Status**: ⏳ **OPEN — incoming request from the agnos side.** cyrius owns this; the agnos kernel already implements all 64 syscalls (`0–63` contiguous). `lib/syscalls_x86_64_agnos.cyr` exposes `SYS_*`/`sys_*` for `0–35, 40–41, 45–61, 63` but **omits 8 numbers the kernel dispatches**. Same shape as the just-closed lseek + signal-constant gaps — a kernel syscall with no peer wrapper → a `--agnos` consumer either hand-rolls a raw `syscall(N,…)` (the Linux-number mis-dispatch landmine) or hard-link-fails.
**Date**: 2026-06-30
**Priority**: **Medium — proactive, before the base-system consumers land.** The AGNOS base stack now porting to `--agnos` — **kavach, bote, t-ron, thoth, phylax, aegis** — lands squarely on the **process/exec band (`execwait`#37 / `spawn_path`#43 / `exec_redirect`#62)** for spawning + capturing tool subprocesses, and **`klug`#36** for reading the audit/log ring. Filing now so the wrappers exist *before* each consumer hits a one-at-a-time link error (the reactive path lseek/SIGHUP took).
**Where**: cyrius `lib/syscalls_x86_64_agnos.cyr` — add a `SYS_*` enum value + a `sys_*` wrapper for each, mirroring the existing peer pattern.
**Originating record (agnos side)**: agnos `docs/development/issues/2026-06-30-cyrius-agnos-peer-incomplete-syscall-wrappers.md`.
**Precedent (same shape, both RESOLVED once surfaced)**: `2026-06-29-agnos-sys-symlink-peer.md` (this folder); agnos `archive/2026-06-16-cyrius-patra-lseek-syscall-gap.md` + `archive/2026-06-23-...signal-number-constants.md`.

## The gap — the 8 missing numbers (ABI verified from agnos `kernel/core/syscall.cyr` + `syscall_hw.cyr`)

`a4` (the 4th arg) arrives via **`r10`**, the established 4-arg agnos convention (as `sys_link`#32 / `sys_symlink`#63).

| # | agnos syscall (signature) | returns | who needs it on `--agnos` |
|---|---|---|---|
| **36** | `klug(buf=arg1, len=arg2)` — copy the unified **klug** log ring (`core/klug.cyr`) into a user buffer, oldest→newest (newest `len` bytes if smaller; dmesg tail) | bytes / -1 | aegis, phylax, sakshi (log/dmesg read) |
| **37** | `execwait(path=arg1, pathlen=arg2)` — load a static ELF64 from disk, run it to completion in ring 3 | child exit code / -1 | bote, daimon, t-ron, thoth (+ agnsh/ark/kriya call it via **raw** today) |
| **38** | `fbinfo(buf=arg1, len=arg2)` — write the 24-byte framebuffer geometry struct | bytes / -1 | chakshu, kii, aethersafha |
| **39** | `blit(src=arg1, w=arg2, h=arg3, dstxy=arg4)` — copy a w×h 32bpp block to the framebuffer (a4=r10) | 0 / -1 | chakshu, kii, aethersafha |
| **42** | `kbscan(buf=arg1, max=arg2)` — NON-blocking raw-scancode drain for ring-3 | count / -1 | chakshu, cyim (TUI input) |
| **43** | `spawn_path(path=arg1, len=arg2)` — NON-blocking from-disk spawn (scheduled, returns immediately) | pid / -1 | bote, daimon (concurrent spawn) |
| **44** | `sched_yield()` — cooperative yield to the scheduler (dispatches in the agnos SYSCALL entry stub, not `ksyscall`) | 0 | threading / cooperative loops |
| **62** | `exec_redirect(src_fd=arg1, dst_fd=arg2)` — arm a one-shot fd redirect before `execwait`/spawn (capture a child's stdout/stderr) | 0 / -1 | bote, daimon, t-ron (capture tool output) |

## The peers to add (mirrors the existing wrappers)

```cyrius
SYS_KLUG = 36;          fn sys_klug(buf, len): i64 { return syscall(SYS_KLUG, buf, len); }
SYS_EXECWAIT = 37;      fn sys_execwait(path, pathlen): i64 { return syscall(SYS_EXECWAIT, path, pathlen); }
SYS_FBINFO = 38;        fn sys_fbinfo(buf, len): i64 { return syscall(SYS_FBINFO, buf, len); }
SYS_BLIT = 39;          fn sys_blit(src, w, h, dstxy): i64 { return syscall(SYS_BLIT, src, w, h, dstxy); }   # a4=r10
SYS_KBSCAN = 42;        fn sys_kbscan(buf, max): i64 { return syscall(SYS_KBSCAN, buf, max); }
SYS_SPAWN_PATH = 43;    fn sys_spawn_path(path, len): i64 { return syscall(SYS_SPAWN_PATH, path, len); }
SYS_SCHED_YIELD = 44;   fn sys_sched_yield(): i64 { return syscall(SYS_SCHED_YIELD); }
SYS_EXEC_REDIRECT = 62; fn sys_exec_redirect(src_fd, dst_fd): i64 { return syscall(SYS_EXEC_REDIRECT, src_fd, dst_fd); }
```

**Naming note: it is `klug`, not `klog`.** The agnos subsystem is `core/klug.cyr` (the unified klug log ring); the old `klog` name is dead and agnos is renaming its remaining references to `klug` — so the wrapper should be `sys_klug`#36 to match. (Some agnos modules `process_agnos.cyr` already drive `execwait`#37 / `spawn_path`#43 internally via raw numbers — exposing the named `sys_*` wrappers lets every consumer call them portably and lets those internals stop hand-rolling raw numbers, the §"syscall-number overlap" hazard from `2026-06-15-cyrius-stdlib-missing-syscalls`.)

## Done-criteria

The 8 `SYS_*`/`sys_*` resolve clean on a `--agnos` build (a tiny `--agnos` program calling each compiles + emits the right `syscall #N`). End-to-end value is confirmed when a base-system consumer (e.g. bote/t-ron spawning + capturing a tool via `sys_execwait`/`sys_exec_redirect`, or aegis reading the ring via `sys_klug`) links + runs on agnos with no raw-syscall hand-rolling.

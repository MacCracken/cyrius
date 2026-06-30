# stdlib — add the AGNOS `sys_symlink` peer for kernel `symlink`#63

**Status**: ✅ **CYRIUS HALF DONE (2026-06-29)** — `sys_symlink` + `SYS_SYMLINK = 63` landed in `lib/syscalls_x86_64_agnos.cyr` (mirrors `sys_link`#32's 4-arg ABI, a4=r10). Agnos-target compile verified: resolves clean and emits `syscall #63` (`mov …,0x3f`). **Remaining (downstream, not cyrius):** the full done-criteria's on-agnos round-trip — a `--agnos` program creates a symlink that resolves + survives `e2fsck` — is the ark M3 `.ark`-with-symlinks install exerciser; verify there. (Was: ⏳ OPEN — incoming request from the agnos side. cyrius owns this; the agnos kernel half already shipped at 1.51.0.)
**Date**: 2026-06-29
**Priority**: **Medium — the ark v2 / agnova DO-FIRST prerequisite.** Unblocks **ark M3** (on-agnos install of a prebuilt signed `.ark`, = agnova's install minimum): `ark_pkg_install` pass-2 creates `.so → .so.N` symlinks. A `--agnos` program cannot create a symlink until this peer lands, even though the kernel implements it.
**Where**: cyrius `lib/syscalls_x86_64_agnos.cyr` — the agnos file-op peer band. It has `sys_unlink`#30 / `sys_rename`#31 / `sys_link`#32 (hardlink) / `sys_stat`#33 but **no `sys_symlink`**. The new peer slots right beside `sys_link`.
**Originating record (agnos side)**: agnos `docs/development/issues/2026-06-29-cyrius-agnos-sys-symlink-peer.md`; kernel `symlink`#63 landed at **agnos 1.51.0** (`kernel/core/syscall.cyr`, over the pre-existing `ext2_symlink`).

## The gap

No `--agnos` program (ark / agnova / kriya `ln -s`) can create a symbolic link — the agnos file-op peer band is missing `sys_symlink`. The agnos kernel arm alone is a no-op to userland until cyrius exposes the number.

## The kernel ABI to wire against (verified from agnos `kernel/core/syscall.cyr` @ 1.51.0)

### `symlink` — agnos syscall **#63**
```
symlink(target = arg1, targetlen = arg2, linkpath = arg3, linkpathlen = a4) -> rax
```
- `arg1`/`arg2` = the symlink's **TEXT contents** (what it points at) + length. Link TEXT, **NOT a path the kernel resolves** (a symlink may point at a nonexistent/relative target). Kernel validates it as a user buffer, `1 <= targetlen <= 4096` (one ext2 block).
- `arg3`/`a4` = the **linkpath** (where the link is created) + length. A real path: ext2-only (FAT/exFAT → `-1`). `a4` arrives via `r10` — the established 4-arg agnos convention, identical to `sys_link`#32 / `sys_rename`#31.
- Returns **0** on success, **-1** on failure (POSIX-like).

### The peer to add (mirrors `sys_link` exactly)
```cyrius
fn sys_symlink(target, targetlen, linkpath, linkpathlen): i64 {
    return syscall(SYS_SYMLINK, target, targetlen, linkpath, linkpathlen);
}
```
with `SYS_SYMLINK = 63` added to the agnos syscall-number enum next to `SYS_LINK`. Number **#63** was the next free agnos syscall (#0–62 all taken; #44 `sched_yield` dispatches in the agnos SYSCALL entry stub, not its `ksyscall`). NOTE: agnos's planned 1.52.x audio syscall band ("next free contiguous band") consequently becomes **#64-69** — no action here, just FYI for the next agnos→cyrius peer band.

## Done-criteria

The agnos-side item (a) is marked complete only when **both** halves ship **AND** an on-agnos round-trip works: a `--agnos` program calls `sys_symlink(...)`, the symlink lands on the agnos-fs, resolves on traversal, and survives `e2fsck -fn`. The natural end-to-end exerciser is the ark M3 `.ark`-with-symlinks install.

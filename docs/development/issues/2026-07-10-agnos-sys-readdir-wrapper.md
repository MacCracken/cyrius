# 2026-07-10 — agnos `sys_readdir` wrapper for the directory-listing syscall (#81)

> **✅ RESOLVED cyrius-side (v6.4.43, 2026-07-10):** `SYS_READDIR = 81` + the `sys_readdir(path,
> buf, max)` wrapper added to `lib/syscalls_x86_64_agnos.cyr` after the `sys_blk_*` band (same
> agnos-only pattern; #81 is `fchdir` on Linux so it lives only in the agnos syscall stdlib).
> agnos-target compile verified; default cycc byte-identical; api-surface + cyrdoc regenerated.
> Named entry point now trickles to crab / a future `ls` / agnsh by name.

**Status:** OPEN — cyrius-side ask. The **kernel half is done** in agnos — **cut 1.53.13**
(`ext2_readdir_sys` + dispatch #81, QEMU-proven: crab lists real `/bin` and `/`). Full detail in
`agnos/docs/development/issues/2026-07-10-readdir-syscall-cyrius-wrapper.md`. This is the
cyrius stdlib task: add the agnos wrapper so the syscall trickles to programs by name.

## Ask

Add a `sys_readdir` wrapper to the agnos syscall stdlib (`lib/syscalls_x86_64_agnos.cyr`),
mirroring the existing `sys_shm_*` (v6.4.34) and `sys_blk_*` (v6.4.39) agnos wrappers:

```
# ring-3 directory listing (agnos syscall #81). Fills `buf` with up to `max` fixed
# 64-byte records: name (NUL-terminated) at +0, type at +63 (1 = dir, 0 = file).
# Returns the entry count (>= 0), or a negative error. agnos-only.
fn sys_readdir(path, buf, max): i64 {
    return syscall(81, path, buf, max);
}
```

It must be `#ifdef CYRIUS_TARGET_AGNOS`-gated: syscall **81 is `fchdir` on Linux x86_64**, so
the wrapper should only emit it on agnos (on Linux: return an error / not be defined, matching
how the other agnos-only bands are handled).

## Why cyrius, not just agnos

The syscall is live in the kernel, but Cyrius programs currently reach it only via the raw
`syscall(81, …)` under their own `#ifdef CYRIUS_TARGET_AGNOS`. A stdlib `sys_readdir` gives a
named, target-gated entry point — the same reason `sys_shm_*` / `sys_blk_*` were added — so
consumers (crab, a future `ls`, agnsh) don't hand-roll the raw number.

## ABI (for the wrapper doc)

`sys_readdir(path, buf, max) -> count`
- `path` — user NUL-terminated cstring (absolute directory path).
- `buf` — user buffer, `max * 64` bytes.
- record `i` at `buf + i*64`: bytes `0..62` = name (NUL-terminated, ≤ 62 chars), byte `63` =
  type (`1` = directory, `0` = file). `.` and `..` are omitted by the kernel.
- returns entry count (≥ 0), or negative (`-1` bad ptr / not ext2, `-2` not found, `-4` not a dir).

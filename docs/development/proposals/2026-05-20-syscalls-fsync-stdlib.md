# Stdlib syscall wrapper: `sys_fsync` (and `sys_fdatasync`)

**Filed:** 2026-05-20 during hapi M4 (`adopt` + manifest-edit atomicity)
**Severity:** Stdlib gap — hapi M4's `manifest_append_link_row` and `manifest_remove_link_row` rely on the standard `write-to-tmp + fsync + rename` pattern for crash-safe atomic edits, but `fsync(2)` has no stdlib wrapper. Hapi calls it via `syscall(74, fd)` with a magic number.
**Affects:** `lib/syscalls_x86_64_linux.cyr`, `lib/syscalls_aarch64_linux.cyr`. Companion to the 2026-05-17 *at()-family proposal but conceptually separate (durability, not filesystem-tree mutation).
**Target slot:** Same v6.x stdlib-syscall expansion arc as the 2026-05-17 proposal, OR a same-minor quality-of-life patch if the v6.x arc lands beyond hapi's M4–M7 window. User direction.

## Summary

Two missing wrappers that every consumer doing atomic file replacement needs:

| Name | Linux syscall | Why a wrapper |
|---|---|---|
| `sys_fsync` | `fsync(2)` (SYS_FSYNC=74 x86_64; SYS=82 aarch64) | The durability half of the standard "write-tmp + fsync + rename" pattern. Without it, `rename(2)` can return success while the tmp's contents are still in page cache — a power loss between rename and a hypothetical later flush produces a zero-length or partial file at the destination. Required by every atomic-replace consumer. |
| `sys_fdatasync` | `fdatasync(2)` (SYS_FDATASYNC=75 x86_64; SYS=83 aarch64) | The "data-only" variant — flushes file contents without forcing metadata. Useful when the caller doesn't care about mtime/atime durability and wants slightly less I/O. Commonly used in append-only logs (which describes hapi's audit trail). |

Pair with `lib/syscalls_*_linux.cyr` adding the syscall-number `enum` entries and the bare wrappers; same shape as the existing `sys_unlink` / `sys_symlink` pattern. No constants needed (both take `fd` only).

## Why this is more than cosmetic

`syscall(74, fd)` works today, but:

1. The magic number is per-arch (74 on x86_64, 82 on aarch64). Every consumer that wants cross-arch portability has to `#ifdef` the number. The wrapper hides this exactly like every other `sys_*` wrapper already does.
2. It silently fails wrong. `syscall(74, fd)` on aarch64 calls `sched_yield` (syscall 74 on aarch64) instead of `fsync` — and `sched_yield` returns 0, so the caller sees what looks like a successful fsync. This is the **specific failure mode the bare-name wrapper convention exists to prevent.**
3. Searchability. `grep sys_fsync src/` finds every fsync site in any consumer; `grep "syscall(74" src/` finds noise (and misses aarch64 callers using the right number).

## Hapi's call site

[`hapi/src/manifest_write.cyr:_hmw_write_atomic`](https://github.com/MacCracken/hapi/blob/main/src/manifest_write.cyr):

```cyrius
fn _hmw_write_atomic(path, buf, n): i64 {
    # ... open tmp, write contents ...
    syscall(74, fd);                       # fsync(fd)  ← magic number
    file_close(fd);
    var rrc = syscall(82, tmp, path);      # rename(tmp, path)
    ...
}
```

The `syscall(82, ...)` for rename is on the 2026-05-17 stdlib-gap proposal; fsync slots beside it.

## Future consumers

Anyone implementing an atomic file replacement: package managers (zugot), config writers, log-rotation tools, persisted-state caches. The same pattern recurs everywhere a single-machine durability guarantee matters.

## Workaround until landed

Hapi continues to use `syscall(74, fd)` on x86_64. If the v6.x arc slips past hapi's v0.5.0 ship, hapi can ship its own private wrapper in `src/` and grep-replace when the stdlib version lands. Marked here so future-claude doing the stdlib add knows where the consumer-side calls are.

## Relationship to the 2026-05-17 *at()-family proposal

This proposal is a companion, not a subset. The *at() family is about *which path* the syscall operates on (rooted at an fd vs cwd). fsync/fdatasync are about *durability* of writes already issued. They naturally bundle in the same v6.x stdlib expansion arc but address distinct gaps; consumers may need one without the other.

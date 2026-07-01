# stdlib — no AGNOS peer for fd-based `sys_fstat(fd, buf)` (agnos exposes only path-based `sys_stat`#33)

**Status**: ⏳ **OPEN — surfaced by the base-stack 6.3.15 migration (aegis 1.1.1).**
**Date**: 2026-06-30
**Priority**: **Medium — proactive, before the base stack runs on `--agnos`.** aegis's TOCTOU-safe stat path uses **fd-based `fstat`** by design (open with `O_NOFOLLOW`, then `fstat` the fd — closes the race between the stat and the consumer's action), so switching it to path-based `stat` would reintroduce the very TOCTOU it exists to avoid.
**Where**: cyrius `lib/syscalls_x86_64_agnos.cyr`.

## The gap

`sys_fstat(fd, buf)` is defined in `lib/syscalls_linux_common.cyr` (and the arch Linux/macOS peers), but **`lib/syscalls_x86_64_agnos.cyr` is standalone** — it deliberately does **not** include `syscalls_linux_common.cyr` — and defines **no `sys_fstat`**. It exposes only the **path-based** form:

```cyrius
# lib/syscalls_x86_64_agnos.cyr
SYS_STAT = 33;   # stat(path, pathlen, statbuf) → 0 / -1
fn sys_stat(path, pathlen, statbuf): i64 { return syscall(SYS_STAT, path, pathlen, statbuf); }
# ... no sys_fstat ...
```

So a `--agnos` consumer that calls `sys_fstat(fd, &sb)` links against an **undefined symbol** → `ud2`/SIGILL when reached. aegis hits this directly:

```cyrius
# aegis src/lib.cyr:_aegis_stat_modesize  (the TOCTOU-safe path)
var fd = sys_open(path_cstr, O_RDONLY | O_CLOEXEC | _AEGIS_O_NOFOLLOW, 0);
var sb[144];
var rc = sys_fstat(fd, &sb);          # <-- no agnos peer
```

(Note: `sys_access` is **not** part of this gap — the agnos file already ships a deliberate fail-stub `fn sys_access(path, mode): i64 { return 0 - 1; }` with a comment that agnos has no `access(2)`. Consumers treat `-1` as "unsupported/deny". This issue is `fstat`-only.)

## The fix — decide, then add the peer

Two questions for the agnos + cyrius owners:

1. **Does the agnos kernel dispatch an `fstat`-by-fd syscall?** The agnos enum has `SYS_STAT`#33 (path-based) but no visible fstat number. If the kernel can `fstat` an open fd (it has the fd table + inode), add the number and the peer:

   ```cyrius
   SYS_FSTAT = <n>;   # fstat(fd, statbuf) → 0 / -1
   fn sys_fstat(fd, statbuf): i64 { return syscall(SYS_FSTAT, fd, statbuf); }
   ```

   The `struct stat` layout is already agnos-native in this file (§4.1, 48 bytes, all 8-byte fields) so the buffer contract is settled.

2. **If agnos will not gain fstat**, ship an agnos `sys_fstat` peer that fails closed (`return 0 - 1;`, like `sys_access`) so consumers link and get a defined "unsupported" answer rather than a SIGILL — and document that `--agnos` fd-based stat is unavailable, so TOCTOU-sensitive consumers (aegis) must gate that path behind `#ifndef CYRIUS_TARGET_AGNOS` or fall back to path-based `sys_stat` with the race documented.

Either way the symbol must resolve on `--agnos`; today it does not.

**Precedent (same shape, resolved once surfaced)**: `2026-06-29-agnos-sys-symlink-peer.md`, `2026-06-30-agnos-syscall-peer-incomplete-8-wrappers.md` (this folder).
**Originating record**: AGNOS base-security-stack migration to cyrius 6.3.15 (aegis tier); see `agnosticos` memory `project_base_stack_6315_migration`.

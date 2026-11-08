# The stdlib has no `sys_fchdir`, and on aarch64 no literal reaches it — OPEN

**Status:** 🟡 **OPEN** — verified 2026-11-03 against cyrius 6.7.18. `lib/syscalls_linux_common.cyr` wraps
`sys_chdir` (line 233), and has neither `sys_fchdir` nor an `SYS_FCHDIR` constant on either Linux peer.
**Placement:** unpinned — 6.x-line backlog. A stdlib wrapper, plus the aarch64 `1000+N` alias it needs.
**Discovered:** 2026-11-03 by kriya (coreutils-equivalent), implementing `find -execdir` / `-okdir` for 1.8.2.
**Severity:** Medium. On x86_64 a consumer can still issue the raw number. On aarch64 the native call is
unreachable, so the consumer has to depend on `/proc` instead.
**Affects:** cyrius 6.7.18 (verified), Linux x86_64 and aarch64; `lib/syscalls_linux_common.cyr`, and the
aarch64 renumbering chain (ESYSXLAT).

## Summary

`fchdir(fd)` is how a program enters a directory it holds open. That matters for a tree walker that has to
run a command *inside* a directory it reached by descriptor, without re-resolving a path an attacker could
swap for a symlink. It is GNU fts's `FTS_CWDFD` / `fchdir` model, and it is how `find -execdir` is safe.

The stdlib does not wrap it. A consumer that reaches for the raw number gets the right call on x86_64 (81).
On aarch64 there is no way through:

- **`syscall(50, fd)`**, aarch64's native `fchdir`, inside `#ifdef CYRIUS_ARCH_AARCH64`, is renumbered to
  201, which is `listen`. The compiler says so, accurately: *"raw syscall 50 inside a native-aarch64 region
  is renumbered → 201 (listen); no 1000+N alias exists for native fchdir (the chain has no 1050 row)"*.
- **`syscall(81, fd)`**, x86's `fchdir`, has no translation row, so it reaches the aarch64 kernel verbatim as
  **`sync`**.
- **`syscall(1050, fd)`** is unknown to both the chain and the kernel (`Unknown syscall 1050`).

## Reproduction

```cyrius
include "lib/string.cyr"
include "lib/fmt.cyr"
include "lib/alloc.cyr"
include "lib/io.cyr"
include "lib/syscalls.cyr"
fn native_fchdir(fd): i64 {
    #ifdef CYRIUS_ARCH_AARCH64
    return syscall(50, fd);
    #endif
    return 0;
}
var fd = sys_open("/tmp", O_DIRECTORY, 0);
fmt_int(native_fchdir(fd)); println("");
syscall(SYS_EXIT, 0);
```

```sh
cyrius build --aarch64 p.cyr p && qemu-aarch64 -strace ./p 2>&1 | grep listen
# warning: raw syscall 50 inside a native-aarch64 region is renumbered → 201 (listen); no 1000+N alias …
# NNN listen(3,…) = -1 errno=88 (Socket operation on non-socket)
```

Swap in `81` and the strace shows `sync(…)`. Swap in `1050` and it shows `Unknown syscall 1050`.

## Proposed fix

- **`sys_fchdir(fd)`** in `lib/syscalls_linux_common.cyr`, with `SYS_FCHDIR` on each peer: x86_64 81,
  aarch64 through a private alias such as `SYS_FCHDIR = 1050` plus the matching `1050 → 50` row, which is
  the same shape as `SYS_FCHOWN = 1055`. On agnos, -38, like the other cwd calls.
- Optionally, **`sys_dup(fd)`** on the Linux peers. It exists only in the agnos file today. kriya used
  `sys_fcntl(fd, F_DUPFD_CLOEXEC, 0)`, which works, so this is a convenience rather than a gap.

## Consumer-side workaround

kriya 1.8.2 (`src/lib/spawn.cyr`, `_k_fchdir`) issues `syscall(81, fd)` on x86_64. On aarch64 it does
`sys_chdir("/proc/self/fd/N")`: the magic link names exactly the directory the descriptor holds, so the
child still lands where `fchdir` would put it. That depends on `/proc` being mounted. Without it, the
command is not run, and the failure is reported. kriya switches to `sys_fchdir` when this lands.

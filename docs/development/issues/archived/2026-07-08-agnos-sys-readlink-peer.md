# agnos `sys_readlink`#70 peer — add to `lib/syscalls_x86_64_agnos.cyr` — RESOLVED

> **RESOLVED v6.4.23 — archived 2026-07-08.** Added `SYS_READLINK = 70` to `enum
> SysNrAgnos` + the 4-arg wrapper `sys_readlink(path, pathlen, buf, buflen)` (a4=r10),
> mirroring `sys_symlink`#63. `docs/api-surface.snapshot` updated (`sys_readlink/4`).
> Lib-only (cycc byte-identical); hapi's agnos branch can drop its raw-number stopgap on
> re-sync. See CHANGELOG [6.4.23].


**Discovered:** 2026-07-08 during the agnos kernel `readlink`#70 landing + the hapi
(GNU-stow-equivalent symlink manager) `--agnos` port.
**Severity:** Low — stdlib-surface recommendation (ABI-completeness). The consumer ships a working
stopgap (local syscall number), so nothing is blocked; the peer just makes the call native.
**Affects:** cycc 6.4.x (the agnos peer `lib/syscalls_x86_64_agnos.cyr` has `sys_symlink`#63 but no
`sys_readlink`, and no `sys_lstat`; `sys_fstat` fails closed). Consumer (hapi) is on the **6.4.22**
vendored snapshot. Recommended floor for the fix to deploy: whatever 6.4.x cut ships this peer.

## Summary

agnos grew a ring-3 `readlink`#70 syscall — the symlink-INTROSPECTION peer of `symlink`#63 (which
the cyrius `sys_symlink` peer already wraps). It reads a symbolic link's TEXT target **no-follow**
into a buffer, returning the byte length or -1. cyrius has no `sys_readlink` wrapper for it (and no
`sys_lstat`; path-based `sys_stat`#33 FOLLOWS the final symlink), so a `--agnos` symlink manager can
create links but has no *native* wrapper to introspect one. The agnos kernel + supervisor (mirshi)
halves are shipped and QEMU-proven; this is the missing ring-3 wrapper.

## Reproduction

Kernel ABI (verified from agnos `kernel/core/syscall.cyr`; QEMU-proven via agnos
`scripts/symlink-smoke.sh` → `READLINK-OK`):

```
readlink(path=arg1, pathlen=arg2, buf=arg3, buflen=a4) -> rax
```
- `arg1`/`arg2` — path to the symlink + len (a real path; ext2-only; the FINAL component is resolved
  NO-FOLLOW, so it reads the LINK not its target — a mid-path symlink still resolves).
- `arg3`/`a4` — output buf + capacity (target written NOT NUL-terminated, ≤ buflen). `a4` rides
  `r10` (the 4-arg agnos convention, same as `sys_symlink`#63 / `sys_link`#32).
- Returns the target byte length (>0) / -1 (path absent, not a symlink, target > buflen, non-ext2).

Today a `--agnos` consumer must hand-roll the number (what hapi ships):
```cyrius
var AGNOS_SYS_READLINK = 70;
var n = syscall(AGNOS_SYS_READLINK, path, strlen(path), buf, buflen);
```

## Root cause (not a bug — a missing surface)

`lib/syscalls_x86_64_agnos.cyr` mirrors the agnos ABI but predates `readlink`#70. `sys_symlink`#63
is the immediate neighbor; `sys_readlink` slots right after it, and `SYS_READLINK = 70` goes after
the audio band `SYS_SND_AVAIL`#69 in `enum SysNrAgnos`.

## Proposed fix (mirrors `sys_symlink` exactly)

```cyrius
# in enum SysNrAgnos, after SYS_SND_AVAIL = 69:
    SYS_READLINK   = 70;          # readlink(path, pathlen, buf, buflen) → target bytes / -1 (a4=r10).
    #   Symlink-INTROSPECTION peer of SYS_SYMLINK=63: reads the link's TEXT target NO-FOLLOW into
    #   buf (≤ buflen, not NUL-terminated); -1 if path absent / not a symlink / target > buflen / non-ext2.

# after fn sys_symlink(...):
# Read the TEXT target of the symlink at `path` (len `pathlen`) into `buf` (cap `buflen`),
# returning the target byte count (≤ buflen, NOT NUL-terminated) or -1. 4-arg, a4 in r10. The
# no-follow introspection peer of sys_symlink#63 (agnos readlink#70) — resolves the FINAL path
# component WITHOUT following it, so a --agnos symlink manager (hapi) can SEE an existing link +
# read its target (there is no lstat peer, and path-based sys_stat#33 FOLLOWS the final symlink).
fn sys_readlink(path, pathlen, buf, buflen): i64 {
    return syscall(SYS_READLINK, path, pathlen, buf, buflen);
}
```

No new preprocessor gating — the existing `#ifdef CYRIUS_TARGET_AGNOS` peer split covers it. (On the
Linux/mac peers, `sys_readlink(path, buf, bufsize)` already exists with the native 3-arg shape; this
is only the agnos 4-arg peer, so no cross-target signature clash — consumers branch per target.)

## Consumer-side workaround (shipped)

**hapi** (frozen 1.0.x, `src/agnos_compat.cyr`) defines `var AGNOS_SYS_READLINK = 70` and calls it
raw from `hapi_readlink`, exactly as it did for `AGNOS_SYS_SYMLINK`#63 before the 6.4.x `sys_symlink`
peer. On landing this peer + a hapi `lib/` re-sync, `hapi_readlink`'s agnos branch collapses to
`sys_readlink(...)` (mirroring how `hapi_symlink` moved to the native peer at hapi 1.0.3).

## The other three halves (context — all done + proven; this is the only open piece)

- **agnos kernel** — `readlink`#70 + the no-follow `ext2_path_lookup_ex(path,len,follow_last)`
  refactor (public `ext2_path_lookup` = the `follow_last=1` wrapper, all prior callers byte-identical).
  QEMU-proven: same `/hn_link` gives `archaemenid` via `open()`/follow but `/etc/hostname` via
  #70/no-follow; e2fsck-clean.
- **hapi** — `link_probe` flipped readlink-first; builds `--agnos` + Linux; suite 242/0.
- **mirshi** — emulates #70 → host `readlink(89)` (unconfined) / `readlinkat(267)` (`--root`);
  seccomp allows 89 + 267; `docker/tools/rltest.cyr` smoke PASS (both modes). Suite 295/0.

## Cross-refs

- agnos `docs/development/issues/2026-07-08-cyrius-agnos-sys-readlink-peer.md` (the agnos-side mirror
  of this request).
- agnos `docs/development/agnos-userland-abi.md` §3.2 row 70 (the canonical ABI contract).

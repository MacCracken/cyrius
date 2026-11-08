# The stdlib wraps no `symlinkat`, `readlinkat`, `getcwd` or `fchmodat2` — OPEN

**Status:** 🟡 **OPEN** — verified 2026-11-03 against cyrius 6.7.18.
**Placement:** unpinned — 6.x-line backlog. Four thin wrappers, plus two x86 table names.
**Discovered:** 2026-11-03 by kriya (coreutils-equivalent), converting its last raw syscalls to stdlib
wrappers for 1.8.4. kriya's sweep took its numeric `syscall(N, …)` literals from 44 to four. These are
the calls left; the fourth is `fchdir`, filed separately
(`2026-11-03-stdlib-has-no-sys-fchdir.md`).
**Severity:** Low. Every one works today through a raw number or a table name, and none misroutes. The
cost is that each consumer has to work out, per arch, which spelling reaches the call, and that is the
class of mistake `kriya-syscalls.tcyr` exists to catch.
**Affects:** cyrius 6.7.18, Linux x86_64 and aarch64; `lib/syscalls_linux_common.cyr`,
`lib/syscalls_x86_64_linux.cyr`.

## Summary

| Call | Wrapper | x86_64 table | aarch64 table | What a consumer must do today |
|---|---|---|---|---|
| `symlinkat` | none (only `sys_symlink`, which is `symlinkat(AT_FDCWD)` on aarch64) | **no `SYS_SYMLINKAT`** | `SYS_SYMLINKAT = 36` | literal 266 on x86, the name on aarch64 |
| `readlinkat` | none (only `sys_readlink`) | **no `SYS_READLINKAT`** | `SYS_READLINKAT = 78` | literal 267 on x86, the name on aarch64 |
| `getcwd` | none | `SYS_GETCWD = 79` | `SYS_GETCWD = 17` | `syscall(SYS_GETCWD, …)` on both |
| `fchmodat2` | none | none | none | literal 452 (one number on every arch since 5.1) |

All four work. Measured with the repro below, on x86_64 natively and on aarch64 under
`qemu-aarch64 -strace`:

- `getcwd` through both the literal 79 and `SYS_GETCWD` reaches `getcwd` on both arches.
- `symlinkat` / `readlinkat` through the aarch64 names reach `symlinkat` / `readlinkat`, and through the x86
  literals 266 / 267 reach them on x86.
- `fchmodat2` through 452 reaches the kernel on both arches: `AT_SYMLINK_NOFOLLOW` on a symlink answers the
  kernel's `-EOPNOTSUPP` (-95) on each. qemu's strace table prints it as `Unknown syscall 452`, but the
  answer is the kernel's, not a `-ENOSYS`.

What is missing is the wrapper. A dirfd-relative tree walker (`cp -R` copying a link inside the tree it
walks) needs `symlinkat` / `readlinkat` *with* a dirfd, which `sys_symlink` / `sys_readlink` cannot give. And
`fchmodat2` is the only chmod that honours `AT_EMPTY_PATH`, so it is the only way to chmod an `O_PATH`
descriptor.

## Reproduction

`repros/2026-11-03-stdlib-unwrapped-at-calls.cyr`:

```sh
cyrius build repros/2026-11-03-stdlib-unwrapped-at-calls.cyr p && ./p
cyrius build --aarch64 repros/2026-11-03-stdlib-unwrapped-at-calls.cyr pa && qemu-aarch64 -strace ./pa 2>&1 \
  | grep -E 'getcwd|symlinkat|readlinkat|452'
```

The repro needs `#ifdef CYRIUS_ARCH_AARCH64` around its `symlinkat` / `readlinkat` calls only because x86
has no table name for them. That `#ifdef` is the gap.

## Proposed fix

- `sys_symlinkat(target, dirfd, linkpath)` and `sys_readlinkat(dirfd, path, buf, bufsize)` in
  `lib/syscalls_linux_common.cyr`, with `SYS_SYMLINKAT = 266` / `SYS_READLINKAT = 267` added to the x86_64
  table. The aarch64 names exist already.
- `sys_getcwd(buf, size)`, over the `SYS_GETCWD` both tables already have.
- `sys_fchmodat2(dirfd, path, mode, flags)` with `SYS_FCHMODAT2 = 452` on both tables. A kernel before 6.6
  answers `-ENOSYS`, which the caller handles (kriya falls back to `fchmod` / `fchmodat`).
- On agnos, -38 for all four, like the other at-family calls the agnos peer lacks.

## Consumer-side workaround

kriya 1.8.4 issues `syscall(266, …)` / `syscall(267, …)` in `fs_symlinkat` / `fs_readlinkat`'s x86 arms
(`src/lib/fs.cyr`), with the aarch64 arms on the table names. It issues `syscall(SYS_GETCWD, …)` in
`k_getcwd` and `syscall(452, …)` in `k_fchmodat2` (`src/lib/sys.cyr`). It switches to the wrappers when
they land.

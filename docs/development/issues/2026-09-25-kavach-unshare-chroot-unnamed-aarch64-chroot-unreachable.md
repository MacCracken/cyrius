# Stdlib names neither `unshare(2)` nor `chroot(2)`, and on aarch64 `chroot` cannot be reached through `syscall()` — OPEN

**Status:** 🟡 **OPEN** — stdlib surface gap plus one `ESYSXLAT` interaction; filed by kavach at its
3.12.8 ABI repairs.
**Placement:** unpinned — 6.6.x-line backlog.
**Discovered:** 2026-09-25, reading kavach's aarch64 build against the 6.6.6 syscall tables, then
measuring under `qemu-aarch64 -strace`.
**Severity:** Medium. Nothing in the stdlib is wrong, but two first-party consumers need these calls
and neither can spell them correctly on aarch64. kavach 3.12.8 refuses namespaces and rootfs entry
there until they exist; takumi carries the pattern the guide forbids.
**Affects:** cyrius 6.6.6 stdlib (`lib/syscalls_x86_64_linux.cyr`, `lib/syscalls_aarch64_linux.cyr`,
`lib/syscalls_linux_common.cyr`) and the ELF-aarch64 `ESYSXLAT` chain (`src/backend/aarch64/emit.cyr`).

## Summary

Neither Linux peer declares `SYS_UNSHARE` or `SYS_CHROOT`, and there is no `sys_unshare` or
`sys_chroot`. A consumer that needs them writes a number, and on aarch64 every number it can write is
wrong or fragile:

- the x86-64 numbers (272, 161) have no `ESYSXLAT` row, so aarch64 runs them as other calls;
- the native aarch64 numbers (97, 51) are what the guide's rule 3 forbids ("Never write the
  aarch64-native number under an `#ifdef CYRIUS_ARCH_AARCH64`"), and for `chroot` the native number
  does not even work, because the getsockname row takes 51.

## Reproduction

cyrius 6.6.6, `cyrius build --aarch64`, run unprivileged under `qemu-aarch64 -strace`:

```cyr
include "lib/syscalls.cyr"
fn main() {
    syscall(161, "/nonexistent-root");      # x86-64 chroot
    syscall(272, 131072);                   # x86-64 unshare(CLONE_NEWNS)
    syscall(51, "/nonexistent-root");       # aarch64-native chroot
    syscall(97, 131072);                    # aarch64-native unshare
    return 0;
}
var r = main();
syscall(SYS_EXIT, r);
```

```
sethostname(6293264,6293248,0,0,0,0) = -1 errno=1 (Operation not permitted)
kcmp(131072,6293248,0,0,0,0) = -1 errno=3 (No such process)
getsockname(6293264,0x600700,(nil)) = -1 errno=14 (Bad address)
unshare(CLONE_NEWNS) = -1 errno=1 (Operation not permitted)
```

- **161 runs `sethostname`**, with the path as the name and whatever `x1` held as the length.
  Unprivileged that is EPERM. As root it succeeds whenever the stray length is 0–64: the UTS
  namespace is renamed, and a caller that reads 0 as "chrooted" runs its payload in the host's
  filesystem.
- **272 runs `kcmp`**.
- **51 is renumbered to 204** by `emit.cyr:1239` (`# getsockname 51→204`), so aarch64 `chroot` is
  unreachable through `syscall()` at all.
- **97 reaches `unshare` today** only because no row claims 97. x86 97 is `getrlimit`; a row added
  for it takes this call silently, which is rule 3's warning.

Rule 3's hazard is not hypothetical in this tree. takumi's aarch64 sleep, `syscall(73, 0, 0, &ts, 0)`
written as native `ppoll`, is `flock` since the 6.6.4 row `73→32` (`emit.cyr:1259`). Measured the same
way: `flock(0,0,…) = -1 errno=22`, returning at once instead of sleeping. takumi pins 6.6.2, so it
breaks on its next pin move rather than today.

## Consumers today

- **kavach**, through 3.12.7: `syscall(272, flags)` in `security_create_namespace` and
  `syscall(161, rootfs)` in `_spawn_enter_rootfs`. On aarch64 the first failed closed (kcmp), and the
  second was only unreached because the namespace step before it failed first. 3.12.8 declares both
  numbers under `#ifdef CYRIUS_ARCH_X86` only, so an aarch64 use is a compile error, and refuses both
  calls on aarch64 before any side effect: `kavach_err_not_supported("NAMESPACES")`, and rootfs entry
  returns -1 ahead of its private mount. aarch64 has no namespaces and no rootfs in kavach until this
  lands.
- **takumi** `src/sandbox.cyr:39-48`: `enum SandboxSysNr { SANDBOX_SYS_UNSHARE = 97; }` under
  `#ifdef CYRIUS_ARCH_AARCH64` (rule 3's pattern; works today), plus the `ppoll` sleep above.

## Requested

1. **Both Linux peers: `SYS_UNSHARE = 272` and `SYS_CHROOT = 161`**, the x86 numbers per rule 2, with
   ELF-aarch64 `ESYSXLAT` rows `272→97` and `161→51`. ⚠ The chain is sequential (`cmp` / `b.ne +8` /
   `movz`, falling through to the next row), so the `161→51` row must sit **below** the
   `51→204` getsockname row, or chroot is carried on to getsockname. This is the same
   produce-after-consume ordering the file already documents for the fsync and statfs bands.
2. **`sys_unshare(flags)` and `sys_chroot(path)`** in `lib/syscalls_linux_common.cyr`, with the agnos,
   macOS and Windows arms returning `-ENOSYS`. agnos has neither call, and no consumer needs them on
   the others.
3. Optional, same shape: `pivot_root` (x86 155, aarch64 41). kavach's rootfs entry names it as the
   next increment over chroot. Its row `155→41` must sit below the `41→198` socket row, for the same
   reason as item 1.
4. Smaller: every seccomp filter should start with an architecture check, which needs the running
   ABI's `AUDIT_ARCH_*` (x86_64 `0xC000003E`, aarch64 `0xC00000B7`). A per-peer `AUDIT_ARCH_NATIVE`
   would let consumers stop hand-writing it. kavach 3.12.8 carries its own
   (`security_seccomp_native_arch`).

## When this lands

kavach deletes the two constants in `src/sys_security_syscalls.cyr`, calls `sys_unshare` /
`sys_chroot`, and drops the aarch64 refusals in `security_create_namespace` and `_spawn_enter_rootfs`.
takumi can replace `SANDBOX_SYS_UNSHARE` with `sys_unshare`, and its aarch64 sleep with
`sys_nanosleep`, which exists today.

# `SYS_IOCTL` is defined for both Linux arches but has no `sys_ioctl` wrapper — stdlib surface gap, two consumers already hand-rolling it

**Status:** ✅ **RESOLVED v6.5.36** — `sys_ioctl(fd, request, argp)` added to `lib/syscalls_linux_common.cyr`. ⛔ Wrapping it exposed a latent bug the filing did not know about: `syscalls_macos.cyr` declared `SYS_IOCTL = 16` while ESYSXLAT's Mach-O arm routes **29 → 54** and had no row for 16, so the number reached Darwin unrouted. The macOS peer now declares 29 and EMACHO_SYSXLAT gained the matching x86 row.
`sys_*` wrapper surface. A three-line consumer workaround exists and is already shipping, so this is a
consistency filing rather than a blocker.
**Placement:** unpinned — 6.x-line backlog. Cheap enough to land opportunistically alongside any other
`syscalls_*` work.
**Discovered:** 2026-08-24 during kybernet v1.5.8 — PID 1 needs `TCGETS`/`TCSETS` on `/dev/console` to
stop a typed emergency-shell password echoing to the screen.
**Severity:** Low — nothing is broken and the workaround is trivial. Filed because the *asymmetry* is the
trap, and because a second first-party repo is about to duplicate the first one's fix.
**Affects:** the stdlib snapshot shipped with cycc 6.5.35, and earlier releases carrying the same tables

## Summary

`SYS_IOCTL` is present and correct in both Linux syscall tables, but no `sys_ioctl` wrapper exists on any
target. The constant being there says "supported"; the missing wrapper means every consumer that needs
it reaches for `syscall()` directly.

That call is *correct* — the enum dispatches per-arch, so it does not violate the "no literal syscall
numbers" rule first-party repos audit against — but it ends up being the only place in an otherwise
fully-wrapped surface where consumer code touches `syscall()` at all, which reads like a rule violation
until a reviewer checks that the first argument is a named constant.

`fcntl` sits in exactly the same position. **argonaut has already shipped its own wrapper for it**, and
kybernet is about to ship one for `ioctl`. Two first-party repos independently reimplementing the same
three lines is the part worth acting on.

### Scale

`syscalls_x86_64_linux.cyr` defines **99** distinct `SYS_*` constants; the Linux wrapper surface provides
**84** distinct `sys_*` functions. Most of the difference is deliberate — `clone`, `brk`, `futex` and
friends are not things a normal consumer should reach for. Two stand out as ordinary file-descriptor
operations:

| syscall | constant | wrapper |
|---|---|---|
| `ioctl` | ✅ both arches (x86_64 16 / aarch64 29) | ❌ none, any target |
| `fcntl` | ✅ both arches (x86_64 72 / aarch64 25) | ❌ none, any target |

For contrast `lseek` and `mmap` *do* have wrappers — but only on the `windows` and `x86_64_agnos`
targets, not the Linux ones. So the surface is not uniformly "everything except the exotic calls"; the
holes vary by target, which is what makes them hard to predict.

## Reproduction

```sh
grep -nE 'SYS_IOCTL *=' ~/.cyrius/lib/syscalls_x86_64_linux.cyr \
                        ~/.cyrius/lib/syscalls_aarch64_linux.cyr
# lib/syscalls_x86_64_linux.cyr:29:    SYS_IOCTL = 16;
# lib/syscalls_aarch64_linux.cyr:47:   SYS_IOCTL = 29;

grep -rnE '^fn (sys_)?ioctl\b' ~/.cyrius/lib/*.cyr
# (no matches)

grep -rnE '^fn (sys_)?fcntl\b' ~/.cyrius/lib/*.cyr
# (no matches)

grep -rnE 'TCGETS|TCSETS|termios|tcsetattr' ~/.cyrius/lib/*.cyr
# (no matches)
```

## Root cause (if known)

Not a defect — the wrapper simply was never added. The `SYS_*` enums and the `sys_*` wrapper list are
maintained separately, so a constant can land without a wrapper and nothing flags it. Speculation, but it
would be cheap to assert the two lists agree for the subset of calls intended to be consumer-facing.

## Proposed fix

Additive and arch-neutral; both constants already exist on both arches. In `syscalls_linux_common.cyr`,
beside the existing wrappers:

```cyrius
fn sys_ioctl(fd, request, arg): i64 {
    return syscall(SYS_IOCTL, fd, request, arg);
}

fn sys_fcntl(fd, cmd, arg): i64 {
    return syscall(SYS_FCNTL, fd, cmd, arg);
}
```

### Optional and separable: a small `termios.cyr`

Worth its own decision rather than being bundled in silently. There is currently no termios surface at
all, so "turn off echo while reading a password" means each consumer hand-deriving constants and struct
layout from kernel headers. That is where the real failure modes are — a wrong offset silently corrupts
terminal state on a console the operator may be depending on.

The encouraging part is that the expensive research is already done and verified against the installed
kernel headers: `/usr/include/asm/ioctls.h` and `/usr/include/asm/termbits.h` on x86 both simply
`#include <asm-generic/...>`, so **x86_64 and aarch64 share identical values and identical layout**:

```
TCGETS = 0x5401        TCSETS = 0x5402        NCCS = 19
tcflag_t = unsigned int (4 bytes)     cc_t = unsigned char (1 byte)

struct termios {          offset   size
    tcflag_t c_iflag;        0       4
    tcflag_t c_oflag;        4       4
    tcflag_t c_cflag;        8       4
    tcflag_t c_lflag;       12       4      <- ECHO lives here
    cc_t     c_line;        16       1
    cc_t     c_cc[19];      17      19
};                        total     36 bytes

ECHO = 0x00008         ECHONL = 0x00040
```

Unlike `struct epoll_event` — packed on x86_64, natural elsewhere, and a source of real consumer breakage
— `struct termios` needs no per-arch treatment on the two targets cyrius supports. A get/set pair plus
`echo_off` / `echo_restore` would be small and low-risk. Not requested as part of this issue; recorded
because the verification is already paid for if it is ever wanted.

## Consumer-side workaround (if any)

Shipping in argonaut 1.13.1, in the file it created specifically to quarantine arch-sensitive syscalls:

```cyrius
# argonaut/src/syscall_compat.cyr:109
# fcntl(fd, cmd, arg) — F_SETFL O_NONBLOCK on the notify and health sockets.
# No stdlib wrapper, but `SYS_FCNTL` IS defined in both arch peers (x86 72 /
# aarch64 25), so the enum does the dispatch and no #ifdef is needed here.
fn ag_sys_fcntl(fd, cmd, arg): i64 {
    return syscall(SYS_FCNTL, fd, cmd, arg);
}
```

kybernet v1.5.8 will carry the same shape for `ioctl`. Any consumer needing either call before a stdlib
wrapper lands can copy this verbatim — the important detail is passing the **named `SYS_*` constant**
rather than an integer, so the arch dispatch stays correct on the cross-build.

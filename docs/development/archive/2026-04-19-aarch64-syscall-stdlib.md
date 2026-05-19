# Proposal: aarch64 Linux syscall table in stdlib

**Status**: accepted (claimed by v5.4.11)
**Date**: 2026-04-19
**Target**: v5.4.11 (was v5.5.x in original draft — pulled in
because yukti is actively broken on aarch64 today and v5.5.x is
months out)
**Affects**: `lib/syscalls.cyr`, every consumer that cross-builds
with `cyrius build --aarch64`

## Summary

Cyrius stdlib `lib/syscalls.cyr` is **explicitly Linux x86_64**
(file header: `# syscalls.cyr — Linux x86_64 syscall wrappers`).
The `SysNr` enum hardcodes x86_64 numbers (`SYS_OPEN = 2`,
`SYS_CLOSE = 3`, `SYS_STAT = 4`, `SYS_IOCTL = 16`,
`SYS_MKDIR = 83`, `SYS_UNLINK = 87`, `SYS_MOUNT = 165`, …).

aarch64 Linux uses the generic syscall table
(`include/uapi/asm-generic/unistd.h`), which is **completely
different**: `openat = 56`, `close = 57`, `newfstatat = 79`
(no `stat`), `ioctl = 29`, `mkdirat = 34`, `unlinkat = 35`,
`mount = 40`. Cross-built binaries today include the x86_64
enum verbatim, so every `SYS_*` lookup on real aarch64 hardware
hits the wrong kernel entry point.

**This is not hypothetical**: yukti 2.1.0 cross-builds clean
under 5.4.8, passes `core_smoke` on real Pi 4, but the test
binary `yukti-test-aarch64` segfaults at
`test_query_permissions_dev_null` because `syscall(4, path, &buf)`
invokes `pivot_root` on aarch64 instead of `stat`. Full evidence
and per-call-site audit in
[yukti docs/development/issues/2026-04-19-aarch64-syscall-portability.md](../../../yukti/docs/development/issues/2026-04-19-aarch64-syscall-portability.md)
(relative path from this file to the yukti repo root).

Every first-party consumer of `lib/syscalls.cyr` has the same
gap: sigil, sakshi, libro, agnosys, mabda, and any future
project that uses `syscall(SYS_OPEN, …)` idioms. The fix
therefore belongs in stdlib, not in each consumer.

## Non-goal

Do **not** turn `cc5_aarch64` into a Linux-syscall-number
translator. Evidence from the yukti test run shows the compiler
already translates a subset (`syscall(1, …)` and `syscall(60, …)`
work on aarch64 output — `main.cyr`'s `write` + `exit` calls
ran cleanly on the Pi), but the translation is incomplete and
opaque. Expanding that table further hides the platform dispatch
inside the code emitter. The stdlib is the honest seam.

Related cleanup (out of scope for this proposal but follow-up):
audit `src/frontend/parse.cyr` syscall rerouting to either
(a) cover the full Linux table deterministically, or (b) remove
the subset translation entirely and require consumers to go
through `lib/syscalls*`.

## Existing patterns to reuse

Cyrius already has a per-platform syscalls layout. No new
infrastructure is needed:

- **`lib/syscalls_macos.cyr`** — BSD numbers with the `0x2000000`
  Mach-O prefix; sibling of `syscalls.cyr`.
- **`lib/syscalls_windows.cyr`** — queued for v5.4.9+; PE-kernel32
  IAT wrappers. Already on the roadmap.
- **`#ifdef CYRIUS_ARCH_{X86,AARCH64}`** — compile-time arch
  guards shipping since v5.3.16; used throughout
  `src/frontend/parse.cyr` and `src/backend/`.
- **`src/main_aarch64_native.cyr`** — hand-rolled aarch64
  numbers for the compiler's own bootstrap (`read=63, write=64,
  openat=56, close=57, brk=214, exit=93`). Authoritative local
  source for the aarch64 column.

## Design

### 1. New file: `lib/syscalls_aarch64_linux.cyr`

Mirrors `lib/syscalls.cyr`'s structure but with aarch64
generic-table numbers. Same enum identifier names — every
consumer's `SYS_OPEN`, `SYS_CLOSE`, … resolves transparently.

```cyr
# syscalls_aarch64_linux.cyr — Linux aarch64 syscall wrappers
# Peer of syscalls.cyr; same identifiers, aarch64 generic numbers.

enum SysNr {
    SYS_READ        = 63;
    SYS_WRITE       = 64;
    SYS_OPENAT      = 56;   # aarch64 has no bare `open`
    SYS_CLOSE       = 57;
    SYS_NEWFSTATAT  = 79;   # aarch64 has no bare `stat`/`lstat`/`fstat`
    SYS_FSTAT       = 80;
    SYS_LSEEK       = 62;
    SYS_MMAP        = 222;
    SYS_BRK         = 214;
    SYS_IOCTL       = 29;
    SYS_PIPE2       = 59;   # aarch64 has no `pipe`; pipe2 only
    SYS_FCNTL       = 25;
    SYS_GETCWD      = 17;
    SYS_CHDIR       = 49;
    SYS_MKDIRAT     = 34;
    SYS_UNLINKAT    = 35;   # also covers rmdir with AT_REMOVEDIR
    SYS_FCHMODAT    = 53;
    SYS_GETUID      = 174;
    SYS_GETGID      = 176;
    SYS_SETUID      = 146;
    SYS_SETGID      = 144;
    SYS_GETEUID     = 175;
    SYS_GETEGID     = 177;
    SYS_GETPPID     = 173;
    SYS_SETSID      = 157;
    SYS_CLOCK_GETTIME = 113;
    SYS_NANOSLEEP   = 101;
    SYS_MOUNT       = 40;
    SYS_UMOUNT2     = 39;
    SYS_SOCKET      = 198;
    SYS_CONNECT     = 203;
    SYS_BIND        = 200;
    SYS_LISTEN      = 201;
    SYS_ACCEPT      = 202;
    SYS_SENDTO      = 206;
    SYS_RECVFROM    = 207;
    SYS_SETSOCKOPT  = 208;
    SYS_GETSOCKOPT  = 209;
    SYS_PPOLL       = 73;   # aarch64 has no `poll`; ppoll only
    SYS_SYNC        = 81;
    SYS_FORK        = 220;  # clone(CLONE_CHILD|SIGCHLD, 0) — see below
    SYS_EXECVE      = 221;
    SYS_WAIT4       = 260;
    SYS_KILL        = 129;
    SYS_UNAME       = 160;
    SYS_EXIT        = 93;
}
```

Wrappers (`sys_open`, `sys_stat`, `sys_mkdir`, `sys_rmdir`,
`sys_unlink`, `sys_poll`, `sys_pipe`, `sys_fork`) that today
call x86-only numbers must be re-implemented in terms of the
at-family equivalents with `AT_FDCWD = -100`:

```cyr
fn sys_stat(path_cstr, buf_ptr) {
    return syscall(SYS_NEWFSTATAT, 0 - 100, path_cstr, buf_ptr, 0);
}
fn sys_open(path_cstr, flags, mode) {
    return syscall(SYS_OPENAT, 0 - 100, path_cstr, flags, mode);
}
fn sys_mkdir(path_cstr, mode) {
    return syscall(SYS_MKDIRAT, 0 - 100, path_cstr, mode);
}
fn sys_rmdir(path_cstr) {
    return syscall(SYS_UNLINKAT, 0 - 100, path_cstr, 512);  # AT_REMOVEDIR
}
fn sys_unlink(path_cstr) {
    return syscall(SYS_UNLINKAT, 0 - 100, path_cstr, 0);
}
fn sys_poll(pfd_ptr, nfds, timeout_ms) {
    # aarch64 wants ppoll (struct timespec); translate from ms.
    var ts_sec = timeout_ms / 1000;
    var ts_nsec = (timeout_ms % 1000) * 1000000;
    var ts[16]; store64(&ts, ts_sec); store64(&ts + 8, ts_nsec);
    return syscall(SYS_PPOLL, pfd_ptr, nfds, &ts, 0, 8);
}
```

### 2. `lib/syscalls.cyr` becomes an arch selector

Cyrius preprocessor uses bare `include "..."` (no `#`) for file
inclusion; `#ifdef` / `#endif` are the conditional-compilation
directives. So the selector reads:

```cyr
# syscalls.cyr — Linux syscall wrappers (arch-dispatched)
# Selects the right per-arch peer based on CYRIUS_ARCH_*.

#ifdef CYRIUS_ARCH_AARCH64
include "lib/syscalls_aarch64_linux.cyr"
#endif
#ifdef CYRIUS_ARCH_X86
include "lib/syscalls_x86_64_linux.cyr"
#endif
```

(Two-arm `#ifdef` rather than `#ifdef`/`#else` matches the
existing pattern in `lib/fnptr.cyr`, which is the only other
file in the tree using `#ifdef CYRIUS_ARCH_*` today. If
`#else` works, collapse — but verify against the preprocessor
implementation in `src/frontend/lex.cyr` first.)

The existing x86_64 content moves verbatim into
`lib/syscalls_x86_64_linux.cyr`, preserving all identifiers and
wrapper shapes. Net diff: mechanical rename + one new selector
stub + one new aarch64 peer.

### 3. `struct stat` layout helper

x86_64 `stat(2)` returns a 144-byte struct with `st_mode` at
offset 24; aarch64 `newfstatat(2)` returns the generic kernel
layout (`include/uapi/asm-generic/stat.h`) with `st_mode` at
offset 16, `st_uid` at 20, `st_gid` at 24.

**Decision to make at implementation time:** keep both arches'
native layouts and arch-dispatch the offset constants (the
proposal's original design, below) **OR** route x86_64 through
`newfstatat` too so both arches share the generic-stat layout
and the offsets become arch-independent. Vote: route both
through `newfstatat` for consistency — slightly more syscall
args per call, much smaller cognitive surface for stdlib
maintainers. Decide after auditing yukti's `device.cyr:157-159`
and `storage.cyr:568` for any latent dependence on the 144-byte
layout's specific fields.

If we keep arch-dispatched offsets:

```cyr
#ifdef CYRIUS_ARCH_AARCH64
enum Stat {
    STAT_MODE = 16;
    STAT_UID  = 20;
    STAT_GID  = 24;
    STAT_SIZE = 48;
}
#endif
#ifdef CYRIUS_ARCH_X86
enum Stat {
    STAT_MODE = 24;
    STAT_UID  = 28;
    STAT_GID  = 32;
    STAT_SIZE = 48;
}
#endif
```

yukti's `device.cyr:157-159` and `storage.cyr:568` are the
first consumers that would break on the layout change; the fix
in yukti becomes "replace `&buf + 24` with `&buf + STAT_MODE`"
once this proposal lands.

### 4. `sys_fstat` on aarch64

aarch64 doesn't expose a bare `fstat`. The closest equivalent
is `fstatat(fd, "", buf, AT_EMPTY_PATH)` (modern Linux ≥ 2.6.39,
which every aarch64 build target satisfies). Wrapper:

```cyr
fn sys_fstat(fd, buf_ptr) {
    var empty[1]; store8(&empty, 0);
    return syscall(SYS_NEWFSTATAT, fd, &empty, buf_ptr, 0x1000);  # AT_EMPTY_PATH
}
```

Or — if we go the consistency route from §3 — both arches use
the same `fstatat` form, no per-arch wrapper needed. Same
decision point.

## Acceptance criteria

1. **Build gate**: `cyrius build --aarch64 lib/syscalls.cyr
   /tmp/null` compiles clean on both x86_64 host and aarch64
   native.
2. **Test gate**: every `.tcyr` suite in stdlib and `regression.tcyr`
   passes when cross-built with `--aarch64` and run on real Pi.
   Currently unverified territory for any test that touches
   filesystem / sockets.
3. **yukti gate**: `scripts/retest-aarch64.sh pi` in the yukti
   repo runs every target to exit 0, including
   `yukti-test-aarch64` (the current regression).
4. **Downstream gate**: sigil, sakshi, libro, agnosys all
   cross-build clean against the new stdlib and exit 0 on a
   trivial smoke target when run on the Pi.
5. **Closeout**: `lib/syscalls.cyr` header no longer says
   "Linux x86_64" — it says "Linux (arch-dispatched)".

## Migration path for consumers

No source changes required in consumers that already go through
the `SYS_*` enum — identifier names stay identical, values
become arch-dependent. Consumers with **bare-literal**
`syscall(N, …)` sites (yukti's `device.cyr:154`,
`storage.cyr:126,361,557,596,612,633,656`, etc.) must migrate
to the enum as part of their own portability work; that's a
yukti-local follow-up tracked separately.

## Rollout

Originally drafted for "v5.4.10+ behind a feature flag" then
"v5.5.0 flip default" — collapsed into a single v5.4.11 patch
because:
- `#ifdef CYRIUS_ARCH_AARCH64` already *is* the gate; no
  feature flag needed. x86 builds stay byte-identical because
  the new `lib/syscalls.cyr` selector delegates to a renamed
  `lib/syscalls_x86_64_linux.cyr` carrying today's verbatim
  content.
- Yukti is actively broken on aarch64 today; v5.5.x is months
  out. The honest rollout matches the urgency.

- **v5.4.11**: land the new `lib/syscalls_aarch64_linux.cyr`
  peer + the selector stub in `lib/syscalls.cyr` + the
  arch-dispatched `Stat` enum (or, per §3 decision, the
  consistency-routed unified layout). x86 path stays
  byte-identical; aarch64 cross-builds finally hit the right
  kernel entry points.
- **Downstream pin bumps land at downstream's own pace**;
  cyrius CI doesn't re-run downstreams' aarch64 retest scripts
  (keeps cyrius CI hermetic). When a downstream bumps its pin
  to v5.4.11+, its own CI reports green.
- **Documentation**: update `docs/stdlib-reference.md` line 311
  ("Linux x86_64 syscall bindings") and
  `docs/guides/cyrius-guide.md` line 406 in the same patch.

## Risks

- **Wrapper semantic drift**: `sys_open` on aarch64 is really
  `openat(AT_FDCWD, …)`. If any consumer today relies on the
  x86 `open` syscall's *exact* errno surface (e.g., `EFAULT`
  vs. `EBADF` timing), they'll see minor differences. Low risk
  in practice — yukti, sigil, and agnosys already treat
  `sys_open < 0` as "failed, read errno from negated return".
- **`fork` → `clone` translation**: aarch64 has no `fork`.
  Original draft suggested `clone(CLONE_CHILD|SIGCHLD, 0, 0,
  0, 0)` but **`CLONE_CHILD` isn't a Linux clone flag**. The
  POSIX-fork-equivalent is `clone(SIGCHLD, 0, 0, 0, 0)` — the
  bare `SIGCHLD` term tells the kernel to send SIGCHLD to the
  parent on child exit, with no `CLONE_*` bits set so the
  child gets its own VM, files, signal handlers, etc. Verify
  against libro's fork tests; if libro relies on
  copy-on-write semantics, also confirm that's preserved
  (without `CLONE_VM` it should be).
- **`pipe` → `pipe2`**: aarch64 has no `pipe`, only `pipe2`.
  Wrapper passes `flags=0`. Behaviorally identical.
- **Byte-count regression**: `cc5` and `cc5_aarch64` must still
  self-host byte-identical after the stdlib refactor. Covered
  by existing `sh scripts/check.sh` gates.
- **`#ifdef`/`#else` support**: the proposal's selector
  example uses two-arm `#ifdef` rather than `#ifdef`/`#else`
  because the latter is unverified in cyrius's preprocessor.
  If `#else` works (verify against `src/frontend/lex.cyr`
  before landing), collapse the two arms.

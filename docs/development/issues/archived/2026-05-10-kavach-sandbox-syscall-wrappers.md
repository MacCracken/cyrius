# Cyrius: kavach + future sandbox-runtime consumers need stdlib wrappers for the post-fork hardening syscalls

**Filed:** 2026-05-10
**Reporter:** kavach (AGNOS sandbox-execution framework, v3.1.1)
**Cyrius version at time of report:** 5.10.34 (release tarball + source archive)
**Affected stdlib:** `lib/syscalls_x86_64_linux.cyr` + the aarch64 peer
**Severity:** **P1** — see "Severity rationale" below; the rating is the
**reporter's** ask. Real-world blocking-ness is mitigated by raw-syscall
workarounds (kavach 3.1.1 already ships one for `SYS_FCHMOD`), so an
upstream maintainer may legitimately re-rate to P2 if scheduling
pressure is elsewhere.
**Status:** open.

## Summary

Six post-fork-relevant Linux syscalls have no stdlib wrapper in
`syscalls_x86_64_linux.cyr` at cc 5.10.34. Each gates a distinct
kavach hardening feature in the v3.2 backlog. Each is a one-line raw
`syscall(N, ...)` away from working from the consumer side, so
**kavach can ship without these wrappers**; the upstream filing is
about deduplicating raw-syscall surface across the first-party tree
and centralising the async-signal-safe-context review (post-fork
seccomp / prctl / setresuid call sites are pre-execve and have
to be heap-free, mutex-free, tracing-free).

| Syscall | x86_64 nr | aarch64 nr | Kavach feature it gates |
|---|---|---|---|
| `prctl` | 157 | 167 | `seccomp` profile install — needs `PR_SET_NO_NEW_PRIVS` then `SECCOMP_SET_MODE_FILTER` (see `seccomp` row). Post-fork. |
| `seccomp` | 317 | 277 | BPF syscall filter install per `SandboxPolicy.seccomp_profile`. Post-fork, async-signal-safe only. |
| `setresuid` | 117 | 147 | Firecracker jailer UID drop (per-VM dedicated UID/GID). Post-fork. |
| `setresgid` | 119 | 149 | Firecracker jailer GID drop — pairs with setresuid. Post-fork. |
| `execveat` | 322 | 281 | Close ADR-005 §H4 binary-path TOCTOU residual — `which()` resolves to `O_PATH \| O_NOFOLLOW` fd, exec runs against the held fd. The fd has to survive the fork boundary. |
| `fchmod` | 91 | 52 | `FileInjection.mode` honoring — write secret to fd opened `O_CREAT \| O_EXCL \| O_NOFOLLOW` at mode 0600, then chmod the **same fd** before close (no TOCTOU window between write and chmod). **Kavach 3.1.1 ships this with raw `syscall(91, fd, mode, 0)` in `src/util.cyr::file_write_secure_modal`** — see [`kavach/CHANGELOG.md`](https://github.com/MacCracken/kavach/blob/main/CHANGELOG.md) §3.1.1. Folded back to `sys_fchmod` when the wrapper lands. |

## Detail per syscall

### `sys_prctl(option, arg2, arg3, arg4, arg5)`

Five-arg wrapper. Used here to set `PR_SET_NO_NEW_PRIVS` (option = 38)
ahead of `sys_seccomp` install. Linux mandates the NO_NEW_PRIVS bit
be set or `seccomp(2)` requires `CAP_SYS_ADMIN`. Always called
post-fork, pre-execve. **Async-signal-safe**: no heap, no mutex,
no logging.

```cyrius
fn sys_prctl(option, arg2, arg3, arg4, arg5) {
    return syscall(157, option, arg2, arg3, arg4, arg5);
}
```

### `sys_seccomp(op, flags, args)`

Three-arg wrapper. `op` is typically `SECCOMP_SET_MODE_FILTER` (1),
`flags` carries `SECCOMP_FILTER_FLAG_*` bits (TSYNC = 1, LOG = 2,
SPEC_ALLOW = 4), `args` is a pointer to a `struct sock_fprog`
(filter length + program pointer). Kavach builds the BPF program
in-kavach (~700 lines from rust-old/src/seccomp_profiles.rs — the
syscall allowlist per "strict" / "basic" profile); the wrapper is
just the kernel-entry plumbing. **Async-signal-safe.**

```cyrius
fn sys_seccomp(op, flags, args_ptr) {
    return syscall(317, op, flags, args_ptr);
}
```

### `sys_setresuid(ruid, euid, suid)` + `sys_setresgid(rgid, egid, sgid)`

Three-arg each. Firecracker jailer pattern: pre-execve, drop from the
kavach UID to a per-VM dedicated UID/GID for defense-in-depth.
Setresuid + setresgid in that order (gid first per the standard
order-of-ops Linux examples). **Async-signal-safe.**

```cyrius
fn sys_setresuid(ruid, euid, suid) {
    return syscall(117, ruid, euid, suid);
}
fn sys_setresgid(rgid, egid, sgid) {
    return syscall(119, rgid, egid, sgid);
}
```

### `sys_execveat(dirfd, pathname, argv, envp, flags)`

Five-arg wrapper. Critical bit: `flags = AT_EMPTY_PATH | AT_SYMLINK_NOFOLLOW`
(0x1000 | 0x100 = 0x1100) lets the caller pass a held fd as `dirfd` with
an empty pathname, so the exec runs against the file referenced by the
held fd rather than re-resolving a path. Closes the H4 TOCTOU class:
`which("ls")` opens `/usr/bin/ls` with `O_PATH | O_NOFOLLOW`, the fd is
held across fork (CLOEXEC must be cleared in the child), the child
`execveat`s that fd. An attacker swapping `/usr/bin/ls` between `which()`
and exec doesn't help — the child exec'd the held fd, not the path.
**Async-signal-safe** (the path resolution happened pre-fork via `sys_open`).

```cyrius
fn sys_execveat(dirfd, pathname, argv_ptr, envp_ptr, flags) {
    return syscall(322, dirfd, pathname, argv_ptr, envp_ptr, flags);
}
```

### `sys_fchmod(fd, mode)`

Two-arg wrapper. Kavach 3.1.1's `credential_inject_files` is the
forcing function: secret files are created `O_CREAT|O_EXCL|O_NOFOLLOW`
at mode 0600 (no other-readable window during write), then the fd is
fchmod'd to the caller-requested final mode before close. Doing
`sys_chmod(path, mode)` after `sys_close(fd)` would re-open a brief
window where an attacker who owns the directory could `rename()` swap
our file between close and chmod — fchmod-on-same-fd closes that window.

```cyrius
fn sys_fchmod(fd, mode) {
    return syscall(91, fd, mode, 0);  # third arg is the syscall(...) trailer
}
```

## Severity rationale

The reporter (kavach) rates this **P1** because every row above gates a
specific hardening feature in kavach's v3.2 work arc, and the
async-signal-safe-after-fork audit is a class of correctness review
that benefits from being done once in the stdlib rather than per
downstream.

The honest counter-case: **kavach can ship without these wrappers.**
Raw `syscall(N, ...)` calls work today and v3.1.1 has set the
precedent (SYS_FCHMOD shipped as a raw syscall, with a SAFETY-comment
naming the invariant). An upstream maintainer prioritising elsewhere
can legitimately re-rate to **P2** — the rating reflects "we want this
upstreamed", not "we cannot ship without it".

aarch64 numbers are listed for completeness; kavach is x86_64-only in
CI today and the aarch64 cross-build is itself blocked by the agnosys
`SYS_OPEN` portability item (already on majra's roadmap).

## Downstream impact

Today **kavach is the only consumer** filing this — but the surface
is a generic Linux-sandbox-runtime surface. Future consumers
(stiva when its Cyrius port lands; any AGNOS-side container runtime;
any first-party tool that needs to drop privs / install seccomp /
close exec TOCTOU) will hit the same wall. Filing now keeps the
stdlib-syscall additions in front of the curve rather than chasing
multiple downstream raw-syscall copies.

## Suggested placement

The cyrius v5.10.x arc is currently bug-fix + small-stdlib-addition
shaped. Each wrapper is ~3 lines + an aarch64 peer line. A single
patch landing the six wrappers fits the v5.10.x shape; no parser /
codegen work involved. The async-signal-safe contract should be
documented in the wrappers' comments so consumers don't re-prove it.

A reasonable order — landed in priority sequence — would be:
**fchmod** (closes kavach 3.1.1's existing raw-syscall workaround,
zero additional kavach work needed) → **prctl + seccomp** (unblocks
the seccomp v3.2 feature, the largest in-tree kavach work) →
**setresuid + setresgid** (Firecracker jailer) → **execveat**
(H4 TOCTOU, lowest priority — H1-H3 already prevent dominant attack
class per ADR-005).

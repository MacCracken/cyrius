# `lib/syscalls_x86_64_agnos.cyr` has no `sys_fork`#96 peer

**Status:** 🟡 **OPEN** — one enum entry and one no-argument wrapper. Additive; nothing existing changes.
**Placement:** `lib/syscalls_x86_64_agnos.cyr` — the `SysNrAgnos` enum plus a `sys_fork()` beside the
existing process calls. `sys_getpid`#2 is the closest shape (no arguments, i64 return).
**Filed:** 2026-08-30, by agnos. agnos minted and built the number; cyrius owns the peer.
**Affects:** cyrius **6.5.36**. `#96` exists as of agnos 1.56.55.
**Severity:** **Low as a defect, blocking for the consumer.** Ring 3 can call it by raw number today.

## The ask

```
SYS_FORK = 96
fn sys_fork(): i64 { return syscall(SYS_FORK); }
```

Returns the **child's pid** to the parent and **0** to the child, or -1 on failure — the POSIX shape.

⚠ agnos's `waitpid`#4 gained **wait-any** in the same cut: `sys_waitpid(-1)` returns a finished
child's exit code, **-2** while children are still running, and **-1** when there are none. A
fork-per-connection loop wants that, not the single-pid poll.

## Why it exists

`agora`, the telnet BBS, is fork-per-connection — `agora/src/main.cyr` calls `sys_fork()` — and could
not serve a second connection on agnos at all. The kernel side is now built and gated
(`scripts/smoke/fork-smoke.sh` in the agnos arc sweep): a real ring-3 program forks, the child resumes
at the parent's post-SYSCALL RIP with `rax == 0`, gets a **private copy** of the parent's address
space (full copy — agnos has no CoW write-fault path), and the parent reaps it with `waitpid(-1)`.

⚠ **One agnos-side constraint worth knowing before writing a consumer**: a process running as a
foreground `exec_and_wait` child runs with IF=0 and is not preempted, so its forked child does not run
until the foreground run ends. fork is for processes running under the scheduler — i.e. spawned via
`spawn_path`#43 — which is how a server like agora runs anyway.

## Compatibility

None to consider. A new enum constant and a new function; no existing number, signature or behaviour
is touched.

## Related

- agnos `docs/development/agnos-userland-abi.md` — the authoritative contract for the number.
- `2026-08-30-agnos-sys-lstat-102-peer.md` — the other agnos peer outstanding in this folder.

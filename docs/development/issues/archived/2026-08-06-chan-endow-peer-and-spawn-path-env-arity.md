# `lib/syscalls_x86_64_agnos.cyr` — `CH_ENDOW` is missing, and `sys_spawn_path` exposes 2 of the 4 arguments `#43` accepts

**Status:** ✅ **SHIPPED v6.5.9** — CH_ENDOW=0x05 + sys_chan_endow (returns an FD, per the kernel's ARM at syscall.cyr:7898 — its enum comment at :4588 still says '-> 0' and is stale) and sys_spawn_path_env, keeping the 2-arg form. Gated in tests/syscall_wrapper_pass.sh axis 5.
**Filed as:** 
Filed 2026-08-06 from the agnos 1.56.40 channel-band cutover.
**Placement:** unpinned; ~4 lines total. Item 1's kernel arm already shipped, so it is mintable now.
**Severity:** Medium — nothing in cyrius is *wrong*; two things are absent, and a consumer cannot
proceed without either.
**Affects:** cycc 6.5.8 and earlier.
**Filed from:** agnos. Related — [`2026-08-05-syscall-97-chan-op.md`](https://github.com/MacCracken/agnos/blob/main/docs/development/issues/2026-08-05-syscall-97-chan-op.md).

⭐ 6.5.8's `#97` peer is otherwise complete and correct — `SYS_CHAN_OP` plus `sys_chan_caps` / `_mint` /
`_send` / `_recv` / `_close` all match the kernel exactly, ops and error codes included. setu's agnos
client cut over onto it with no friction. These are the two remaining gaps.

## 1. `CH_ENDOW = 0x05` + `sys_chan_endow(fd)` — the op landed after 6.5.8 shipped

agnos **1.56.40** added `CH_ENDOW` (bite 5): a parent arms a channel endpoint, and the next
`spawn_path #43` child is **born owning it**. That is what makes the band's authority model usable
rather than merely safe — an inherited fd is inert by construction, so without endowment a child could
never hold a channel at all.

```cyrius
    CH_ENDOW  = 0x05;   # (fd) → the fd index the CHILD will hold, or negative CH_E_*
```
```cyrius
# Arm `fd`'s endpoint for placement into the next spawn_path#43 child. Returns the fd index the child
# will receive — the parent announces it (see item 2); the child never searches for it.
fn sys_chan_endow(fd): i64 { return syscall(SYS_CHAN_OP, CH_ENDOW, fd); }
```

⚠ **It returns an fd, not 0.** The number is decided at ARM time because the kernel cannot announce it
itself: `elf_load_from_file` bakes the child's env into its init stack at `elf.cyr:417-451` and creates
the proc at `:473`, so by the time placement happens the env is already written.

⚠ `CH_OP_SUPPORTED` is now `0x3F` (bits 0-5). A client that negotiates on the mask will see bit 5 set on
a 1.56.40 kernel; the peer having no name for it is the gap.

## 2. `sys_spawn_path` drops the env arguments `#43` has accepted since 1.44.19

```cyrius
fn sys_spawn_path(path, len): i64 { return syscall(SYS_SPAWN_PATH, path, len); }   # today
```

The agnos ABI table for `#43` is:

| # | Name | a1 | a2 | a3 | a4 |
|---|---|---|---|---|---|
| 43 | `spawn_path` | path | pathlen (≤127) | **env blob (opt, 1.44.19)** | **env len (a4=r10)** |

So the wrapper reaches two of four. **This is exactly what bite 7 needs**: the compositor must pass
`AGNOS_CHAN=<fd>` to each client it spawns — Wayland's `WAYLAND_SOCKET` shape, where the parent decides
the number and the child reads it out of its environment rather than searching for a channel it was not
given. setu 0.8.0's client already reads it (`getenv("AGNOS_CHAN")`, no scan fallback by design).

Suggested, keeping the existing 2-arg form for every current caller:

```cyrius
# spawn_path with a per-process env blob (packed "KEY=VALUE\0…", ≤1024 B, ≤16 entries — the kernel
# stages it onto the child's init stack). The 2-arg form above is this with env = 0.
fn sys_spawn_path_env(path, len, env, envlen): i64 {
    return syscall(SYS_SPAWN_PATH, path, len, env, envlen);
}
```

⚠ The kernel treats a garbage `a3`/`a4` as **fallback-to-default-env, never an error**, so an
accidentally-wrong call degrades quietly rather than failing — which is an argument for the wrapper
existing, not against it.

## Why the consumer is not routing around this

agnos could call `syscall(SYS_SPAWN_PATH, path, len, env, envlen)` directly — the *number* is the named
constant and only the arity differs, so this is not the raw-number defect class. It is still worth the
wrapper: this ecosystem has a confirmed history of raw syscall arity/number mistakes compiling clean and
mis-dispatching (jalwa: `poll`(7) → `open` **per frame**, `read`(0) → `exit`), and agnos's
`syscall-abi-check.sh` gate exists because of it. Two named wrappers cost four lines and remove the
temptation permanently.

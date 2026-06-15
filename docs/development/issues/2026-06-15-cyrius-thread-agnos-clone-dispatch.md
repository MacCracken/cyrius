# 2026-06-15 — AGNOS full-build cascade: stale vendored stdlib snapshot + `lib/async.cyr` epoll gap

> **CORRECTION NOTICE.** An earlier draft of this file claimed the agnos
> build failure was an *unfixed upstream `lib/thread.cyr` defect*. An
> adversarial verification pass proved that **wrong** on two counts: (1) the
> `thread.cyr` AGNOS dispatch is **already fixed in the cyrius 6.2.6
> toolchain** — the failure was sandhi's **stale vendored `./lib` snapshot**;
> and (2) `thread.cyr` is not the only blocker — fixing it exposes the **next**
> gap (`lib/async.cyr`'s raw `SYS_EPOLL_CREATE1`), so a full `--agnos` build is
> a **cascade**, not a single issue. This file is rewritten to reflect that.

**Status**: Open — **upstream cyrius** (stdlib agnos-completeness). The real
first blocker is `lib/async.cyr`'s raw `SYS_EPOLL_CREATE1` (§2); a stale local
`./lib` can surface a `thread.cyr` `CLONE_VM` error first but that is already
fixed in the 6.2.6 toolchain and clears on a clean `cyrius deps` (§1 — not real
work). Affects only a full `cyrius build --agnos` of a sandhi consumer; x86_64 /
macOS / Windows unaffected and authoritative.
**Filed**: sandhi side, against the cyrius repo.
**Sandhi-side surface**: per ADR 0001 / CLAUDE.md "No FFI", sandhi neither
forks stdlib modules nor defines syscall numbers. The only sandhi-side touch is
`rm -rf lib && cyrius deps` on a stale tree (§1); the substantive work is a
cyrius-side stdlib agnos-completeness pass.

## How this was discovered (and why the earlier framing was wrong)

The agnos build reports `error:lib/mmap.cyr:184: undefined variable
'CLONE_VM'`. `mmap.cyr` has no `CLONE_VM` — the position is a single-pass
include-offset artifact (`thread.cyr` includes `mmap.cyr`; the real token is
`thread.cyr:199`). The first investigation stopped there and filed it as an
unfixed upstream `thread.cyr` defect. A sentinel probe then proved the build
consumes the **vendored** `./lib/thread.cyr` (Jun-12 snapshot), and a diff
showed the **toolchain** `~/.cyrius/lib/thread.cyr` (6.2.6, Jun-14) **already
routes AGNOS** to a `thread_agnos.cyr` peer:

```
#ifdef CYRIUS_TARGET_WIN
include "lib/thread_win.cyr"
#endif
#ifdef CYRIUS_TARGET_AGNOS
include "lib/thread_agnos.cyr"     # <-- present in 6.2.6 toolchain; absent from sandhi's ./lib
#endif
#ifndef CYRIUS_TARGET_WIN
#ifndef CYRIUS_TARGET_AGNOS
... clone(2) body (CLONE_VM | …) ...
#endif
#endif
```

Copying the toolchain `thread.cyr` + `thread_agnos.cyr` into `./lib` **clears
the `CLONE_VM` error** and the build advances — confirming `thread.cyr` is a
**stale-vendoring** problem, not an upstream defect.

## The two layers

### (1) Transient — a stale vendored `./lib` (clean `cyrius deps` fixes it)

This layer is **NOT a real project blocker** — it only appears in a working
tree whose `./lib` was resolved before the toolchain shipped the `thread.cyr`
agnos fix. A **clean re-resolve fixes it**: `rm -rf lib && cyrius deps` pulls
the 6.2.6 toolchain's `thread.cyr` (with `#ifdef CYRIUS_TARGET_AGNOS → include
thread_agnos.cyr`) **and** `thread_agnos.cyr` — verified, the `CLONE_VM` error
then disappears (0 occurrences). The gotcha is only that plain `cyrius deps`
is a **no-op** when `./lib` + the lockfile already exist, so a long-lived
working tree silently keeps the stale copy after a toolchain bump. A fresh
clone is unaffected. The x86_64 authoritative build is byte-identical across
the refresh, so this never touched a release. **In short: not an upstream
defect and not real sandhi-side work — just `rm -rf lib && cyrius deps` on a
stale tree.** The earlier "`mmap` stub" and "unfixed upstream `thread.cyr`
defect" framings were both chasing this transient artifact.

### (2) Upstream cyrius — `lib/async.cyr` uses raw `SYS_EPOLL_CREATE1`

With `thread.cyr` refreshed, the next agnos-compile error is:

```
error:lib/async.cyr:50: undefined variable 'SYS_EPOLL_CREATE1'
```

`async.cyr` calls `syscall(SYS_EPOLL_CREATE1, 0)` directly at lines 50 + 143.
The agnos syscall table **does** provide epoll — `SYS_EPOLL_CREATE = 19`,
`SYS_EPOLL_CTL = 20`, `SYS_EPOLL_WAIT = 21`, plus the portable wrappers
`sys_epoll_create()` / `sys_epoll_ctl()` / `sys_epoll_wait()` — but **not**
the `epoll_create1` variant (`SYS_EPOLL_CREATE1`). This is a **genuine current
gap** (identical in the 6.2.6 toolchain and the vendored copy, so not
stale-vendoring): `async.cyr` should compose the portable `sys_epoll_create`
wrapper rather than the raw `SYS_EPOLL_CREATE1` symbol. (`async` is the
server-path dep — `sandhi_server_run_async`; agnos inbound TCP is Phase B and
sit is a client — so async functionality is unused on agnos, but the bundle
still has to **compile** it.)

## Why this matters / scope honesty

A full `--agnos` build is a **cascade** of stdlib agnos-compile gaps surfaced
one at a time (thread → async → …; further layers not yet enumerated). It is
the wrong shape for a single point-fix. The realistic resolution is a
**systematic stdlib agnos-completeness pass** on the cyrius side, plus a
sandhi-side dep-snapshot refresh. **None of this gates sandhi's authoritative
artifacts** (x86_64 binary, `.tcyr` suite, `dist/sandhi.cyr`) — those are
green on 6.2.6. sandhi's own AGNOS transport surface (socket syscalls + DNS
entropy) was completed sandhi-side at 1.5.1 / 1.5.2 (Batch C1 / C2). The full
agnos *consumer* build (sit) needs the cascade resolved.

## Resolution path

- **sandhi-side**: establish a vendored-stdlib refresh so `./lib` tracks the
  pinned toolchain (gets the fixed `thread.cyr` + `thread_agnos.cyr`).
- **cyrius-side**: `lib/async.cyr` — use `sys_epoll_create` instead of raw
  `SYS_EPOLL_CREATE1` (and audit `async.cyr` / other stdlib server modules for
  the rest of the cascade as part of an agnos-completeness pass).

## Log

- **2026-06-15** — filed at sandhi 1.5.3 close on cyrius 6.2.6. First draft
  mis-framed this as an unfixed upstream `thread.cyr` defect; corrected after
  an adversarial verification pass proved `thread.cyr` is fixed-in-toolchain /
  stale-vendored and that `async.cyr`'s `SYS_EPOLL_CREATE1` is the next
  cascade layer. Earlier sandhi 1.5.1 / 1.5.2 notes that called this the
  "`mmap` `CLONE_VM` stub" are superseded by this file.

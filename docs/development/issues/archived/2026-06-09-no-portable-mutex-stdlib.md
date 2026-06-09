# cyrius stdlib — no portable cross-platform mutex primitive — RESOLVED (v6.1.16)

> **RESOLVED v6.1.16.** Added `lib/sync.cyr`, a portable process-internal mutex
> (`mutex_new` / `mutex_lock` / `mutex_unlock`) decoupled from `thread.cyr`'s
> spawn machinery, selected per-OS like `alloc.cyr`: Linux/aarch64 = SYS_FUTEX
> (blocking); Windows = SRWLOCK (`lib/sync_windows.cyr`); macOS = `atomic_cas`
> spinlock (`lib/sync_macos.cyr`, since macOS has no routed `__ulock`/`os_unfair_lock`
> primitive yet). Documented acquire/release ordering contract. Verified on all
> four targets (Linux x86, aarch64/qemu, Windows/cass, macOS/ecb) via
> `tests/tcyr/sync.tcyr`. No trylock (Windows lacks a routed TryAcquire) and the
> macOS lock spins pending `__ulock` backend routing — both noted as follow-ons.

**Filed:** 2026-06-09 (during patra v1.11.0 thread-safety P1 work)
**Cyrius version observed:** 6.1.15
**Tool at fault:** stdlib — `lib/thread.cyr` (mutex), `lib/atomic.cyr`, the
per-platform `syscalls_*` futex constants
**Severity:** LOW for patra (Linux x86_64 primary + aarch64 best-effort; both
covered). Potentially MEDIUM for any first-party library that must compile on
Windows and wants an internal lock.

## Summary

patra v1.11.0 needed a process-internal mutex to make a shared db handle
thread-safe (the SQL parse/exec scratch is process-global). The only stdlib
mutex is `lib/thread.cyr`'s futex-based `mutex_new` / `mutex_lock` /
`mutex_unlock`, built on `atomic_cas` (`lib/atomic.cyr`) + `SYS_FUTEX`
(`FUTEX_WAIT` / `FUTEX_WAKE` / `FUTEX_PRIVATE_FLAG`).

That works on patra's targets — `SYS_FUTEX` is defined for both
`syscalls_x86_64_linux.cyr` (202) and `syscalls_aarch64_linux.cyr` (98), and
`atomic.cyr` carries x86_64 + aarch64 asm branches — so patra cross-builds
clean on both. **But there is no portable, OS-agnostic mutex abstraction in
the stdlib**, and the existing one is explicitly Linux/futex-shaped:

- `lib/thread.cyr`'s own header note (v6.0.53) says: *"Win32 has no
  clone/futex — the Linux thread body below (SYS_CLONE + CLONE_* + futex +
  hand-assembled trampolines) can't even parse under [Win32]."* So a consumer
  that `include`s `thread.cyr` to get its mutex cannot build for Windows at
  all — the threading machinery in the same file fails to parse.
- `lib/thread_win.cyr` exists as a *separate* file with its own
  `thread_create` etc., implying threads are meant to be selected per-platform
  by the consumer — but there is no equivalent "portable mutex" surface, and
  no documented story for "I just want a lock that compiles everywhere."
- `lib/syscalls_windows.cyr` / `syscalls_macos.cyr`: macOS reuses the Linux
  futex numbers (202) which is almost certainly wrong on Darwin (no Linux
  futex syscall there); Windows has no futex at all.

So a first-party library author who wants an internal mutex today must either
(a) depend on `atomic` + raw futex syscalls (what patra did — Linux/aarch64
only), or (b) hand-roll a per-platform lock behind their own `#if`-style
selection (cyrius has no preprocessor; this means separate files + manifest
juggling). Neither is a clean "portable mutex" the way `alloc` / `io` are
portable.

## What patra did (workaround, not a fix)

patra implements its own 8-byte futex mutex inline in `src/lib.cyr`
(`_patra_mtx` + `_patra_lock` / `_patra_unlock`), mirroring `thread.cyr`'s
2-state scheme, and adds `"atomic"` to `[deps].stdlib`. We deliberately did
**not** pull in all of `thread.cyr` (clone/channel/trampoline machinery,
binary bloat, the Win32 parse problem). This is fine for patra because
Windows is not a patra target. Logged here only because the language /
stdlib agent asked to hear about missing Windows specifics.

## Suggested fix (for the cyrius/stdlib agent)

A small portable-sync module, e.g. `lib/sync.cyr`, exposing
`mutex_new` / `mutex_lock` / `mutex_unlock` (and ideally `once` / rwlock)
that:

- compiles on Linux (futex), macOS (`os_unfair_lock` / `__ulock`), and
  Windows (`SRWLOCK` / `WaitOnAddress`), selected the same way `alloc.cyr`
  vs `alloc_windows.cyr` / `alloc_macos.cyr` already are;
- carries **only** the lock, with no dependency on the thread-spawn
  machinery that can't parse under Win32 (decouple "I want a lock" from
  "I want to clone threads");
- documents a stated memory-ordering contract (acquire on lock, release on
  unlock) so library authors don't re-derive the fence placement.

That would let a library like patra take an internal lock that is correct
and portable without vendoring a Linux-specific primitive.

## Not blocking

patra v1.11.0 ships the inline futex mutex and is correct on its supported
targets (Linux x86_64 + aarch64, both verified). Re-file / escalate only if
a patra consumer ever needs a Windows build of the library.

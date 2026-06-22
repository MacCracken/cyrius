# stdlib `io.cyr` file-lock helpers are `CYRIUS_TARGET_LINUX`-only — no agnos (or macOS) branch

> **RESOLVED v6.2.36 (2026-06-21).** The five helpers now route through the
> v6.2.33 `xflock` wrapper (drops the `CYRIUS_TARGET_LINUX` guard) — fixing agnos
> (#59), macOS (#92), **and** a latent aarch64-Linux bug (raw `syscall(73)` is
> x86-only) in one move; x86-Linux byte-identical. `file_append_locked` keeps
> kernel-atomic `O_APPEND` on Linux/macOS and uses explicit `xlseek` SEEK_END
> under the lock on agnos — premise-checked the agnos kernel does NOT honor
> `AO_APPEND` (`agnos/kernel/core/syscall.cyr:614` "AO_APPEND TODO"), confirming
> the SEEK_END recommendation. New agnos cross-build gate **probe 1g** guards it
> (asserts the helpers are defined + `SYS_FLOCK` #59 emitted; negative-tested).
> All four targets compile the helpers with zero `undefined function`. descent
> picks it up by re-vendoring (`cyrius deps`) at 6.2.36.

**Discovered:** 2026-06-21 (follow-up to the now-archived `archived/2026-06-21-agnos-peer-m6-chain-syscalls.md`; that sweep's peer C1/C2 landed, this is a distinct stdlib-`io` gap)
**Severity:** Medium-High — **runtime blocker** for descent on agnos (traps at boot)
**Affects:** `lib/io.cyr` — the whole file-lock helper group (`io.cyr:242-277`)

## Confirmed: language/stdlib gap, NOT a pin/stale-vendor issue

Verified against the live install (not inferred):
- descent's vendored `lib/io.cyr` is **byte-identical** to `~/.cyrius/versions/6.2.35/lib/io.cyr` (`diff -q` clean) — descent has the genuine latest io.cyr, not a stale copy.
- **6.2.35 is the newest installed cyrius.**
- In that io.cyr, the entire lock group is wrapped in **`#ifdef CYRIUS_TARGET_LINUX`** (line 242) … `#endif` (line 277):

```cyrius
#ifdef CYRIUS_TARGET_LINUX
fn file_lock(fd): i64        { return syscall(73, fd, LOCK_EX); }
fn file_unlock(fd): i64      { return syscall(73, fd, LOCK_UN); }
fn file_trylock(fd): i64     { return syscall(73, fd, LOCK_EX | LOCK_NB); }
fn file_lock_shared(fd): i64 { return syscall(73, fd, LOCK_SH); }
fn file_append_locked(path, buf, len): i64 {
    var fd = file_open(path, O_WRONLY | O_CREAT | O_APPEND, 0x1A4);
    ... file_lock(fd); file_write; file_unlock(fd); file_close(fd) ...
}
#endif
```

So on agnos (and macOS) these five are **undefined** (`syscall(73)` is raw Linux
`flock` anyway). 6.2.35 added agnos branches for `file_open`/`read`/`write`, but
this lock group stayed Linux-only.

## Why it blocks descent at boot (not opt-in)

libro's FileStore audit path calls `file_append_locked` / `file_lock_shared` /
`file_unlock` (`lib/libro.cyr:3742+`). descent's `persist_init()` opens the audit
store **and appends an entry at startup** (`persist.cyr:74,84` → `filestore_append`
→ `file_append_locked`), so the undefined-fn trap-stub fires **at boot, before any
login**. descent's `--agnos` build is otherwise green (1,477,624 B, full M6 chain
compiling via patra 1.12.3 + libro 2.7.7); this lock group is what stands between
that and descent actually running on agnos.

## Fix

Add an agnos branch (and ideally a macOS one — the `#ifdef CYRIUS_TARGET_LINUX`
already leaves macOS uncovered) for the five:

- `file_lock` / `file_lock_shared` / `file_trylock` / `file_unlock` →
  `flock(fd, LOCK_EX|SH|EX\|NB|UN)` via `SYS_FLOCK`#59 (agnos flock: advisory,
  inode-keyed, non-blocking — contended EX returns −1/WOULD_BLOCK, caller poll-spins).
- `file_append_locked` → `file_open` (agnos has no `O_APPEND` in the frozen flag
  set, so `lseek`#58 SEEK_END after open) + lock EX + `file_write` + unlock + close.

A single-process degraded variant is also valid for agnos's single-core model:
lock helpers = no-ops, `file_append_locked` = open + `lseek` SEEK_END + write + close.

## Verification
With these defined for agnos, descent's `--agnos` build drops the three `undefined
function` warnings and `persist_init` no longer trap-stubs — clearing the path to
the QEMU server-socket smoke.

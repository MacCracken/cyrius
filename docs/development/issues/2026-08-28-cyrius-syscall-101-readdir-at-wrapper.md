> ## ✅ SATISFIED in this edit — `SYS_READDIR_AT = 101` + `fn sys_readdir_at(path, buf, max, cursor)`
> are in `lib/syscalls_x86_64_agnos.cyr`, and `tests/gates/platform/syscall_wrapper_pass.sh` axis 5
> asserts both **plus** that `sys_readdir` keeps arity 3. Filed anyway, per the standing rule that an
> agnos↔cyrius syscall is recorded on **both** sides rather than in whichever repo happened to
> notice it.
>
> ⚠ Presence is not compatibility. This was verified by compiling for the agnos target and by the
> gate; nothing here has been exercised against a booted kernel **through the wrapper**. That is the
> lesson `sys_readlink` taught this file — it turned out to take 4 args, not 3.
>
> ⛔ **This ticket exists because it was nearly skipped.** The kernel side shipped and the first
> consumer (crab) was wired with a hand-rolled `syscall(101, …)` and a local constant — which is
> precisely the bug class `#99`'s ticket names: *"Consumers must also not hard-code the number."*
> The standing both-sides rule is what catches this, and it only works if it is followed when the
> work feels like it belongs to the other repo.

# cyrius peer: `SYS_READDIR_AT = 101` + a `sys_readdir_at` wrapper for resumable directory listing

**Status:** ✅ **Built** 2026-08-28 (cyrius 6.5.36).
**Repo owning the design:** agnos — `docs/development/issues/2026-08-28-syscall-101-readdir-at.md`.
**Cross-repo:** filed in **both** repos.
**Severity:** Low for cyrius — two additions, no behaviour change to any existing target.
**Precedent:** identical in shape to `#100 icmp_echo_ex` (6.5.35-era), `#99 proclist` (6.5.35),
`#98 ptrscan` (6.5.13), `#97 chan_op` (6.5.8).

---

## What was added

In `lib/syscalls_x86_64_agnos.cyr`:

1. `SYS_READDIR_AT = 101;` in the agnos `Sys` enum.
2. `fn sys_readdir_at(path, buf, max, cursor)` — a thin wrapper beside `sys_readdir`, same band.

Contract (kernel side; agnos owns it):

```
readdir_at(path, buf, max, cursor) -> entry count (>=0), or <0
  cursor points at ONE i64 the kernel reads AND writes:
    in   0 to start at the top of the directory
    out  the byte offset to resume from, or -1 when exhausted
  errors: -1 bad ptr / not ext2 · -2 not found · -4 not a dir · -5 misaligned cursor
```

## Why the number is `#101`

Verified mechanically on the agnos side, not assumed:

- Dispatch arms in `agnos/kernel/core/syscall.cyr` cover 0-95 and 97-100. `101` had none.
- ⚠ **`#96` looks free and is reserved** for `fork` (operator ruling 2026-08-05). Not taken.
- ⚠ **`#44` looks free to that grep and is not** — `sched_yield` dispatches in the ring-3 entry stub.

## ⛔ Why this is a second wrapper and not a 4th argument on `sys_readdir`

This is the row the gate really protects, and it is a **sharper** case than `#100`'s. Measured on
cyrius 6.5.35, the compiler pops only as many registers as a call site passes, so unused syscall
argument registers carry stale values rather than zero:

```
syscall(39)          ->  pop %rax                              ; rsi/rdx untouched
syscall(39, 1234)    ->  pop %rdx ; pop %rsi ; pop %rdi ; pop %rax
```

For `#55` the stale register would have been a garbage **timeout**. For `#81` it is a garbage
**pointer the kernel writes through** — an arbitrary 8-byte write into the caller's address space
from every already-shipped three-argument call site. Keep `sys_readdir(path, buf, max)` at three
arguments, byte-for-byte as it is. **Two wrappers, two arities.**

## ⚠ Guarding

A kernel older than **1.56.50** has no `#101` arm; it falls through the dispatch chain and returns
`-1`. Consumers must treat a negative return as *"this kernel cannot resume a listing"* and fall back
to `sys_readdir`, rather than rendering an empty directory. "No entries" and "this kernel cannot
page" are different facts — the same lesson `#99` and `#100` record. crab does exactly this.

## Acceptance

- `SYS_READDIR_AT` resolves on the agnos target and is inert elsewhere. ✅
- `sys_readdir_at` compiles for the agnos target and perturbs no Linux/host build. ✅
- `sys_readdir` keeps arity 3. ✅ (gate row)
- `tests/gates/platform/syscall_wrapper_pass.sh` axis 5 asserts all three, and was verified to
  **fail** when the wrapper is removed rather than merely to pass. ✅
- ⚠ **Not yet done:** exercised end-to-end against a booted 1.56.50 kernel *through the wrapper*.
  agnos's `tests/readdir/rdat.cyr` proves the kernel contract (exit 95) but calls the raw number,
  because it predates this release. **crab is the first consumer and carries that verification.**

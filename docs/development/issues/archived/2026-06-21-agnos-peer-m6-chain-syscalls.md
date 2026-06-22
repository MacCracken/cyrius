# AGNOS syscall peer — futex constants + `sys_access` for the M6 persistence chain

> **RESOLVED v6.2.35 (2026-06-21) — root-cause fix, not the filed one.**
> Premise-checking + an adversarial multi-agent verification pass found **C1
> (inert `SYS_FUTEX`/`FUTEX_*` constants) is dead code** against canonical patra
> 1.12.3 and was masking a real bug:
> - The `--agnos` error the reporter hit came from descent's **stale patra 1.11.2**
>   pin, whose `_patra_lock` uses `SYS_FUTEX` as a raw *constant* (cyrius
>   hard-errors on undefined *constants*). patra 1.12.x replaced that raw syscall
>   with `mutex_lock()` (a *function* — cyrius compiles undefined functions to a
>   `ud2`/SIGILL stub + warning, not a hard error). So once patra 1.12.3 is folded
>   (done this release), nothing on agnos references the futex constants — C1 is
>   permanent dead code.
> - The **actual** gap: `lib/sync.cyr` had no `CYRIUS_TARGET_AGNOS` mutex backend,
>   so patra's `mutex_new`/`lock`/`unlock` were undefined on agnos and
>   `patra_init()`'s *unconditional* `mutex_new()` was a silent runtime SIGILL.
>
> **Shipped:** (1) `lib/sync.cyr` agnos `#ifdef` **no-op mutex** (single-core
> cooperative-iron; a real lock awaits agnos preemptive multithreading); (2) **C2
> `sys_access` stub** as filed (fail-closed); (3) patra **1.12.3** re-fold; (4)
> agnos cross-build gate **probe 1f** asserting both are genuinely defined. **C1
> was NOT added.** Downstream action: descent should bump its patra pin
> 1.11.2 → 1.12.3.

**Discovered:** 2026-06-21 while porting `cyrius-yeomans-descent` (telnet MUD) to `CYRIUS_TARGET_AGNOS`
**Severity:** Medium (blocks `--agnos` builds of any libro/sigil/patra consumer; **zero** Linux/macos/aarch64 impact — additive)
**Affects:** `lib/syscalls_x86_64_agnos.cyr` (the agnos syscall peer) — 2 missing symbols
**Local reference (full sweep + derivation):** `agnosticos/docs/development/issues/2026-06-21-m6-chain-agnos-syscall-sweep.md`
**Related:** `2026-06-14-stdlib-constant-value-collisions.md` (same Linux↔agnos number-overlap class)

## Summary

The M6 persistence chain (`libro → sigil → patra → sakshi`) now compiles for
`CYRIUS_TARGET_AGNOS` **except** for two symbols the agnos peer doesn't define.
Both are pure, additive **peer** changes — no consumer edit, no Linux-side change.

The *in-lib* runtime hazards (raw Linux syscall numbers inside patra/libro) are
already fixed and released — **patra 1.12.3** and **libro 2.7.6** (2026-06-21,
source-only, Linux byte-identical). This issue covers only the **peer** half plus
a re-bundle note.

The agnos peer already defines everything else the chain needs (`SYS_LSEEK`#58,
`SYS_FLOCK`#59, `SYS_GETRANDOM`#45, `SYS_TIME_UNIX`#46, `SYS_SYNC`#12, `SYS_STAT`#33,
`SYS_WRITE`/`SYS_EXIT`, sock/epoll/timerfd/signalfd). Only the two below are missing.

## C1 — futex constants (compile-only; dead on single-core agnos)

The agnos peer lacks `SYS_FUTEX`, `FUTEX_WAIT`, `FUTEX_WAKE`, `FUTEX_PRIVATE_FLAG`
(all four are in `lib/syscalls_x86_64_linux.cyr`). patra's optional mutex path
(`_patra_lock`/`_patra_unlock`, via `mutex_lock`/`mutex_unlock`) references them.
They are **never reached at runtime on single-core agnos** — `_patra_mtx == 0` is
the default and short-circuits both helpers before any futex call — but the
symbols must resolve for the chain to compile `--agnos`.

**⚠ C1 may be MOOT once patra ≥1.12.2 is re-bundled.** The raw `syscall(SYS_FUTEX)`
only exists in the OLD vendored **patra 1.11.2**. **patra 1.12.2 refactored its
mutex onto the `mutex_lock` / `mutex_unlock` abstraction**, and on agnos those are
**no-ops** (`lib/thread_agnos.cyr:79-81` — `fn mutex_lock(m) { return 0; }`), so
the agnos build of patra 1.12.2+ **never references `SYS_FUTEX` at all**. Verify
after re-bundling patra: if nothing else on the agnos path references the symbol,
**drop C1 entirely** (don't add a Linux ABI for a workload agnos doesn't have —
single-core run-to-completion has no userspace contention). Keep the fix below
only if a residual reference survives the re-bundle.

**Fix (if still needed)** — add to `lib/syscalls_x86_64_agnos.cyr` (values inert; mirror the Linux peer):

```cyrius
# Futex constants — referenced by patra's optional mutex path. DEAD CODE on
# single-core agnos (_patra_mtx defaults to 0, short-circuiting before any
# syscall); defined only so the M6 chain compiles for CYRIUS_TARGET_AGNOS.
# 202 is out of agnos's 0–59 range and would no-op if ever dispatched.
enum AgnosFutexCompat {
    SYS_FUTEX = 202;
    FUTEX_WAIT = 0;
    FUTEX_WAKE = 1;
    FUTEX_PRIVATE_FLAG = 128;
}
```

## C2 — `sys_access(path, mode)` + `SYS_ACCESS`

sigil calls `sys_access` in ~13 sites (TPM / IMA / secureboot / cert existence
probes, e.g. `sys_access("/dev/tpmrm0", 0)`); the agnos peer defines neither the
wrapper nor `SYS_ACCESS`.

agnos has no `access(2)`, and none of sigil's probed paths exist on agnos, so
"absent" is the correct answer for every current call site. The minimal correct
fix is a fail-closed stub; the general upgrade is a `SYS_STAT`#33 existence test.

**Fix (recommended — fail-closed)** — add near `sys_stat` in the agnos peer:

```cyrius
# agnos has no access(2). sigil's callers only probe TPM/IMA/secureboot/cert
# paths that don't exist on agnos, treating !=0 as absent — so report absent.
# `mode` is ignored (no ring-3 perm model). UPGRADE PATH for a consumer that
# needs existence-true on agnos: strlen(path) + sys_stat(path, len, scratch)==0.
fn sys_access(path, mode): i64 { return 0 - 1; }
```

(If you prefer the general form now: compute the cstring length and
`return syscall(SYS_STAT, path, len, scratchbuf) == 0 ? 0 : -1` with a stack
statbuf ≥ `STAT_BUFSZ` bytes.)

## Action — re-bundle the released libs

`patra 1.12.3` + `libro 2.7.6` carry the in-lib agnos fixes (syscall-number
routing: patra WAL `time→time_unix`; libro `getrandom`/`time_unix`/symbolic
`SYS_LSEEK` — the last was the silent `#8=dup`-on-agnos FileStore-size bug).
Re-bundle both into the stdlib snapshot so `cyrius lib sync` consumers (descent)
pick them up alongside C1/C2.

## Additional finding (2026-06-21) — stdlib `io.cyr` flock helpers (persistence write path)

Surfaced after C1+C2 unblocked the compile and the descent-source port landed:
**`file_append_locked` / `file_lock_shared` / `file_unlock`** (defined in
`lib/io.cyr`, ~248–264) are **Linux-only** — undefined for `CYRIUS_TARGET_AGNOS`,
so libro's FileStore audit-write path (`lib/libro.cyr:3742+`) emits trap-stubs on
agnos (the build still succeeds; runtime-only, in the opt-in M6 save path).

agnos now has `flock`#59 + `lseek`#58, so these are implementable: give the three
an agnos branch (flock via `SYS_FLOCK`#59; append = `lseek` SEEK_END + `write`).
Lower priority than C1/C2 — it only gates *crash-safe persistence*, not the MUD
itself — but it's the next thing the libro audit chain needs on agnos.

## Verification

With C1+C2 in the peer, `cyrius build --agnos src/main.cyr` of
`cyrius-yeomans-descent` compiles **straight through** patra/sigil/sakshi/libro
into descent's own source (next stop: descent's epoll→poll-loop port, descent-side).
Confirmed 2026-06-21 with a throwaway prototype of exactly C1+C2 in descent's
vendored peer copy.

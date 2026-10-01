# arm64 macOS: a thread created in a `fork()` child kills the child (SIGSEGV inside `thread_create`)

**Status:** 🟡 **OPEN** — found while preparing sigil 3.13.6; not repaired.
**Placement:** **6.6.13** — the open-issue repairs (user, 2026-10-01; see `roadmap.md` § 6.6.13).
**Discovered:** 2026-10-01, running sigil 3.13.6's new first-use threading tests on ecb. They fork a fresh
process per trial and create threads in it; on ecb every trial died of SIGSEGV. A probe with no sigil code in
it reproduces the crash.
**Severity:** Medium. The crash is deterministic and loud, not silent, but its trigger is a common shape:
any arm64-macOS program that forks without exec and then creates a thread. That includes a daemon that forks and
then starts a worker pool, and a test harness that forks per trial.
**Affects:** cycc ≥ 6.5.44 on arm64 macOS (Mach-O arm64): measured on 6.6.12 and 6.6.9, on ecb (macOS 27.0).
6.5.44 (band J phase 2) is when `thread_create` became a real libSystem `pthread_create` there; before it,
bodies ran inline. Not affected:
- Linux (clone; no libSystem);
- x86 macOS (`THREADS_CONCURRENT = 0`, bodies run inline — a fork-then-thread test passed on ach under 6.6.9;
  not re-run under 6.6.12 because ach was unreachable at filing time);
- Windows (no fork);
- agnos.

## Summary

In a child made by `sys_fork()`, the first `thread_create` kills the child with SIGSEGV. The fault happens
inside `thread_create`, before it returns, and the thread body never runs. Fork itself works: a child that only
exits reports its status normally. It makes no difference whether the parent created a thread of its own
before forking.

| case | 6.6.12 arm64 macOS (ecb) | 6.6.12 Linux x86_64 |
|---|---|---|
| 0 — the child only exits (control) | exit 7 ✓ | exit 7 ✓ |
| 1 — the child creates and joins a thread | **killed by SIGSEGV** | exit 0 ✓ |
| 2 — the parent ran a thread first, then the child creates one | **killed by SIGSEGV** | exit 0 ✓ |

Markers written straight to fd 2 locate it: the child prints "before thread_create", and never "thread_create
returned".

## Reproduction

`repros/2026-10-01-macos-arm64-thread-create-in-fork-child-sigsegv.cyr` runs the three cases; the exit code is
the number that fail (2 on 6.6.12 arm64 macOS, 0 on Linux).

```
CYRIUS_MACHO_ARM=1 cyrius build --aarch64 docs/development/issues/repros/2026-10-01-macos-arm64-thread-create-in-fork-child-sigsegv.cyr fork_thread
scp fork_thread ecb: && ssh ecb 'codesign -s - -f fork_thread && ./fork_thread; echo "exit=$?"'
# -> case 1 and case 2 report 111 (100 + SIGSEGV); exit=2
```

## Root cause (hypothesis — the libSystem path is not established; no debugger run)

- On arm64 macOS the stdlib resolves the **aarch64 Linux** syscall peer (`lib/syscalls.cyr`'s
  `CYRIUS_TARGET_MACOS` / `CYRIUS_ARCH_AARCH64` arm). So `sys_fork` is
  `syscall(SYS_CLONE, SIGCHLD, 0, 0, 0, 0)` (`lib/syscalls_aarch64_linux.cyr:803`), which the Mach-O arm64
  syscall translation turns into Darwin's raw BSD `fork` (#2) with cycc's x1 child/parent fixup
  (`src/backend/aarch64/emit.cyr:896`, `_esx_arm(S, 220, 2)`, and the fixup at `:501`). (`lib/syscalls_macos.cyr:588`'s
  `sys_fork` is the x86 macOS one, where threads run inline.) None of this goes through libSystem's `fork()`, so
  none of libSystem's child-side fork handling runs in the child: the pthread atfork machinery, and the child
  re-initialisation that re-derives per-process state (for example the cached task port) and resets the thread
  list to the calling thread.
- `thread_create` on arm64 macOS (`lib/thread_macos.cyr:127`) calls libSystem's `pthread_create` through
  `__got[5]` (`syscall(1700, ...)`). In the child, that libSystem state still describes the parent.
- What is measured: cyrius's own work before the call runs fine in a fork child (`alloc`, the control-block
  stores, `atomic_fence`). The fault comes after that and before `thread_create` returns, and the body never
  runs. That places it in `pthread_create`'s use of the pre-fork state, but which access faults is not
  established.

## Proposed fix

1. **Route `sys_fork` through libSystem's `fork()` on the libSystem-linked arm64 Mach-O target**, so
   libSystem's own child handling runs. Concretely:
   - give the aarch64 peer's `sys_fork` a `CYRIUS_TARGET_MACOS` arm that calls `_fork` through `__got`, in the
     libSystem-routine sub-band the way `thread_create` reaches `pthread_create` (`syscall(1700, ...)`);
   - leave real aarch64 Linux on `clone`.

   The `__got` entry is a Mach-O writer change — `GOT_SIZE`, plus the parallel symtab / bind / indirect-symtab
   tables in `src/backend/macho/emit.cyr` — the same shape the `_pthread_detach` note in `lib/thread_macos.cyr`
   describes. The raw-fork translation (`emit.cyr:896`) can then stay for code that issues the number directly.
   Calling libSystem's private child-reinit hook after the raw syscall instead would depend on non-public
   symbols, and is not recommended.
2. **Add a `tests/tcyr/crossos/` test** that forks and creates a thread in the child (this repro's cases 1–2).
   The release gate's ecb leg runs that directory, so a regression goes red on real hardware, not only here.
3. Linux, Windows, agnos and x86 macOS are untouched.

## Consumer-side workaround

On arm64 macOS, do not create threads in a fork child: exec a fresh process instead (fork + exec is
unaffected). Creating a thread before forking does not help (case 2). sigil 3.13.6's tests run their cold trial
in-process off Linux for this reason (`tests/tcyr/lazy_init_race.tcyr`, `cbank_main_lane.tcyr`).

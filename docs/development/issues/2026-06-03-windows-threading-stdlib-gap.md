# cyrius `CYRIUS_TARGET_WIN` threading/mutex stdlib gap — `lib/thread.cyr` is Linux-only

> **Status**: OPEN — slotted SEPARATELY (user 2026-06-03, "ship .52 now, slot threading
> separately"). Blocks the ai-hwaccel `win_amd64` wheel's full build. Position in the slate TBD
> (user's call). Surfaced by the v6.0.52 ai-hwaccel cross-build smoke.
> **Prereqs in place**: v6.0.51 `lib/process_win.cyr` (CreateProcessW + the 5 kernel32 reroutes
> 0xF001-0xF005), v6.0.52 `cyrius build --win` (Linux→Windows cross-build flag) + the PROT_READ
> thread/freelist `mmap.cyr` fix. So a Windows cross-build now gets *past* PROT_READ and *into*
> `thread.cyr`, where it hits the Linux threading model.

## Symptom

`cyrius build --win src/main.cyr` of ai-hwaccel (a real consumer that pulls `thread` + `freelist`
via `[deps]`) fails: after the v6.0.52 PROT_READ fix, the next error is
`undefined variable 'CLONE_VM'` (and behind it `CLONE_FS/FILES/SIGHAND/THREAD/SYSVSEM/
PARENT_SETTID/CHILD_CLEARTID/SETTLS`, `SYS_CLONE`, the futex constants). The native Linux build
is clean — these symbols are `CYRIUS_TARGET_LINUX`-only (`syscalls_x86_64_linux.cyr`).

## Root cause

`lib/thread.cyr` is fundamentally the **Linux/POSIX threading model**: hand-assembled `clone(2)`
trampolines (x86 `SYS_CLONE` 56 / aarch64 220) with `CLONE_VM|FS|FILES|SIGHAND|THREAD|SYSVSEM|
PARENT_SETTID|CHILD_CLEARTID|SETTLS`, thread stacks via `mmap`, and `thread_join`/`mutex_*` via
**futex**. None of clone/futex exists on Win32 — Windows threading is `CreateThread` +
`WaitForSingleObject` (join) and `SRWLOCK`/`CRITICAL_SECTION` (mutexes), a different model.
`thread.cyr` has no `#ifdef CYRIUS_TARGET_WIN` branch, so it can't even *parse* under WIN.

ai-hwaccel genuinely depends on this surface: `async_detect.cyr` (`registry_detect_threaded`) runs
CLI-probe backends in parallel threads, and `lazy.cyr` + `cache.cyr` use `mutex_new`/`mutex_lock`/
`mutex_unlock` on **every** run (lazy init + disk cache). So a Windows ai-hwaccel needs at minimum
working mutexes, and ideally real threads.

**v6.0.50's green Windows gate masked this** — `win_emit_probe.cyr` includes only syscalls+alloc,
never `thread`/`freelist`, so the gate passed while a real consumer closure couldn't build. (Same
class as the macOS-rot: a probe that doesn't exercise the real surface is a placebo.) The
v6.0.52 PROT_READ fix is the first layer peeled; this is the second.

## Fix (the arc — approach decided at slot entry)

Guard `lib/thread.cyr`'s Linux body under `#ifndef CYRIUS_TARGET_WIN` and add a `thread_win.cyr`
included under `#ifdef CYRIUS_TARGET_WIN` (mirroring the v6.0.51 `process.cyr`→`process_win.cyr`
split). Two candidate shapes:

- **(A) Real Windows threading.** `thread_win.cyr` over `CreateThread` (a thread-proc with the
  MS-x64 ABI + a fn-pointer trampoline), `WaitForSingleObject` for join (already imported in .51),
  `GetExitCodeThread`, and `SRWLOCK` or `CRITICAL_SECTION` for mutexes (`InitializeSRWLock`/
  `AcquireSRWLockExclusive`/`ReleaseSRWLockExclusive`). Faithful parallel detection. New kernel32
  reroutes (the .51 0xF00N pattern: CreateThread / GetExitCodeThread / the SRW lock fns).
  process_win.cyr-scale.
- **(B) Serial-fallback.** `thread_spawn(fn,arg)` runs `fn(arg)` inline and stashes the result;
  `thread_join` returns it; mutexes are trivial (single-threaded → lock/unlock are no-ops or a
  flag). ai-hwaccel builds + runs on Windows detecting **serially** (fine for a one-shot tool).
  Far smaller — no CreateThread/trampoline/IAT work. Can be upgraded to (A) later.

Either way, the **public interface must match** `thread.cyr` (`thread_create`/`thread_spawn`/
`thread_join`/`mutex_new`/`mutex_lock`/`mutex_unlock`/… — enumerate at slot entry) so consumers are
target-agnostic.

## Validation

- `cyrius build --win src/main.cyr` of ai-hwaccel produces a PE32+ (no undefined CLONE_*/futex).
- Extend the Windows process gate (or add a `_win_thread_gate`) to cross-build a program that pulls
  `thread`+`freelist`+`process` (a *real* closure, not a toy probe) and assert it emits — so this
  can't silently rot again.
- Run the ai-hwaccel binary on cass: detection completes (serially under (B), in parallel under (A))
  and spawns its probes (the .51 exec_capture path). Then the ai-hwaccel `win_amd64` wheel is fully
  unblocked; the owner pins ai-hwaccel to the releasing tag.

## Cross-target note

The same audit should sweep the OTHER PROT_READ/Linux-syscall users not in ai-hwaccel's closure
(`fdlopen`, `dynlib`, `mabda`, `net`/`tls`) for `CYRIUS_TARGET_WIN` readiness when a consumer pulls
them — they likely have the same Linux-only assumption. Out of scope here; flag at slot entry.

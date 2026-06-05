# agnos `CYRIUS_TARGET_AGNOS` follow-up — the work carved out of v6.0.55 (post boot-to-prompt)

> **Status**: ✅ cyrius-side COMPLETE (archived v6.0.65). All cyrius-side items shipped by v6.0.56:
> process `exec` (lib/process_agnos.cyr sys_spawn/waitpid + exec_* family), `W*` wait macros, chrono
> fixed-epoch + no-op sleep, and the `syscall(60)` → target-aware `_die()` normalization. The only
> remainder is **agnos kernel-ABI work on the agnos side** (sys_spawn argv passing + sys_dup stdout
> redirect) — READ-ONLY here (no cyrius edit), tracked on agnos's plate, not a cyrius blocker. Archived
> with this cross-reference to v6.0.56; `git mv` back if a cyrius coordination point reopens.
>
> **Original (filed v6.0.55 close):** tracked, UNSLOTTED. Filed so the deferred
> agnos work has a visible home instead of living in the (now resolved) args+io issue's prose.
> **Predecessor**: 2026-06-03-cyrius-agnos-stdlib-args-io-gap.md (args + io gap — RESOLVED v6.0.55,
> archived). This file is everything that issue explicitly carved OUT of boot-to-prompt.
> **Context**: after v6.0.55 (args/io/chmod), `agnsh` built with `cyrius build --agnos` boots to a
> prompt; the items below are agnsh's only remaining `--agnos` undefineds / silent misbehaviours. All
> are cyrius-side or consumer-side — the agnos kernel is READ-ONLY (no agnos edit).

## 1. agnos process `exec` — the primary follow-up (its own arc)

**Reachability**: `agnsh`'s `run <external>` path (`security.cyr:121` → `exec_vec`, `process.cyr:162`).
Does NOT fire on boot-to-prompt — only when a user runs an external program.

**Gap**: `exec_vec` uses `sys_fork` + `sys_execve` + `sys_dup2`, none in the agnos frozen 0-33 peer →
cycc emits `ud2`. The wait-status macros `WEXITSTATUS` / `WIFEXITED` / `WIFSIGNALED` / `WTERMSIG` are
also undefined on the agnos path. (Confirmed by the v6.0.55 `cyrius build --agnos src/agnsh.cyr`
undefined-fn grep: these are the only remaining undefineds after .55.)

**agnos model**: not fork+exec — `sys_spawn(elf_addr, elf_size)` (in-memory ELF image) + a waitpid.
So this is a substantial arc: a `process.cyr` `CYRIUS_TARGET_AGNOS` branch that reads the target ELF
into memory and calls `sys_spawn`, plus agnos-shaped wait-status handling. **Its own slot(s).**

**Interim option (smaller, optional)**: stub `exec_vec` on agnos to a graceful "not supported on
agnos" return so an interactive `run` returns an error instead of `#UD`-ing. Decide stub-now vs
full-arc when slotted.

## 2. `lib/chrono.cyr` time source

`chrono.cyr` uses raw `syscall(228)` (clock_gettime) + `syscall(35)` (nanosleep) — outside agnos 0-33.
**No `ud2`** (the numbers exist as agnos syscalls, just mean other things) → bogus timestamps / sleep.
agnos has no wall-clock or sleep syscall in the frozen surface. Fix: a `CYRIUS_TARGET_AGNOS` branch
returning a fixed/zero epoch (the v1.0 precedent). Low severity (unusable timestamps, not a crash).

## 3. `sys_stat` sudo-path — consumer-side (agnsh)

`security.cyr:88` calls a 2-arg `sys_stat` and reads `st_uid`; the agnos peer `sys_stat` is 3-arg
`(path, pathlen, statbuf)` with `AgnosStat` (no `st_uid`). Silently misbehaves. agnos `getuid` is
always-root, so the sudo check is moot anyway → **fix consumer-side in agnsh** (guard
`verify_sudo_path` off under agnos). Flag-back to the agnoshi/agnos owner, not cyrius work.

## 4. raw `syscall(60, ...)` aborts — optional rider

`lib/vec.cyr` / `lib/hashmap.cyr` / `lib/tagged.cyr` error paths call raw `syscall(60)` (Linux
exit_group); agnos exit is `syscall(0)`. Compiles fine; only hits an undefined agnos syscall on an
error path. Optional low-priority rider: normalize these to `sys_exit(n)` so they exit correctly on
every target. (agnsh.cyr:404's own exit is consumer-side.)

## agnos-side coordination (flag-back to the agnos agent — non-blocking, no cyrius dependency)

1. `agnos-userland-abi.md` documents the syscall surface but NOT the init-stack/argc/argv exec
   contract (lives only in `elf.cyr` + a 1.40.7 comment). Should gain an "init stack at exec" section
   (the v6.0.55 capture depends on `[rsp]=argc, [rsp+8+i*8]=argv[i]`, rsp 16-aligned, argc≤8). cyrius
   does not edit it.
2. Empty envp + AT_NULL-only auxv is by design; real env vars would be an agnos ABI addition.
3. No time/sleep syscall in 0-33; real audit timestamps would need an agnos syscall addition.

## Confirmed NON-issues (don't spend slot time)
`alloc.cyr` has an agnos branch (mmap(27) heap); `syscalls.cyr` dispatches to the agnos peer;
string/fmt print helpers use `syscall(1)` (agnos SYS_WRITE=1, safe); `io.cyr` file_lock family +
`fs.cyr` are not on the agnsh path (Linux-gated; latent only if agnsh ever lists dirs).

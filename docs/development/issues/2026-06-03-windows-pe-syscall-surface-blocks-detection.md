# 2026-06-03 — Windows PE: ~10-syscall surface + frozen `cc5_win` 5.11.69 block a real consumer build

> **STATUS — split into foundation (v6.0.50, DONE) + arc (v6.0.51, OPEN):**
> **v6.0.50 cleared the BUILD blocker (#2):** `cycc_win` unfrozen 5.11.69 → 6.0.x
> (scripts/install.sh now has a rebuild rule; it had none → copied the frozen
> binary forward). The `PROT_READ` closure break was the frozen frontend — the
> 6.0.x emit path (`CYRIUS_TARGET_WIN=1 cycc`) always resolved the WIN closure.
> Added a Windows stdlib-cross-build gate (`_win_build_gate`, check.sh 84). The
> 5.11.5 ExitProcess/WriteFile hazard (#4) is confirmed gone on 6.x (the cass
> cross-OS self-host writes via WriteFile + exits via ExitProcess every release).
> **v6.0.51 = the RUNTIME blocker (#1), RESOLVED + cass-verified.** Win32 process
> creation now routes through CreateProcessW. `lib/process_win.cyr` (included by
> `lib/process.cyr` under `#ifdef CYRIUS_TARGET_WIN`, POSIX defs guarded by
> `#ifndef`) reimplements the full surface — run / run_capture / spawn / wait_pid /
> exec_vec / exec_capture / exec_env + the `_str` family — over five new
> PE-internal syscall reroutes in `src/backend/x86/emit.cyr` (0xF001-0xF005 →
> WaitForSingleObject / GetExitCodeProcess / SetHandleInformation / CreatePipe /
> CreateProcessW), reusing EREAD_PE (raw-handle ReadFile, v6.0.45) + ECLOSE_PE
> (CloseHandle). `ECREATEPROC_PE` force-aligns rsp — the 10-arg CreateProcessW
> faults on the misalign the ≤4-arg reroutes tolerate (found ON cass, not by
> objdump). **VERIFIED on real Windows (cass):** `exec_capture` spawns `cmd.exe`
> and captures its stdout (`cyrius-spawn-ok`); cycc self-hosts byte-identical on
> ecb/cass/pi; check.sh 85/85 incl. the new `_win_process_gate`. **Remaining
> (v6.0.52):** ai-hwaccel downstream wheel smoke — now UNBLOCKED; pin to 6.0.51.

> **v6.0.52 validation checklist (v6.0.51 adversarial audit, no high/critical found).**
> The cass smoke exercised `exec_capture` with a small output + simple argv. The
> ai-hwaccel downstream smoke should validate these untested-path behaviours against
> real probe invocations (none block the core path; all match POSIX contract or a
> documented limit):
> 1. **Large-output capture** — `_win_drain` truncates at `buflen` and the parent
>    closes the read end before `WaitForSingleObject(INFINITE)`; confirm a probe
>    whose stdout exceeds `buflen` truncates cleanly and the child exits (broken-pipe)
>    rather than hanging. (POSIX relies on SIGPIPE; Win32 relies on read-end close.)
> 2. **argv with spaces** — the cmdline is space-joined + unquoted; a probe path like
>    `C:\Program Files\...` needs quoting. Add CommandLineToArgvW-style quoting if a
>    real probe path contains spaces.
> 3. **`exec_env` replaces the environment** (POSIX-consistent) — a child needing
>    `SystemRoot`/`PATH` must get them in the passed env; merge-with-parent is not done.
> 4. **NULL stdin** for captured children (STARTF_USESTDHANDLES) — fine for probes
>    that don't read stdin; set `hStdInput = GetStdHandle(STD_INPUT)` if one does.
> 5. **ASCII-only UTF-16 widening** — non-ASCII path bytes pass through as the low
>    byte; real UTF-8→UTF-16 decode if a probe path is non-ASCII.
>
> Separately, queue a **vidya compiler field-note** (v6.1.0 closeout): Win64 IAT-call
> reroutes with >4 args must force `rsp` 16-alignment — CreateProcessW's SSE string
> ops fault on the misalign the ≤4-arg reroutes tolerate; invisible to objdump,
> surfaces only on real Windows. And consider a compile-time arity-mismatch error for
> the `0xF00N` syscall range (today a wrong-arity call silently falls through to the
> Linux `0F 05` path → faults on Windows).

**Discovered:** 2026-06-03 assessing the ai-hwaccel v2.3.7 Windows wheel
(consumer: **ai-hwaccel**, cyrius pinned 6.0.47).
**Severity:** High — hard blocker for a roadmapped consumer deliverable
(`win_amd64` wheel), no workaround. Analogous to the x86-macOS runtime
gap ([`2026-06-02-macos-x86-release-no-compiler.md`](./2026-06-02-macos-x86-release-no-compiler.md)):
the PE *backend* exists and emits valid binaries, but the Windows
syscall/runtime surface is too thin to run anything real.
**Affects:** the Windows PE path — `cycc_win` / `cc5_win` (frozen at
**5.11.69**), `CYRIUS_TARGET_WIN` codegen. cyrius wrapper 6.0.47. Build
host: Linux x86_64 (cross). Runtime host: `cass` (Windows x86_64).

## Summary

`cycc_win` is a Linux-hosted ELF cross-compiler that *does* emit valid
`PE32+` Windows binaries — trivial programs work. But two layers block a
usable consumer build:

1. **The Windows PE syscall surface routes only ~10 syscalls.** The
   compiler itself warns:
   > `syscall(n, ...) on CYRIUS_TARGET_WIN=1 routes n=0,1,2,3,8,9,60,83,87,228 today; others crash with STATUS_ILLEGAL_INSTRUCTION (0xC000001D)`

   That set is read/write/open/close/lseek/mmap/exit/mkdir/unlink/
   clock_gettime. It is missing **`fork` (57)** and **`execve` (59)** —
   which `lib/process.cyr` uses (`sys_fork()` + `sys_execve()`) for every
   subprocess. ai-hwaccel's core function is hardware detection by
   spawning probe tools (`run_tool` → `exec_capture` in
   `src/detect/command.cyr`), so the moment it probes, the PE binary
   faults with `STATUS_ILLEGAL_INSTRUCTION`. (Also absent and likely
   needed: `pipe`, `wait4`, `getcwd`, `dup2`.)

2. **The PE toolchain is frozen at `cc5_win` 5.11.69 while the stdlib is
   6.0.47.** Cross-building the full stdlib bundle fails:
   `error: lib/atomic.cyr:98: undefined variable 'PROT_READ'`. `cycc_win`
   also emits `note: cwd ./lib/ shadows version-pinned 5.11.69/lib` —
   i.e. it wants its *own* 5.11.69 snapshot, and the 6.0.47 stdlib's
   include closure for `CYRIUS_TARGET_WIN` doesn't resolve cleanly
   against the 5.11.69 frontend (here `PROT_READ`, an `lib/mmap.cyr` enum
   not in the WIN closure). So even a no-spawn binary can't be built from
   the current pinned stdlib without a frozen-toolchain workaround.

There is a historical third hazard (per `src/detect/windows.cyr`'s own
comment, ai-hwaccel side): `cc5_win` 5.11.5 had a PE emit bug where
`ExitProcess(N)` / `WriteFile()` didn't reach userspace on `cass`
(exit `0x40001000`). Status on 6.x is **unconfirmed** — worth a smoke
test once #1/#2 are addressed.

## Reproduction

On Linux x86_64 with cyrius 6.0.47 + the ai-hwaccel checkout (pin
6.0.47, `./lib` synced):

```sh
# (A) trivial program — PE backend is healthy:
printf 'fn main() { return 42; }\n' | ~/.cyrius/versions/6.0.47/bin/cycc_win > w.exe
file w.exe            # -> PE32+ executable for MS Windows, x86-64   ✅

# (B) full stdlib bundle ([deps] stdlib order + src/main.cyr) — frozen
#     frontend can't resolve the 6.0.47 WIN closure:
#   ... generate win_entry.cyr = `include "lib/<mod>.cyr"` per [deps]
#       stdlib, then `include "src/main.cyr"` ...
cat win_entry.cyr | ~/.cyrius/versions/6.0.47/bin/cycc_win > out.exe
#   error: lib/atomic.cyr:98: undefined variable 'PROT_READ'
#   note:  cwd ./lib/ shadows version-pinned 5.11.69/lib
#   warning: syscall(n,...) routes n=0,1,2,3,8,9,60,83,87,228; others crash
```

Even if (B) is forced to compile (drop the offending modules / supply a
5.11.69 stdlib), the routed-syscall warning means any `fork`/`execve` at
runtime → `STATUS_ILLEGAL_INSTRUCTION`. ai-hwaccel cannot detect anything
without spawning probes.

## Root cause

Two independent gaps:

- **Syscall surface (primary).** The `CYRIUS_TARGET_WIN` runtime routes a
  ~10-syscall subset to Win32 equivalents; `fork`/`execve` (and the
  process-plumbing around them) are unrouted. This is the Windows analog
  of the arm64 BSD-ABI arc (v6.0.32–.34) and the x86-macOS `ESYSXLAT`
  gap — a backend runtime arc, not a packaging patch. Process creation on
  Win32 has no fork/exec; it needs a `CreateProcess`-based reroute for
  the `sys_fork`+`sys_execve`+`pipe`+`wait` pattern `lib/process.cyr`
  emits (or a `process` stdlib variant under `#ifdef CYRIUS_TARGET_WIN`).

- **Toolchain freeze (secondary).** `cc5_win`/`cycc_win` at 5.11.69 lag
  the 6.0.x line, so the current stdlib's WIN include closure doesn't
  build against it (`PROT_READ`). Either unfreeze the PE frontend to 6.0.x
  or ship/pin a 5.11.69-compatible WIN stdlib snapshot that `cycc_win`
  resolves (the "version-pinned 5.11.69/lib" it already looks for).

## Proposed fix

1. Route Win32 process creation: map the `sys_fork`+`sys_execve` (+`pipe`,
   `wait4`, `dup2`, `getcwd`) pattern to `CreateProcess`/anonymous pipes
   under `CYRIUS_TARGET_WIN`. Add the routed-syscall set to the warning so
   it reflects reality as it grows.
2. Unfreeze `cc5_win`/`cycc_win` onto the 6.0.x stdlib (or pin a matching
   WIN snapshot) so the current stdlib cross-compiles.
3. Add a Windows real-build gate to `cyrius audit` (cross-build a program
   that spawns a subprocess + writes stdout, smoke-run it on `cass`) so
   this surface is exercised beyond `fn main(){return 42;}`.
4. Re-confirm the 5.11.5 `ExitProcess`/`WriteFile` userspace-propagation
   bug is gone on 6.x (`cass`, Win11 26200).

## Consumer-side workaround (if any)

**None viable for a useful wheel.** ai-hwaccel has a `builder_no_exec()`
mode (masks spawn-based detectors), but: (a) the stdlib bundle still
won't cross-compile on the frozen frontend (#2), and (b) a no-exec binary
detects only CPU because `src/detect/windows.cyr` (DXGI) is still a stub
on the consumer side — so it isn't worth shipping. ai-hwaccel keeps the
2.3.7 Windows wheel + its `wheels.yml` `windows` job **gated off** until
the PE syscall surface lands; pin is 6.0.47. **Recommended floor for the
Windows wheel: the first 6.0.x whose `cycc_win` (a) cross-builds the
current stdlib and (b) routes process creation, verified on `cass`.**

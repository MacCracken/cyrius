# 2026-06-03 — Windows PE: ~10-syscall surface + frozen `cc5_win` 5.11.69 block a real consumer build

> **STATUS — split into foundation (v6.0.50, DONE) + arc (v6.0.51, OPEN):**
> **v6.0.50 cleared the BUILD blocker (#2):** `cycc_win` unfrozen 5.11.69 → 6.0.x
> (scripts/install.sh now has a rebuild rule; it had none → copied the frozen
> binary forward). The `PROT_READ` closure break was the frozen frontend — the
> 6.0.x emit path (`CYRIUS_TARGET_WIN=1 cycc`) always resolved the WIN closure.
> Added a Windows stdlib-cross-build gate (`_win_build_gate`, check.sh 84). The
> 5.11.5 ExitProcess/WriteFile hazard (#4) is confirmed gone on 6.x (the cass
> cross-OS self-host writes via WriteFile + exits via ExitProcess every release).
> **v6.0.51 = the RUNTIME blocker (#1), still OPEN:** route Win32 process creation
> — `fork`(57)/`execve`(59) (+`pipe`/`wait4`/`dup2`/`getcwd`) are unrouted, so
> ai-hwaccel's probe spawns fault (STATUS_ILLEGAL_INSTRUCTION). Needs a
> `CreateProcess`-based `run`/`run_capture` under `#ifdef CYRIUS_TARGET_WIN`
> (no 1:1 fork mapping) + kernel32 imports (CreateProcessW/CreatePipe/
> WaitForSingleObject/GetExitCodeProcess) + a cass spawn-build gate. Keep OPEN.

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

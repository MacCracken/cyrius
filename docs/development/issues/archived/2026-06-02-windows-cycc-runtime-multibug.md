# 2026-06-02 — Windows: cycc has never run as a compiler (multi-bug runtime arc)

**Filed:** 2026-06-02 (during the Windows-install pillar work)
**Affected:** the PE runtime — `cycc.exe` running as a compiler on Windows
**Severity:** High — Windows is claimed-supported but `cycc` does not
compile anything there. Same class as the macOS rot, one platform over.
**Status:** bug 1 (v6.0.39) + **bug 2 RESOLVED** — only the install Pillar
remains. `cycc.exe` compiles + runs + self-hosts on real `cass`. The cross-OS
cass gate (`scripts/cross-os-selfhost.sh cass`) runs the REAL on-Windows
compile chain (`cycc.exe < main_win.cyr > c2.exe && c2.exe < main_win.cyr >
c3.exe && fc /b`, + the exit-42 + callptr-real-Win64 guards) and is green.
**Re-verified hands-on 2026-06-07:** `cycc.exe` compiled a non-trivial program
(fns + while-loop + args) on cass → a 1536-byte runnable PE → exit 90 (correct).
The remaining work is the **Pillar** (real install on cass → working cycc +
cass `cyrius audit` gate) — scoped as the v6.0.85 Windows install bundle (cyrius
is NOT yet installed on cass: no `~/.cyrius`). Verifiable on `cass`
(Windows 10.0.26200, SSH-wired).

## How it stayed hidden

CI/release only ever ran *emitted* PE programs (exit42, hello-world) and
the PE-emit magic check — **never compiled a program THROUGH `cycc.exe`
on real Windows.** So every Windows "self-host"/"native" checkmark was a
placebo. `cycc.exe` crashed on startup the whole time. The PE work
(v5.4.x–v5.11.x) was all about *emitting* PE from Linux, never running
the compiler on Windows.

## Bug 1 — allocator (FIXED, v6.0.39)

`lib/alloc_windows.cyr:alloc_init` called `syscall(12)` (BRK) assuming a
"PE reroutes brk → VirtualAlloc" that was never implemented (the PE
syscall dispatch in `parse_expr.cyr` handles 0/1/2/3/8/9/60/228, not 12).
`syscall(12)` fell through to a raw `SYSCALL` instruction → illegal on
Windows → `STATUS_ACCESS_VIOLATION`. cycc's `vec_new()` hit it on the
first `alloc()` at startup. Fixed to `syscall(9)` (mmap → VirtualAlloc).
**Verified on cass: `vec_new` no longer crashes, cycc reads stdin (12/12
bytes).**

## Bug 2 — input length lost before parse (RESOLVED)

> **RESOLVED (verified 2026-06-07).** `cycc.exe` now compiles non-trivial
> programs on cass and self-hosts byte-identical (the cross-OS cass gate runs
> the real on-Windows compile chain every slot). The original "zero code"
> symptom is gone — direct hands-on test compiled fns + a while-loop + args to
> a runnable 1536-byte PE that exits 90. (The SBL/GBL store concern below was
> resolved in the compile→emit→write hardening that landed with the WIN
> auto-call-main guard and the self-host bring-up; the issue text was left
> stale.) Remaining: the install **Pillar** below (= v6.0.85).

Original symptom (historical): after bug 1, `cycc` read its input but produced
**zero code** (`GCP=0` before FIXUP → empty output, exit 0). Bisected on `cass`:
- read loop reads the full input,
- but `GBL(S)` reads **0** immediately after `SBL(S, bl)` with `bl=12`.

So `SBL`'s store (`S64(S + 0x18C100, v)`) isn't landing where `GBL`
(`L64(S + 0x18C100)`) reads it, on Windows specifically. Candidates: a
store/load codegen issue at that offset under the PE/VirtualAlloc heap
base, or a fn-arg passing bug for `SBL(S, bl)`. **Not yet root-caused.**
Likely more bugs beneath this (compile → FIXUP → EMITPE → write).

## How to continue (on `cass`)

Use the exit-code-checkpoint method (ExitProcess works; stdout may not be
needed): instrument `main_win.cyr` / the store path, build with a CLEAN
PE cross-emitter (NOT one built from the instrumented source — it would
exit early on Linux), ship to `cass`, read the errorlevel. Root-cause
bug 2 (SBL/GBL store), then walk the rest of the compile→emit→write path
until `cycc.exe` compiles `var x=42` to a runnable PE on `cass`, then
`fn main(){return N}` (also needs the auto-call-main fix `main_win.cyr`
lacks — the `0x40001000` exit), then self-host, then the REAL install
(`install.sh`) on `cass`, then the cass arm of the `cyrius audit` gate.

## Pillar — DONE (v6.0.85)

Windows is not supported until the real installer on `cass` yields a `cyrius`
that compiles + runs (verified on hardware) — same bar as macOS arm64 (v6.0.38).
**Met @ v6.0.85.** Native `scripts/install.ps1` + `scripts/build-windows-tarball.sh`
(now shipping `cyrius.exe`) produce an install where `cyrius build fn
main(){return 42}` yields a runnable PE exiting 42, verified by the new cass arm
of `cyrius audit` (`scripts/cass-install-gate.{sh,ps1}`). Required, all landed
@ .85: the `GetEnvironmentVariableA` PE reroute (`0xF015`) for Windows env-read,
the wrapper's `bin/cycc.exe` resolution (cbt/core.cyr), and the `compile()`
cmd.exe-redirect spawn via `CreateProcessW` (cbt/build.cyr + lib/process_win.cyr)
— Win32 has no fork/dup2/execve. See CHANGELOG [6.0.85]. **Issue resolved.**

> The only remaining Windows item is the DXGI GPU-enum demonstrator — operator-
> gated (cass has no windbg/cdb + only an integrated GPU); tracked in
> 2026-06-03-windows-pe-com-vtable-dxgi-for-gpu-enum.md + -followup-nuances.md.

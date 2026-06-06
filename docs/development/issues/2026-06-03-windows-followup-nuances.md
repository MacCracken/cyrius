# Windows `CYRIUS_TARGET_WIN` follow-up nuances (tracked, not urgent)

> **Status**: PARTIAL — §1 (real threads) + §2 (per-thread TLS) RESOLVED v6.0.61; §3 (full
> CommandLineToArgvW + UTF-8) RESOLVED v6.0.69. §0 (COM/DXGI GPU-enum, its own issue): the COM
> vtable / IR_CALL_INDIRECT capability LANDED (v6.0.70 callptr + v6.0.71 ECALLPTR_PE frame fix,
> verified on cass) — only the real-GPU DXGI demonstrator residual remains. **Re-ordered 2026-06-06**:
> that residual + the other Windows partials were back-burned into the **near-end Windows repair
> cluster** that runs AFTER the TLS arc (see roadmap.md back-end shape; `.72+` = native TLS).
> cyrius-side; no cross-repo edit.
> **NOTE TO USER**: you flagged "another wrinkle" you have in mind — add it under §0 so it's captured.

## 0. COM vtable + DXGI for GPU enumeration — the user's flagged wrinkle

Tracked in its own issue: **2026-06-03-windows-pe-com-vtable-dxgi-for-gpu-enum.md** (COM-interface
vtable dispatch + DXGI for enumerating GPUs on Windows — the ai-hwaccel detection path). **Priority:
AFTER the heavier items** (#1 real threading first), per user 2026-06-03. Listed here so the Windows
follow-up set is complete in one place.

## 1. Real preemptive Windows threads — the primary upgrade — RESOLVED v6.0.61

~~`lib/thread_win.cyr` (v6.0.53) is a serial fallback~~ — **DONE.** Real `CreateThread` (0xF007) /
`WaitForSingleObject` (0xF001) + `CloseHandle` (3) / `SRWLOCK` (`InitializeSRWLock`/`Acquire`/
`ReleaseSRWLockExclusive`, 0xF008-0xF00A) reroutes. Channels became SRWLOCK-protected rings. Verified
on cass: 4-thread mutex contention → exactly 400000; no-mutex → lost updates (real parallelism). The
fully-resolved 2026-06-03-windows-threading-stdlib-gap.md was archived at .61.

## 2. Windows `thread_local` → real per-thread TLS (depends on #1) — RESOLVED v6.0.61

~~single global 16-slot array~~ — **DONE.** `thread_local_init/get/set` key off one `TlsAlloc`'d
(0xF00C) TEB index; each thread installs its own 128-byte block via `TlsSetValue` (0xF00E) /
`TlsGetValue` (0xF00D). `gettid` → `GetCurrentThreadId` (0xF00B). Landed in lockstep with #1. Verified
on cass: 4 threads each read back their own slot-0 value after interleaving + distinct tids.

## 3. args tokenizer — ✅ RESOLVED v6.0.69 (real CommandLineToArgvW + UTF-8)

~~`lib/args_win.cyr` (v6.0.54) tokenizes `GetCommandLineW` with the common subset~~ — **DONE.** The
v6.0.69 multi-DLL IAT foundation made `shell32` importable (cyrius's first non-kernel32 DLL); `args_init`
now splits with the real `shell32!CommandLineToArgvW` (`0xF010` → `ECMDTOARGV_PE`, full `\\"`-quote
semantics) and converts each wide arg to UTF-8 via the host-testable `_args_w2u8` (surrogate-aware), then
frees the `LPWSTR*` with `kernel32!LocalFree` (`0xF011`). The ASCII-only down-convert (non-ASCII →
high-byte-dropped / '?') is gone — Unicode install paths and backslash-quoted argv now parse correctly.
Verified on cass (`"hello world"` kept as one arg) + `tests/tcyr/args_win_utf8.tcyr` (21 assertions).
See CHANGELOG [6.0.69].

## Confirmed RESOLVED (for the record)
- Real preemptive threads + SRWLOCK mutexes (`thread_win.cyr`, 0xF007-0xF00A) — v6.0.61
  (2026-06-03-windows-threading-stdlib-gap.md, archived). [§1]
- Real per-thread TLS + gettid (`thread_local.cyr`, 0xF00B-0xF00E) — v6.0.61. [§2]
- Windows command-line args (`args_win.cyr`, GetCommandLineW `0xF006` reroute) — v6.0.54
  (2026-06-03-windows-args-stdlib-gap.md, archived).
- cycc_win `fn main()` DCE-rooting — v6.0.54.
- PE syscall surface / cycc_win runtime — v6.0.39–.51.

# Windows `CYRIUS_TARGET_WIN` follow-up nuances (tracked, not urgent)

> **Status**: PARTIAL — §1 (real threads) + §2 (per-thread TLS) RESOLVED v6.0.61. Remaining OPEN:
> §3 (full CommandLineToArgvW, ASCII-only today) + §0 (COM/DXGI GPU-enum, its own issue, the heavier
> deferred item). UNSLOTTED (user "not right away... nuances we need to cover at some point",
> 2026-06-03). cyrius-side; no cross-repo edit.
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

## 3. args tokenizer — ASCII-only, no full `CommandLineToArgvW` semantics

`lib/args_win.cyr` (v6.0.54) tokenizes `GetCommandLineW` with the common subset: toggle on `"`, split
on unquoted space/tab, ASCII down-convert (drop the high byte). It does NOT implement the full
`CommandLineToArgvW` backslash-before-quote rules (`\\"` runs, 2n-backslash + quote, etc.) and a
Unicode (non-ASCII) install path or argv corrupts silently. Fine for ASCII tool paths + flags (the
ai-hwaccel wheel). Full fidelity would need a `shell32!CommandLineToArgvW` import + `LocalFree` (a new
DLL beyond the single-kernel32 path) — out of scope until a consumer forces it.

## Confirmed RESOLVED (for the record)
- Real preemptive threads + SRWLOCK mutexes (`thread_win.cyr`, 0xF007-0xF00A) — v6.0.61
  (2026-06-03-windows-threading-stdlib-gap.md, archived). [§1]
- Real per-thread TLS + gettid (`thread_local.cyr`, 0xF00B-0xF00E) — v6.0.61. [§2]
- Windows command-line args (`args_win.cyr`, GetCommandLineW `0xF006` reroute) — v6.0.54
  (2026-06-03-windows-args-stdlib-gap.md, archived).
- cycc_win `fn main()` DCE-rooting — v6.0.54.
- PE syscall surface / cycc_win runtime — v6.0.39–.51.

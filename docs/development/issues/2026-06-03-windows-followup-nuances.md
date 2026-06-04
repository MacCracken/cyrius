# Windows `CYRIUS_TARGET_WIN` follow-up nuances (tracked, not urgent)

> **Status**: OPEN — tracked, UNSLOTTED (user "not right away... nuances we need to cover at some
> point", 2026-06-03). Consolidated home for the Windows things deferred across .50–.54 so they have
> a visible place instead of living in resolved issues' prose. cyrius-side; no cross-repo edit.
> **NOTE TO USER**: you flagged "another wrinkle" you have in mind — add it under §0 so it's captured.

## 0. COM vtable + DXGI for GPU enumeration — the user's flagged wrinkle

Tracked in its own issue: **2026-06-03-windows-pe-com-vtable-dxgi-for-gpu-enum.md** (COM-interface
vtable dispatch + DXGI for enumerating GPUs on Windows — the ai-hwaccel detection path). **Priority:
AFTER the heavier items** (#1 real threading first), per user 2026-06-03. Listed here so the Windows
follow-up set is complete in one place.

## 1. Real preemptive Windows threads — the primary upgrade

`lib/thread_win.cyr` (v6.0.53) is a **serial fallback**: `thread_create` runs the fn inline to
completion, mutexes are single-threaded no-ops, `thread_join` is a stub. Real concurrency needs
`CreateThread` / `WaitForSingleObject` / `SRWLOCK` kernel32 reroutes. **Already tracked in
2026-06-03-windows-threading-stdlib-gap.md** — this entry just cross-references it as part of the
Windows nuance set.

## 2. Windows `thread_local` → real per-thread TLS (depends on #1)

`lib/thread_local.cyr`'s WIN branch (v6.0.54) is a single global 16-slot array — correct ONLY because
`thread_win` is serial (one logical thread live at a time). When real Windows threads land (#1), this
MUST become real per-thread storage (`TlsAlloc`/`TlsGetValue`/`TlsSetValue` via new 0xF0xx kernel32
reroutes) or concurrent workers (e.g. sigil 3.6.x's crypto-scratch banks) will collide. The WIN
branch carries a load-bearing comment to this effect; tracked here so the upgrade lands in lockstep
with #1.

## 3. args tokenizer — ASCII-only, no full `CommandLineToArgvW` semantics

`lib/args_win.cyr` (v6.0.54) tokenizes `GetCommandLineW` with the common subset: toggle on `"`, split
on unquoted space/tab, ASCII down-convert (drop the high byte). It does NOT implement the full
`CommandLineToArgvW` backslash-before-quote rules (`\\"` runs, 2n-backslash + quote, etc.) and a
Unicode (non-ASCII) install path or argv corrupts silently. Fine for ASCII tool paths + flags (the
ai-hwaccel wheel). Full fidelity would need a `shell32!CommandLineToArgvW` import + `LocalFree` (a new
DLL beyond the single-kernel32 path) — out of scope until a consumer forces it.

## Confirmed RESOLVED (for the record)
- Windows command-line args (`args_win.cyr`, GetCommandLineW `0xF006` reroute) — v6.0.54
  (2026-06-03-windows-args-stdlib-gap.md, archived).
- cycc_win `fn main()` DCE-rooting — v6.0.54.
- PE syscall surface / cycc_win runtime — v6.0.39–.51.

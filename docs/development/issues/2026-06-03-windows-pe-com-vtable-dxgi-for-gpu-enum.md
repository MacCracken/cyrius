# 2026-06-03 — Windows PE: no COM vtable calls / non-kernel32 IAT blocks native DXGI GPU enumeration

> **Status (updated 2026-06-06):** the two CAPABILITIES this issue named as blockers are DELIVERED +
> verified — (1) non-kernel32 IAT imports (v6.0.69 multi-DLL foundation; `dxgi.dll!CreateDXGIFactory1`
> returns S_OK on cass) and (2) COM vtable / indirect calls (`callptr`/`IR_CALL_INDIRECT`, verified on
> 4 hosts). The Win64-COM-callee frame-corruption bug was FIXED in **v6.0.71** (`ECALLPTR_PE` force-16-align;
> issue now in `issues/archived/2026-06-05-windows-com-vtable-real-callee-frame-corruption.md`). The
> remaining piece — the real-GPU DXGI GPU-enum DEMONSTRATOR (`lib/dxgi.cyr` full `dxgi_vram_bytes()` chain,
> needs windbg-on-cass) — was **back-burned 2026-06-06** into the **near-end Windows repair cluster** that
> runs AFTER the TLS arc (roadmap.md back-end shape).

**Discovered:** 2026-06-03 implementing the ai-hwaccel v2.3.7 Windows
GPU detection (consumer: **ai-hwaccel**, cyrius pinned 6.0.54).
**Severity:** Low — an *enhancement*, not a blocker. ai-hwaccel ships
2.3.7 Windows GPU detection via a `wmic Win32_VideoController` subprocess
(the spawn path cyrius 6.0.51 enabled, RESOLVED in
[`2026-06-03-windows-pe-syscall-surface-blocks-detection.md`](./2026-06-03-windows-pe-syscall-surface-blocks-detection.md)).
This issue is the path to *better* detection: native DXGI, which removes
the subprocess and fixes a VRAM-accuracy limit.
**Affects:** the Windows PE backend's external-call surface
(`src/backend/x86/emit.cyr` IAT machinery). cyrius 6.0.54.

## Summary

ai-hwaccel detects Windows GPUs by spawning `wmic path
win32_VideoController get Name,AdapterRAM`. This works, but
`Win32_VideoController.AdapterRAM` is a **32-bit DWORD capped at 4 GiB**,
so a 24 GB RTX 4090 reports ~4 GB. The accurate, subprocess-free source
is **DXGI**: `CreateDXGIFactory1` → `IDXGIFactory1::EnumAdapters1` →
`IDXGIAdapter1::GetDesc1` → `DXGI_ADAPTER_DESC1.DedicatedVideoMemory`
(a full 64-bit `SIZE_T`).

That path is not expressible in cyrius today. The PE backend wires
external calls as **hardcoded kernel32 IAT reroutes** keyed to magic
syscall numbers (`ExitProcess`, `WriteFile`, `ReadFile`, `CloseHandle`,
and the v6.0.51 `0xF001-0xF006` → WaitForSingleObject / GetExitCodeProcess
/ SetHandleInformation / CreatePipe / CreateProcessW / GetCommandLineW).
DXGI needs two things the backend lacks:

1. **A non-kernel32 IAT import** — `CreateDXGIFactory1` lives in
   `dxgi.dll`, not kernel32. There's no way to declare/import a function
   from an arbitrary DLL from cyrius source.
2. **COM vtable (indirect) calls** — `EnumAdapters1`/`GetDesc1`/`Release`
   are virtual methods dispatched through the object's vtable
   (`call [[obj]+offset]`). cyrius emits only direct calls; there is no
   load-vtable-then-call-through-slot codegen.

## Reproduction

There is nothing to run — it's a missing capability. Concretely: there
is no cyrius source you can write that calls `CreateDXGIFactory1` (no
import mechanism) or invokes `pFactory->EnumAdapters1(...)` (no vtable
call). The v6.0.51 `0xF00N` reroutes are per-function backend edits, not
a general FFI, so each new Win32/COM entry point needs new emit.cyr code.

## Proposed fix (sketch — the cyrius team owns the design)

A general Win64 FFI would subsume the ad-hoc `0xF00N` reroutes:

1. **Arbitrary-DLL IAT imports** — let source name an imported symbol +
   its DLL (e.g. an `extern "dxgi.dll" fn CreateDXGIFactory1(...)` or a
   syscall-number-registry extension that records `(dll, symbol)`), so
   the PE import table grows a `dxgi.dll` descriptor and the call emits
   `FF 15 <disp32>` against its IAT slot.
2. **Indirect (vtable) call** — a primitive to call through a computed
   pointer: load the vtable from the COM object, load slot N, `call rax`
   with the Win64 shadow-space + 16-byte `rsp` alignment the
   CreateProcessW work already established (v6.0.51 noted >4-arg IAT
   calls must force-align `rsp`; vtable calls inherit that).

With both, DXGI enumeration is ordinary cyrius. This also unlocks other
Win32 COM/DLL surfaces (WMI-via-COM, D3D, etc.) generally.

## Consumer-side workaround (shipped)

ai-hwaccel 2.3.7 uses the `wmic Win32_VideoController` subprocess (name +
vendor + VRAM, VRAM capped at 4 GiB) plus the existing `nvidia-smi.exe`
path for precise NVIDIA VRAM. Good enough to ship; DXGI is the 2.3.8
precision upgrade once this lands. **No urgency** — purely additive.

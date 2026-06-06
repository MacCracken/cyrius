# 2026-06-05 — Windows: callptr to a REAL Win64 COM callee corrupts the cyrius caller frame

**Discovered:** 2026-06-05 building the v6.0.70 §0 DXGI demonstrator (lib/dxgi.cyr).
**Severity:** Medium — blocks the DXGI GPU-enum demonstrator; does NOT affect the
shipped v6.0.70 `callptr`/`IR_CALL_INDIRECT` primitive (verified on 4 hosts) or
the `CreateDXGIFactory1` import (S_OK on cass).
**Affects:** the `callptr` indirect-call path when the callee is a real Win64
function that uses the shadow space / SSE / a full prologue (a COM vtable method),
NOT a trivial cyrius callee. **Pinned: v6.0.71.**

## Symptom

A `callptr(method, comobj, args...)` over a real DXGI vtable method
(`EnumAdapters`/`EnumAdapters1`, `GetDesc`/`GetDesc1`) on cass (Windows x86_64)
corrupts the cyrius CALLER's frame: the COM method appears to run (it returns
`S_OK` — the staged `hr != 0` guards don't fire), but the cyrius code AFTER the
call returns garbage (consistently exit code **5**, not any of the function's
return values) or, for some slots, faults with `STATUS_ACCESS_VIOLATION`
(0xC0000005). Reproducible regardless of which method slot is used.

## What it is NOT (isolated during v6.0.70)

- **NOT the callptr primitive.** `tests/tcyr/callptr.tcyr` passes 7/7 on x86 + pi;
  `cphw` returns 42 on cass + ecb. Crucially, callptr with a **loaded callee**
  (`var fp = load64(&slot); callptr(fp, 20, 22)` and a 3-arg variant) returns **42
  on cass** — so loaded-callee dispatch + 2/3-arg marshalling + Win64 shadow work.
- **NOT a vtable-slot error.** Both `EnumAdapters` @ slot 7 (base IDXGIFactory) and
  `EnumAdapters1` @ slot 12 (IDXGIFactory1) fail; `AddRef` @1 / `Release` @2 run
  without an obvious crash. Slot indexing (`load64(vtbl + slot*8)`) is consistent.
- **NOT a frame-slot collision.** An array local before a callptr (`var arr[16]; …;
  callptr(&fn,…)`) leaves the array intact on x86 (exit 42), so the GFLC temp-slot
  allocation doesn't overlap real locals.
- **NOT obviously alignment.** On paper rsp is 16-aligned at the `call` (body
  rsp%16=0; 3 pushes → %16=8; ECALLPOPS pops + `sub rsp,0x20` → %16=0; the call's
  retaddr push → callee entry %16=8 — the Win64 contract). The standalone callptr
  shadow path is the same bytes as a normal call, and kernel32 IAT calls work.

## Hypothesis

Real Win64 callees do something trivial cyrius callees don't — spill all 4 arg
regs to the 32-byte shadow home, use xmm6-15 / SSE on the stack, or rely on a
flag/DF state — and a subtle edge in the callptr call frame (shadow extent,
a stray non-16 alignment in a *large* frame, or a clobbered callee-saved reg)
corrupts the caller. The trivial-callee tests don't exercise it. **Needs a
Windows debugger (windbg / x64dbg) on cass to single-step the callptr→COM call
and watch what the COM method writes / what's corrupt on return** — blind remote
rounds can't pin it.

## Reproduction (v6.0.70 cycc, CYRIUS_TARGET_WIN=1)

A function (callptr needs a fn frame) that: sets IID_IDXGIFactory1, calls
`syscall(0xF012, &iid, &pFactory)` (CreateDXGIFactory1 → S_OK), loads the vtable
`load64(load64(&pFactory))`, then `callptr(load64(vtbl + 7*8), fac, 0, &pAdapter)`
(EnumAdapters@7) — returns garbage/AV instead of reaching the post-call code.
(`/tmp` probes `dxgiB`/`dxgiE`/`dxgiD` from the v6.0.70 session.)

## DXGI constants for the demonstrator (verified layout, for when the call works)

- **IID_IDXGIFactory1** `{770aae78-f26f-4dba-a829-253c83d1b387}` → 16 bytes:
  `78 AE 0A 77  6F F2  BA 4D  A8 29 25 3C 83 D1 B3 87`.
- COM object: vtable ptr at `obj[0]`; method N at `load64(vtbl + N*8)`.
- IUnknown: QueryInterface@0, AddRef@1, Release@2. IDXGIObject: 3-6.
  IDXGIFactory: EnumAdapters@7, MakeWindowAssociation@8, GetWindowAssociation@9,
  CreateSwapChain@10, CreateSoftwareAdapter@11. IDXGIFactory1: EnumAdapters1@12,
  IsCurrent@13.
- IDXGIAdapter: EnumOutputs@7, GetDesc@8, CheckInterfaceSupport@9.
  IDXGIAdapter1: GetDesc1@10.
- DXGI_ADAPTER_DESC(1): Description[128]WCHAR @0 (256 B); VendorId @256 (Intel=0x8086);
  DeviceId @260; SubSysId @264; Revision @268; **DedicatedVideoMemory @272** (SIZE_T).
  (allocate the desc buffer ≥ 320 bytes — `var desc[320]`.)

## Follow-up (v6.0.71)

1. Attach a Windows debugger on cass; single-step a callptr→EnumAdapters call;
   identify the corruption (caller-saved-reg / shadow / alignment / flag).
2. Fix the callptr call frame for real-Win64 callees; add a cass regression that
   callptr's a real Win64 fn (e.g. a kernel32 entry) and checks a known result.
3. Write `lib/dxgi.cyr` (`#ifdef CYRIUS_TARGET_WIN`) — `dxgi_vram_bytes()` via the
   CreateDXGIFactory1 → EnumAdapters1 → GetDesc1 → DedicatedVideoMemory chain;
   verify on cass against the GPU's real VRAM. (cass GPU at filing: Intel UHD 600.)

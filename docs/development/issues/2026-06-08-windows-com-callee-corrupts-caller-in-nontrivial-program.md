# windows: callptr -> real-Win64-COM chain corrupts the cyrius caller in a non-trivial program (residual of the 2026-06-05 frame-corruption issue)

- **Filed**: 2026-06-08 (v6.1.5, surfaced integrating DXGI precise VRAM into ai-hwaccel)
- **Affects**: `src/backend/x86/emit.cyr` `ECALLPTR_PE` / the callptr -> real-Win64-COM-callee path on `CYRIUS_TARGET_WIN`. Real GPU + DXGI only (does not reproduce under wine — no COM path).
- **Severity**: Medium. Blocks any **real** consumer use of the v6.0.70 §0 COM-vtable capability: the isolated probe works, but a program that does ordinary work after a COM call (here a `str_builder` append) gets silently corrupted output. ai-hwaccel's DXGI precise-VRAM feature is gated OFF (`-D AI_HWACCEL_DXGI`) and stays on the WMI path until this lands.
- **Relation**: the **RESIDUAL** explicitly deferred in
  `archived/2026-06-05-windows-com-vtable-real-callee-frame-corruption.md`
  ("a second, subtler interaction the alignment fix doesn't cover … needs a
  Windows debugger single-stepping on cass"). The 6.0.71 `and rsp,-16`
  alignment fix and the 6.0.86 frame-slot-aliasing fix (callee on the stack +
  `call rax`) cleared `tests/win/dxgi_probe.cyr` (exit 42) and `lib/dxgi.cyr`'s
  standalone `dxgi_vram_bytes()`, but NOT the general post-COM case.

## Summary

A `callptr` to a real Win64 COM vtable method (the DXGI
`CreateDXGIFactory1 -> EnumAdapters1 -> GetDesc1 -> Release` chain) corrupts
the cyrius **caller's** subsequent execution. The COM methods themselves run
and return correct values; the damage shows in cyrius code that runs **after**
the chain returns. Concretely, a `str_builder_add_cstr(sb, "true")` performed
after `dxgi_vram_bytes()` emits garbled bytes instead of `"true"`.

This is invisible to `tests/win/dxgi_probe.cyr` because that probe does nothing
after the COM chain except compare integers and `return 42`. Any real program
that keeps working after the call hits it.

## Reproduction

`docs/development/issues/repros/2026-06-08-windows-com-callee-corrupts-caller-nontrivial.cyr`
(uses only cyrius `lib/dxgi.cyr` + `lib/str.cyr` — no external logic):

```
fn run(): i64 {
    var v = dxgi_vram_bytes();                   # cyrius's verified COM chain
    var sb = str_builder_new();
    var a1 = str_builder_add_cstr(sb, "available=");
    var a2 = str_builder_add_cstr(sb, "true");   # <-- garbled on return
    var s = str_builder_build(sb);
    var w = syscall(1, 1, str_data(s), str_len(s));
    return v;
}
fn main(): i64 { alloc_init(); var r = run(); return 0; }
```

Build + run:

```
cycc_win < repros/2026-06-08-windows-com-callee-corrupts-caller-nontrivial.cyr > repro.exe
# copy repro.exe to a real-GPU Windows host (cass), run, capture stdout
```

- **Expected stdout**: `available=true`
- **Actual (v6.1.5, cass, Intel UHD 600)**: `available=` followed by bytes
  `85 31 00` where `74 72 75 65` (`"true"`) is expected. The `"available="`
  append (first after the COM call) survives; the `"true"` append (second) is
  corrupted — pointing at transient post-call state (a clobbered/again-misused
  register or flag), not a one-shot stack smash.

### Independent confirmations (cass, v6.1.5)

- `tests/win/dxgi_probe.cyr` -> **exit 42** (COM chain itself is fine).
- Minimal nested-heap harness: cyrius `dxgi_vram_bytes()` called from a nested
  helper, with a heap sentinel byte written before and read after -> sentinel
  intact (nesting + heap alone do NOT trigger it).
- The same harness with a `str_builder_add_cstr("true")` after the call ->
  **garbled** (the repro above). The discriminator is doing real post-COM work,
  specifically a string copy.
- ai-hwaccel full pipeline with the DXGI pass on: the JSON serializer's
  `_json_bool` (`str_builder_add_cstr(sb, "true")`) emits a corrupt `available`
  value for EVERY profile — i.e. the COM call breaks unrelated downstream
  serialization. With the DXGI call compiled-in but short-circuited at runtime,
  output is clean -> it is the **runtime COM call**, not code presence/layout.

## Hypothesis

The COM callee path leaves some caller-visible state wrong on return that a
trivial integer-only continuation never observes but a `rep movs`-style string
copy does. Candidates to check on cass with a debugger, single-stepping the
return from the callptr:

- **Direction flag (DF)** left set by the callee / not cleared by cyrius before
  the next `rep movsb` in `str_builder_add_cstr` (would corrupt a copy exactly
  like this; ABI says DF must be clear on call boundaries, but verify cyrius
  isn't relying on that without a `cld`).
- A **callee-saved register** (rsi/rdi/r12-r15/rbp, or xmm6-15) that cyrius
  treats as preserved but is wrong after the aligned `and rsp,-16` /
  `mov rsp,rbx; pop rbx` ECALLPTR_PE epilogue interacts with the COM frame.
- The "first append fine, second garbled" pattern suggests state that is
  re-established once then re-broken — worth watching rsi/rdi/DF across the two
  `str_builder_add_cstr` calls.

## Suggested next step

Attach windbg/cdb on cass, break at the instruction after the callptr `call
rax` in `run()`, dump DF + all callee-saved regs, then step into the first vs
second `str_builder_add_cstr` and watch which input register is wrong on the
corrupted one. A `cld` (or a DF save/restore) at the ECALLPTR_PE return, or
restoring the offending callee-saved reg, is the likely fix.

## Workaround (consumer side)

None within the calling program — reproduces with cyrius's own `lib/dxgi.cyr` +
`lib/str.cyr`. Consumers must avoid the real COM path until fixed. ai-hwaccel
keeps Windows GPU VRAM on the WMI `Win32_VideoController.AdapterRAM` path
(4 GiB-capped) and gates the DXGI pass behind `-D AI_HWACCEL_DXGI` (off).

# fnptr: fncall0..8 have no CYRIUS_TARGET_AGNOS branch → indirect calls return 0 on agnos

> **RESOLVED — cycc 6.1.13 (2026-06-08).** Added a `CYRIUS_TARGET_AGNOS` +
> `CYRIUS_ARCH_X86` asm branch in-place to each of `fncall0`..`fncall8`,
> byte-identical to that function's existing Linux/x86 SysV block (per the
> ⚠ note — no shared helper, the `[rbp-N]` offsets are frame-layout-coupled).
> A/B-verified on the real `--agnos` emit: a `fncall2(&fn,0,42)` program emits
> **0** `call rax` before the fix, **1** after. x86 cycc self-host byte-identical
> (fnptr.cyr isn't compiled into cycc); check.sh 87/87; 169 tcyr clean. Sibling
> sweep: `lib/fdlopen.cyr` has the same Linux-only asm gap but is the
> dlopen/ld.so/auxv path agnos static ring-3 binaries never reach — flagged, left
> as-is. See CHANGELOG [6.1.13]. agnoshi can retire `scripts/patch-fnptr-agnos.py`
> after re-vendoring.

- **Filed**: 2026-06-08 (cycc 6.1.12, surfaced by agnoshi 1.4.8 on the agnos kernel target)
- **Affects**: `lib/fnptr.cyr` — `fncall0` (L62), `fncall1` (L119), `fncall2` (L175), `fncall3` (L236), `fncall4` (L302), `fncall5` (L373), `fncall6` (L452), `fncall7` (L553), `fncall8` (L657). Every one guards its inline-asm body on `#ifdef CYRIUS_TARGET_LINUX` / `_MACOS` / `_WIN` with **no `CYRIUS_TARGET_AGNOS` branch**.
- **Severity**: **High** for the agnos emit target. Silent (no `ud2`, no diagnostic). Breaks the entire `Allocator` vtable layer and every function-pointer consumer (`vec`/`str`/`hashmap` via `default_alloc()`), so most non-trivial agnos-target programs fault before doing useful work. Host/Linux/macOS/Windows unaffected.

## Summary

On the agnos target each `fncallN` degenerates to:

```cyrius
fn fncall2(fp, a, b): i64 {
    var result = 0;
    #ifdef CYRIUS_TARGET_LINUX  ... #endif   # not defined on agnos
    #ifdef CYRIUS_TARGET_MACOS  ... #endif   # not defined on agnos
    #ifdef CYRIUS_TARGET_WIN    ... #endif   # not defined on agnos
    return result;                            # → always returns 0 on agnos
}
```

`cyrius build --agnos` predefines `CYRIUS_TARGET_AGNOS` and **deliberately not** `CYRIUS_TARGET_LINUX` (`src/main.cyr:866-871`, comment: *"agnos ring-3 … NOT CYRIUS_TARGET_LINUX … agnos-specific behavior is gated on #ifdef CYRIUS_TARGET_AGNOS"*). So none of the asm branches compile in, and every indirect call returns 0.

This is the **exact bug class the file already documents for macOS** (the `v5.9.38` comment repeated in each function: *"Pre-fix this branch was missing entirely — fncallN returned 0 on Mach-O builds, cascading through alloc_via → str_builder_new → SIGSEGV."*). The agnos target was added later (`CYRIUS_TARGET_AGNOS`, ~6.0.48–.49) and `fnptr.cyr` was never given the parallel branch.

## Impact chain (how it surfaces)

`alloc_via` / `realloc_via` / `free_via` / `reset_via` (`lib/alloc.cyr:296-313`) dispatch the allocator vtable through `fncall2`/`fncall4`/`fncall1`. With those returning 0:

- `default_alloc()` builds a valid `Allocator` (its own `alloc(40)` is the direct global bump, which works), **but** `vec_new_a()` → `alloc_via(a, 24)` returns **0** → `vec_new()` returns **0**.
- The first consumer to dereference that null vec faults. In agnoshi 1.4.8 that is `CommandHistory_new() → vec_new()` (history.cyr:13), called from `interactive_loop` *after* the banner prints and *before* the first prompt: `store64(p, entries)` stores the null fine, then `vec_len(entries)` = `load64(0+8)` faults in ring 3 → silent #PF → `cli; hlt`. **Symptom: agnsh prints its full banner, then dies before the prompt.** (This burned ~a week of misdiagnosis as a "ring-3 stack overflow from getenv"; it is neither getenv nor the stack.)

Reproduced under QEMU (gnoboot + OVMF, real agnos 1.43.7 kernel) — not iron-specific. Isolation probe in a ring-3 agnos program:

```
CAS-WORKS          atomic_cas ok
DA-OK              default_alloc() returns a valid allocator
FP-NONZERO         &fn is a valid pointer
FNCALL2-BROKEN     fncall2(&fn, 0, 42) != 1042     ← the bug
ALLOCFP-NONZERO    allocator alloc_fn slot is correct
ALLOCVIA-ZERO      alloc_via(da, 24) == 0          ← consequence
```

## Fix

Add a `CYRIUS_TARGET_AGNOS` + `CYRIUS_ARCH_X86` branch to **each** of `fncall0`..`fncall8`, byte-identical to that function's existing `CYRIUS_TARGET_LINUX` + `CYRIUS_ARCH_X86` `asm { … }` block. agnos is x86_64 ELF using the SysV register-arg convention, identical to Linux/x86, so the same opcodes and the same `[rbp-N]` offsets are correct. e.g. for `fncall2`:

```cyrius
    var result = 0;
    #ifdef CYRIUS_TARGET_AGNOS
    #ifdef CYRIUS_ARCH_X86
    asm {
        0x48; 0x8B; 0x75; 0xE8;    # mov rsi, [rbp-24] (b)
        0x48; 0x8B; 0x7D; 0xF0;    # mov rdi, [rbp-16] (a)
        0x48; 0x8B; 0x45; 0xF8;    # mov rax, [rbp-8]  (fp)
        0xFF; 0xD0;                # call rax
        0x48; 0x89; 0x45; 0xE0;    # mov [rbp-32], rax (result)
    }
    #endif
    #endif
    #ifdef CYRIUS_TARGET_LINUX
    ...
```

Cleanest implementation: have the agnos predefine also imply the Linux/x86 SysV asm path — either widen the existing guards (if the preprocessor gains `defined(A) || defined(B)`), or have `cyrius build --agnos` additionally predefine a shared `CYRIUS_ABI_SYSV_X86`-style symbol that `fnptr.cyr` (and any other Linux-gated SysV asm) keys on. A grep for `#ifdef CYRIUS_TARGET_LINUX` across `lib/` will surface sibling files with the same latent agnos gap.

### ⚠ Implementation note (do not refactor into a shared/standalone helper)

The asm bodies use hardcoded `[rbp-N]` offsets that are **coupled to cycc's per-definition frame layout**. Verified empirically: a *separate-file* re-definition of `fncall2` (same signature, same `var result = 0;` + same asm) is laid out differently by cycc — it spilled callee-saved r12–r15 first and placed the params at `[rbp-48/-56/-64]` with `result` in `rbx` — so the `[rbp-8/-16/-24]` asm reads garbage and calls a wild address. The fix **must be added in-place inside each existing `fncallN`** (where the offsets match that definition's layout). This frame-layout coupling is itself a sharp edge worth a follow-up (the asm should read params relative to a stable anchor, or cycc should pin the param-spill offsets these blocks assume).

## Workaround in place (consumer side)

agnoshi 1.4.x ships an idempotent stopgap until this lands: `scripts/patch-fnptr-agnos.py` clones each `fncallN`'s Linux/x86 asm under a `CYRIUS_TARGET_AGNOS` guard in the **gitignored vendored** `lib/fnptr.cyr` (run after `cyrius update`, before `cyrius build --agnos`). QEMU-verified: agnsh reaches `[ASSIST] >` and dispatches `help`/`version`/`mode`. Remove that script + this note once `lib/fnptr.cyr` carries the agnos branch and agnoshi re-vendors.

## History / regression window

agnoshi 1.4.1 (built with cyrius 6.0.56) reached the agnsh prompt on iron (burn 14115, 2026-06-06). The breakage rode in with the toolchain move (6.0.56 → 6.0.87 → 6.1.x) as the agnos target was separated from `CYRIUS_TARGET_LINUX`; `fnptr.cyr` was never updated to match. The same root cause likely affects any agnos-target consumer of `vec`/`str`/`hashmap`/function pointers since that separation.

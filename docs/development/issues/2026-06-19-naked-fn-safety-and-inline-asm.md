# #naked fn — incomplete safety guards + no inline-asm path for real ISRs

> **RESOLVED in v6.2.28 (parts 1 + 2) — only the cosmetic part-3 residuals remain.**
> v6.2.27 shipped the `#naked` *attribute* (frameless emit, token 133) with 3
> critical bugs fixed but believed `#naked` a partial building block. **The .27
> premise was wrong**: a v6.2.28 premise-check found cyrius has had inline asm
> (`asm{}` blocks, the `iretq` mnemonic) all along — the only gap was the aarch64
> `eret` mnemonic. v6.2.28 fixed both open parts:
>
> - **Part 1 (safety guards) — FIXED.** The guards now fire: (a) a DCE force makes
>   a `#naked` fn always-reachable (`src/main.cyr`, `if (_naked_pending==1)
>   { dce_reachable=1; }`) so a non-underscore address-taken ISR is no longer
>   stubbed-and-bypassed; (b) the guards' `ERR_MSG(S, msg, strlen(msg))` was
>   *segfaulting silently* — `strlen` lives in `lib/string.cyr`, which the compiler
>   does not include, so the call hit an undefined fn and the guard aborted with no
>   message. Rewrote both guards to a string-literal + hardcoded byte-count (the
>   working `ERR_MSG` pattern). A `#naked` fn with a param or a `return` now hard-
>   errors with a clear message; verified by negative probes.
> - **Part 2 (inline asm) — was never missing.** `asm{}` + `iretq` shipped; added
>   the one-line aarch64 `eret` mnemonic (`src/backend/aarch64/emit.cyr` ASM_MNEMONIC,
>   `0x74657265 → EW 0xD69F03E0`). A real ISR is now writable on both arches:
>   `#naked fn isr() { asm { iretq } }` (x86) / `{ asm { eret } }` (aarch64).
>   `tests/tcyr/naked_fn_attribute.tcyr` updated to a real `asm{iretq}` ISR.
>
> Only the **part-3** cosmetic residuals below remain (macho/PE no-op,
> ELF64-inert-on-aarch64) — low priority; archive this issue once those are
> addressed or explicitly deferred.

**Filed:** 2026-06-19 · **Resolved (parts 1+2):** v6.2.28
**Parent:** v6.2.27 D3 (`#naked`).
**Severity:** ~~P2~~ → resolved; part-3 residuals are P3 cosmetic.

## 1. Safety guards don't fire on DCE-stubbed naked fns (review P2 ×2)

v6.2.27 added two hard-error guards in `src/frontend/parse_fn.cyr`:
- `PARSE_RETURN` rejects a `return` inside a `#naked` fn (a naked fn emits no
  epilogue, so a `return` would jump to a non-existent epilogue and fall through
  into the next fn).
- The param-count store (~`parse_fn.cyr:2106`) rejects a `#naked` fn with
  parameters (params emit rbp-relative arg-home stores, but a naked fn has rbp=0
  → fault).

Both guards live inside `PARSE_FN_DEF`, so they only fire for a **fully-parsed**
naked fn. A non-underscore, unreferenced naked fn is **DCE-stubbed** in pass-2
(`src/main.cyr` ~1506: emit `xor eax,eax; ret`, skip the body) — `PARSE_FN_DEF`'s
body parse + the param check are bypassed, so the guards never run. The catch: a
realistic ISR is **address-taken** (its address goes in the IDT), and the
address-taken DCE-exemption is determined *after* parsing, so at parse time the
ISR is still DCE-eligible → stubbed → guards bypassed. (The DCE-stub *leak*
SIGSEGV is already fixed — main keeps its frame; this is only about the
param/return guards' coverage.)

**Fix options (v6.2.28):** (a) make DCE never stub a `#naked` fn (always emit it
via real `PARSE_FN_DEF` — a naked ISR is referenced by address, not by call, so
DCE's call-graph reachability is the wrong test for it); or (b) hoist the
param/return validity check into pass-1 (the declaration scan, which always runs);
or (c) reject params at the signature scan and `return` at the lexer/pass-1 level.
Option (a) is cleanest and also makes address-taken ISRs survive DCE correctly.
Add a NEGATIVE-test harness entry (a `#naked fn isr(x)` / `{ return 0; }` that must
fail to compile) once the guard fires on the stubbed shape.

## 2. No inline-asm → real ISRs aren't writable (the usability prereq)

cyrius has **no inline-asm mechanism** (no `asm(...)`, no emit-bytes builtin —
grep-confirmed at v6.2.27). A real ISR body must end in `iretq` (x86) / `eret`
(aarch64), which today cannot be expressed in pure cyrius. So `#naked` currently
only provides the *frameless attribute*; the body can only contain frame-free
cyrius statements (no locals/return), which is not enough for an interrupt handler.

**Fix (v6.2.28 or its own slot):** an inline-asm path — either a general
`asm("...")` statement, or a minimal set of intrinsics (`emit_iretq()`,
`emit_eret()`, `emit_cli()`, `emit_sti()`, raw `emit_bytes(...)`) sufficient for
ISR prologue/epilogue. This is the actual AGNOS-kernel-IDT enabler; `#naked` is the
prerequisite that v6.2.27 landed.

## 3. Minor review residuals (low priority)

- **`#naked` is a no-op on the macOS/Windows forks** (review P2, 1/2 votes): the
  x86-macho / aarch64-macho pass-2 dispatches consume-and-ignore token 133 without
  arming `_naked_pending`, so `#naked` is silently ignored on Mach-O/PE. Harmless
  today (`#naked` is bare-metal-ELF-only — macOS/Windows have no bare-metal kernel
  target), but mirror the ELF arming into those forks' pass-2 for consistency if a
  cross-target ISR story ever appears.
- **`CYRIUS_ELF64_KERNEL=1` is inert on the aarch64 backend** (review P3): the
  aarch64 triple injects it but the aarch64 emit ignores it. Harmless no-op; either
  gate the injection to the x86 path or document that aarch64 kernel ELF class is
  fixed.

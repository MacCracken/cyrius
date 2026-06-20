# #naked fn — incomplete safety guards + no inline-asm path for real ISRs

> **OPEN — follow-up to v6.2.27 (the bare-metal frontend half).** v6.2.27 shipped
> the `#naked` *attribute* (frameless emit: no prologue/epilogue/frame, token 133)
> with its 3 critical bugs fixed (the f64v_dot token-128 collision, the DCE-stub
> `_naked_pending`-leak SIGSEGV, and — separately — the aarch64-triple wrong-arch
> fallback). The adversarial review (19 agents, 8 confirmed) surfaced that `#naked`
> is a **partial building block**, not a finished ISR feature. The remaining work
> is pinned to the **v6.2.28 bare-metal runtime half**, where real ISRs first get
> exercised (the boot gate + the AGNOS kernel IDT).

**Filed:** 2026-06-19
**Parent:** v6.2.27 D3 (`#naked`). **Pinned to:** v6.2.28 (runtime half).
**Severity:** P2 (safety guards) + the inline-asm prereq (blocks usable ISRs).

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

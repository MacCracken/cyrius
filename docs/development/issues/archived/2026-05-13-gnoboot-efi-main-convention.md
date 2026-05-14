# `fn efi_main(handle, st)` convention for UEFI entry — open (enhancement)

**Discovered:** 2026-05-13 during gnoboot Step 4 (the first cyrius-fn-driven gnoboot code, post the pure-asm-only Step 3 banner)
**Severity:** Low — workaround works; gnoboot v0.1.0 can ship without this. Enhancement / ergonomics, not a bug.
**Affects:** cc5 5.11.49 (`CYRIUS_TARGET_EFI=1` mode)

## Summary

Under `CYRIUS_TARGET_EFI=1`, cyrius emits a correct UEFI Application
(subsystem 0xA, no Win32 imports, `.reloc` populated, `RELOCS_STRIPPED`
clear). Verified end-to-end on QEMU OVMF — gnoboot's banner + a real
`bs->HandleProtocol(ImageHandle, &LoadedImageGuid, &out)` firmware call
both return cleanly. **The language works for this use case as-is.**

What it's missing is a clean **entry convention**. Today the consumer
has to hand-write a small trampoline that:

1. Captures the firmware-supplied entry args (RCX = ImageHandle,
   RDX = SystemTable\* per the UEFI MS x64 ABI contract) before
   anything else clobbers them.
2. Translates / dispatches them into the user's cyrius code, since
   the cyrius "user program" entry doesn't automatically receive
   them.

This works (proof-of-life in gnoboot, see below) but is more delicate
than it should be — small ordering bugs around top-level
`var X = expr;` vs. `asm` interleaving cost a debugging cycle.
Proposing a `fn efi_main(handle, st)` convention to make the entry
shape obvious and bulletproof, paralleling the `fn main()` /
`syscall(SYS_EXIT, ...)` epilogue pattern that cyrius already has for
Linux/macOS.

## What works today (gnoboot's current entry shape)

```cyrius
kernel;

var marshal_a0[8];
var marshal_fp[8];

fn print_msg(handle, st) {
    var con_out = load64(st + 0x40);
    var out_str = load64(con_out + 0x08);
    store64(&marshal_a0, con_out);
    store64(&marshal_fp, out_str);
    # ... agnos-shim `var p = &g; asm { ... }` pattern works fine inside a fn body
    # ...
    return 0;
}

# === Hand-rolled trampoline ===
# 1. Build any UTF-16LE strings via store8 calls.
# 2. Capture firmware args before they're clobbered.
# 3. Get the fn pointer.
# 4. Translate ABI and call.
store8(&msg + 0, 0x66); # ... lots of these

asm {
    0x49; 0x89; 0xCE;          # mov r14, rcx  — save ImageHandle
    0x49; 0x89; 0xD7;          # mov r15, rdx  — save SystemTable*
}

var fp = &print_msg;            # cyrius: rax = &print_msg

asm {
    # rax = &print_msg (from cyrius's `var fp` lea above)
    # NB: cyrius internal ABI for user fns under CYRIUS_TARGET_EFI
    # appears to be MS x64 (the callee saves rcx/rdx to local slots,
    # not rdi/rsi — verified by objdump), so pass args in rcx/rdx.
    0x4C; 0x89; 0xF1;          # mov rcx, r14   ; arg 0 (ImageHandle)
    0x4C; 0x89; 0xFA;          # mov rdx, r15   ; arg 1 (SystemTable*)
    0x48; 0x83; 0xEC; 0x08;    # sub rsp, 8  (re-align stack to 16 mod 16 for the call)
    0xFF; 0xD0;                # call rax
    0x48; 0x83; 0xC4; 0x08;    # add rsp, 8
    0x31; 0xC0;                # xor eax, eax  ; EFI_SUCCESS
    0xC3;                      # ret to firmware
}
```

This compiles cleanly under cyrius 5.11.49 (`CYRIUS_TARGET_EFI=1`) and
boots under qemu+OVMF. Verified by `gnoboot/tests/ovmf_smoke.sh`.

## What the friction points are (in order discovered)

### A. No documented "where cyrius hands off to user code" contract

The trampoline above works only because the consumer disassembled
their own binary, watched what registers cyrius's emit clobbered,
and noticed that R14/R15 (callee-saved in *both* SysV and MS x64)
survived across cyrius's `var fp = &print_msg;` emit while RCX
did NOT survive top-level `store8` calls.

A consumer who didn't have the agnos boot-shim and lib/fnptr.cyr
to reverse-engineer would have a hard time. The contract is: "after
the cyrius prologue jmp lands you in top-level code, the callee-saved
registers (RBX/RBP/R12-R15) are preserved through cyrius's emit, but
caller-saved (RAX/RCX/RDX/R8-R11) are fair game."

That's defensible behavior; it just needs to be findable.

### B. lib/fnptr.cyr documents SysV but TARGET_EFI fns appear to use MS x64

`lib/fnptr.cyr` opens with:

> Calling convention (both arches — cyrius's own, NOT AAPCS64's
> x0..x7): Args 1-6 in registers: rdi/rsi/rdx/rcx/r8/r9 (x86_64 SysV)

But `objdump -d` on gnoboot's `print_msg(handle, st)` under
`CYRIUS_TARGET_EFI=1` shows the prologue saving RCX and RDX (not RDI
and RSI) into local slots — i.e. MS x64 ABI. The two are
self-consistent (TARGET_EFI uses MS x64 at the firmware-entry
boundary, and apparently propagates it to user-fn calls), but
`lib/fnptr.cyr`'s comment is no longer accurate for TARGET_EFI mode
(and its `fncallN` asm doesn't have a TARGET_EFI / TARGET_WIN `#ifdef`
branch — would silently return 0 if used). Doc & code-branch update
both worth doing.

### C. No fn-based entry convention

The consumer has to hand-roll the trampoline above. It's tractable
once you know the trick, but it's exactly the kind of "everyone
re-rolls the same 20 lines" friction the canonical-convention pattern
(`fn main()` + `var r = main(); syscall(SYS_EXIT, r);`) was designed
to dissolve for Linux/macOS targets.

## Proposed enhancement

Adopt a **`fn efi_main(handle, st)`** convention for
`CYRIUS_TARGET_EFI=1`, paralleling `fn main()`:

- If `fn efi_main(handle, st)` is defined, cyrius emits a `_start`
  that:
    1. Captures the firmware-passed RCX / RDX entry registers.
    2. Sets up a re-aligned stack (16-byte aligned for our internal call).
    3. Calls `efi_main(handle, st)` using whatever ABI cyrius uses
       for internal calls under TARGET_EFI (currently MS x64 by
       observation).
    4. On return, takes `EFI_STATUS` from RAX and `ret`s to firmware.
- Existing `kernel;` + top-level-asm + top-level-`var = &fn` pattern
  stays supported (no breaking change). Consumers who want raw
  control of the entry continue to get it. The convention is opt-in:
  if `efi_main` isn't defined, cyrius does what it does today.

The exact signature can be whatever the language prefers — a fixed
two-arg shape `fn efi_main(handle, st)` is the simplest; the cyrius
agent may have a better idea (e.g. a typed `EFI_HANDLE`/`EFI_SYSTEM_TABLE`
where those become real types in cyrius's stdlib).

Under that convention, the gnoboot main.cyr collapses from ~50 lines
of trampoline + store8 + asm to:

```cyrius
kernel;

fn efi_main(handle, st) {
    # ... real gnoboot work, normal cyrius
    return 0;   # EFI_SUCCESS
}
```

with the cyrius lib supplying any small helpers (e.g. an `efi_print`
trampoline that does the SysV→MS x64 translation around a firmware
function pointer call — see also the related enhancement issue
`2026-05-13-gnoboot-byte-array-literal.md` for the related missing
byte-array literal that makes UTF-16LE string handling verbose).

## Reproduction (consumer side — works as-is, included for context)

The working gnoboot Step 4 source is at
`/home/macro/Repos/gnoboot/src/main.cyr` (in the macro devbox). It
boots through QEMU OVMF and prints "fn entry works" on the firmware
ConOut. Build + smoke test:

```sh
cd /home/macro/Repos/gnoboot
CYRIUS_TARGET_EFI=1 cyrius build src/main.cyr build/BOOTX64.EFI
EXPECT="fn entry works" tests/ovmf_smoke.sh
```

For the friction-point disassembly evidence:

```sh
objdump -d build/BOOTX64.EFI | sed -n '/^0000000140001000/,/^Disassembly/p'
```

— look at the `print_msg` prologue circa `.text+0x29`:

```
mov %rcx, -0x8(%rbp)       ; first arg from rcx → handle slot
mov %rdx, -0x10(%rbp)      ; second arg from rdx → st slot
```

That's MS x64, not SysV, contradicting `lib/fnptr.cyr`.

## Root cause (speculation — cyrius agent please verify)

Not a bug. The friction is that:

- `_TARGET_EFI_APPLICATION` is a recent addition (cyrius 5.11.47-5.11.49,
  per CHANGELOG). The entry-point convention question hadn't been
  surfaced yet because there was no consumer past the `efi_probe.cyr`
  single-asm probe.
- `lib/fnptr.cyr` predates the EFI work and was written when cyrius's
  user-binary targets were all SysV.

## Proposed fix (sketch — cyrius agent owns the design)

1. Cyrius main.cyr (or wherever `_start` lives under kmode +
   `_TARGET_EFI_APPLICATION`): if the parser saw a `fn efi_main`
   declaration, emit the trampoline; otherwise fall through to
   today's "top-level code runs" shape.
2. `lib/fnptr.cyr`: add a `#ifdef CYRIUS_TARGET_EFI` branch (or
   `CYRIUS_TARGET_WIN`) mirroring the Linux/macOS asm but with MS x64
   register loads. At minimum, update the doc-comment to note the
   per-target ABI difference.

If the design takes more thought, this is a perfectly reasonable
2026-05-x slot rather than a "right now" item. gnoboot can ship
v0.1.0 without it.

## Consumer-side workaround (if any)

The hand-rolled trampoline at the top of this issue. Costs ~20 lines
of asm + the awareness of "use callee-saved regs for arg capture,
don't trust caller-saved across cyrius emits."

## Pointers

- Path C plan: `agnosticos/docs/development/path-c-sovereign-uefi.md`
- gnoboot CHANGELOG entry (with constraint documentation):
  `gnoboot/CHANGELOG.md` § *Known cyrius constraints*
- Companion enhancement issue:
  `cyrius/docs/development/issues/2026-05-13-gnoboot-byte-array-literal.md`
- Related earlier-resolved issue:
  `cyrius/docs/development/issues/archived/2026-05-13-gnoboot-uefi-application-emit.md`

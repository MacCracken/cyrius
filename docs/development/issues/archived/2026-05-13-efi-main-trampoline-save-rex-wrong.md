# `fn efi_main` trampoline: entry-save uses wrong REX prefix — bug

**Discovered:** 2026-05-13 during gnoboot Step 4 verification against cyrius 5.11.52
**Severity:** High — `fn efi_main(handle, st)` convention crashes on first invocation (NULL pointer deref). Workaround = revert to manual trampoline (which was the pre-5.11.52 pattern), but the headline ergonomic of v5.11.52 doesn't actually work.
**Affects:** cc5 5.11.52 (released 2026-05-13; first cycle where the convention shipped)
**Companion:** the ergonomic enhancement that introduced this code path is `cyrius/docs/development/issues/archived/2026-05-13-gnoboot-efi-main-convention.md`.

## Summary

Cyrius 5.11.52's auto-emitted `fn efi_main(handle, st)` trampoline
crashes on the first firmware-call inside efi_main because the
**entry-save** instructions are encoded with the wrong REX prefix —
the destination register (r14/r15) is in the *r/m* field of the
ModR/M byte and therefore needs `REX.B=1`, but cyrius emits
`REX.W+REX.R=0x4C` instead of `REX.W+REX.B=0x49`. The bytes that
were supposed to save firmware's RCX/RDX into R14/R15 instead
overwrite RSI/RDI from undefined R9/R10. After gvar_inits clobber
RCX/RDX, the restore (which is correctly encoded) pulls undefined
R14/R15 into RCX/RDX, hands those to efi_main as `handle`/`st`,
and the first deref crashes.

The **restore** instructions at the same trampoline emit the
correct bytes (because for `mov rcx, r14` the same source register
r14 is now in the *reg* field of ModR/M, where REX.R=1 is the
right extension). So the encoding bug is asymmetric: only the
save is wrong, the restore is fine.

## Reproduction

Minimal `kernel;` source that builds clean under cyrius 5.11.52 with
`CYRIUS_TARGET_EFI=1`, crashes immediately under QEMU+OVMF:

```cyrius
kernel;

include "lib/fnptr.cyr"

# Note: byte-array literal (v5.11.51) works perfectly — only the
# v5.11.52 trampoline save is at fault.
var msg[2] = { 0x68,0x00, 0x69,0x00, 0x0D,0x00, 0x0A,0x00 };  # "hi\r\n\0"

fn efi_print(st, m): i64 {
    var con_out = load64(st + 0x40);
    var out_str = load64(con_out + 0x08);
    return fncall2(out_str, con_out, m);
}

fn efi_main(handle, st): i64 {
    efi_print(st, &msg);    # crashes here — st is junk r15 from entry
    return 0;
}
```

Build:

```sh
CYRIUS_TARGET_EFI=1 cyrius build src/main.cyr build/BOOTX64.EFI
```

The output is a structurally-valid PE32+ EFI application
(`grub-file --is-x86-pe32+`, `objdump -p` shows
`Subsystem 0x000A`, `.reloc` present, etc.). Boot under QEMU+OVMF
(GPT disk + ESP, mcopy `BOOTX64.EFI` to `\EFI\BOOT\`) — OVMF
catches a `#PF` with `CR2 = 0x0`:

```
!!!! X64 Exception Type - 0E(#PF - Page-Fault) ...
RIP  - <inside our efi_main, at the second deref of *st-derived chain>
CR2  - 0000000000000000     ; NULL deref
RAX  - 0000000000000008     ; (offset 0x08 from a 0 pointer = 8)
```

Tested on the gnoboot v0.1.0 working tree
(`/home/macro/Repos/gnoboot`, cyrius.cyml pinned to `5.11.52`).
The full crash dump + working pure-asm Step 4 (for comparison) is
in gnoboot's `CHANGELOG.md` and the path-c plan
(`agnosticos/docs/development/path-c-sovereign-uefi.md`).

## Root cause

In the trampoline emitted at the entry-jmp target (per CHANGELOG
[5.11.52] § *Implementation*, "Save at entry … emit `4C 89 CE`
(mov r14, rcx) + `4C 89 D7` (mov r15, rdx)") — the comment is
wrong, those bytes don't encode `mov r14, rcx`.

Decoding `4C 89 CE` (the byte sequence cyrius actually emits):

| Byte | Binary | Meaning |
|------|--------|---------|
| `4C` | `0100 1100` | REX with W=1, R=1, X=0, B=0 |
| `89` | `1000 1001` | MR-form `mov r/m64, r64` (dst = r/m, src = reg) |
| `CE` | `11 001 110` | ModR/M: mod=11 (reg-direct), reg=001, r/m=110 |

With REX.R=1, the reg field extends to 1001 = **r9**.
With REX.B=0, the r/m field stays at 0110 = **rsi**.
Decoded: `mov rsi, r9`. **Not `mov r14, rcx`.**

To encode `mov r14, rcx`:

- The destination is r14 → in the r/m field with REX.B=1 (since
  r14 is encoded as `r/m=110` + REX.B=1).
- The source is rcx → in the reg field, no REX.R needed.
- ModR/M = `11 001 110` = `0xCE` (mod=11, reg=001=rcx, r/m=110=r14).
- REX = `0100 W=1 R=0 X=0 B=1` = `0x49`.
- Correct bytes: **`49 89 CE`**.

Cyrius emits `4C` (W+R) where it needs `49` (W+B). The error is
in which REX extension bit gets set.

Same problem on the second save:
- Emitted: `4C 89 D7` = `mov rdi, r10` (wrong).
- Intended `mov r15, rdx` needs `49 89 D7`.

The **restore** at the trampoline tail (`.text+0x1ee1` in the
gnoboot repro) emits the *correct* `4C 89 F1` / `4C 89 FA`
(`mov rcx, r14` / `mov rdx, r15`) — because for the restore, r14/r15
are the source (reg field, needs REX.R=1), and rcx/rdx are the
destination (r/m field, no REX.B). Same `4C` byte happens to be
right for the opposite mov direction. That's why only the save is
broken.

Anchor point: `src/main.cyr:1266` per the CHANGELOG implementation
description ("Save at entry: right after EPATCH(jmp_patch)"). The
emit pair is two adjacent calls to whatever the cyrius emit
primitive is for mov-reg-to-reg; one of them (or the helper itself)
sets REX.R when it should set REX.B for the destination-is-high-reg
case.

## Reproduction objdump evidence

From the gnoboot repro:

```
$ objdump -d build/BOOTX64.EFI | head -10
0000000140001000 <.text>:
   140001000:    e9 34 03 00 00       jmp    0x140001339
   ...

$ objdump -d build/BOOTX64.EFI | sed -n '/140001339/,/14000133f/p'
   140001339:    4c 89 ce             mov    %r9,%rsi   ← entry save — WRONG
   14000133c:    4c 89 d7             mov    %r10,%rdi  ← entry save — WRONG

$ objdump -d build/BOOTX64.EFI | sed -n '/140001ee0/,/140001ef0/p'
   140001ee1:    4c 89 f1             mov    %r14,%rcx  ← restore — CORRECT
   140001ee4:    4c 89 fa             mov    %r15,%rdx  ← restore — CORRECT
   140001ee7:    48 83 ec 28          sub    $0x28,%rsp
   140001eeb:    e8 df f2 ff ff       call   0x1400011cf
```

Both save bytes use `4C` (REX.W+R); both restore bytes use `4C`
(also REX.W+R, but here REX.R is correct because r14/r15 are the
*source*).

## Proposed fix (sketch — cyrius agent owns the design)

In the emit pair for the entry save (`src/main.cyr:1266`-ish per
the CHANGELOG):

- The first instruction should emit `49 89 CE` for `mov r14, rcx`
  (currently emits `4C 89 CE`).
- The second instruction should emit `49 89 D7` for `mov r15, rdx`
  (currently emits `4C 89 D7`).

If cyrius has a reusable mov-reg-to-reg emit primitive that takes
(dst, src) and the bug is in *that primitive* (rather than in the
trampoline emit's hard-coded bytes), fix the primitive — that
would also future-proof any other call site that moves into a
high register.

A unit test for the trampoline that asserts the byte sequence at
the entry-save site would lock this down — the regression-gate
shape used in the v5.11.49 OVMF smoke gate, or a simpler
byte-pattern check in `programs/check.cyr` (open the built EFI
binary, find the post-jmp target, verify the next 6 bytes are
`49 89 CE 49 89 D7`).

## Consumer-side workaround

gnoboot reverts to the **manual entry-trampoline** that was
working pre-5.11.52 — `kernel;` source with no `fn efi_main`
defined, top-level asm captures RCX/RDX into callee-saved R14/R15,
top-level `var fp = &user_fn;` gets the fn pointer, top-level asm
re-loads MS x64 args and calls. The byte-array literal from
v5.11.51 still works perfectly and remains a big ergonomic win.
The `lib/fnptr.cyr` MS-x64 branches now firing under
`CYRIUS_TARGET_EFI=1` (via the WIN predefine) also still works.

Pre-5.11.52 trampoline shape:

```cyrius
kernel;

include "lib/fnptr.cyr"

# (byte-array literals for msg, GUIDs, etc.)

fn user_fn(handle, st) {
    # ... normal cyrius
    return 0;
}

asm {
    0x49; 0x89; 0xCE;    # mov r14, rcx   ← correctly-encoded by hand
    0x49; 0x89; 0xD7;    # mov r15, rdx
}
var fp = &user_fn;
asm {
    0x4C; 0x89; 0xF1;    # mov rcx, r14
    0x4C; 0x89; 0xFA;    # mov rdx, r15
    0x48; 0x83; 0xEC; 0x08;    # sub rsp, 8 (re-align to 16)
    0xFF; 0xD0;          # call rax
    0x48; 0x83; 0xC4; 0x08;
    0x31; 0xC0;
    0xC3;
}
```

(The `49 89 CE` vs `4C 89 CE` distinction is the same one cyrius
got wrong at the auto-trampoline — this hand-rolled version uses
the correct bytes.)

## Pointers

- gnoboot repro working tree: `/home/macro/Repos/gnoboot/` (cyrius.cyml pinned to 5.11.52)
- gnoboot CHANGELOG (will pin to v5.11.52 once this lands)
- Path C plan: `agnosticos/docs/development/path-c-sovereign-uefi.md`
- Convention proposal that introduced the trampoline: `cyrius/docs/development/issues/archived/2026-05-13-gnoboot-efi-main-convention.md`
- Companion fix that DID land cleanly: `cyrius/docs/development/issues/archived/2026-05-13-gnoboot-byte-array-literal.md` (v5.11.51 byte-array literal — works perfectly, separate from this bug)

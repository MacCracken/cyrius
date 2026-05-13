# UEFI application PE emit mode (PE32+, subsystem = 0xA) — open

**Discovered:** 2026-05-13 during AGNOS Path C (sovereign UEFI bootloader — new repo `gnoboot`) scoping
**Severity:** High — blocks AGNOS MVP boot-to-shell on iron (closed-beta target early June 2026)
**Affects:** cc5 5.11.46 (and all prior — `_TARGET_PE` has only ever emitted Windows-CUI applications)

## Summary

`gnoboot` — the AGNOS sovereign UEFI bootloader, Cyrius-native, replacing GRUB
on the boot path — needs cyrius to emit a **UEFI Application** binary:
PE32+ with `Subsystem = 0xA (IMAGE_SUBSYSTEM_EFI_APPLICATION)`, no Windows
import table, and a `.reloc` directory.

The existing `_TARGET_PE` mode (env var `CYRIUS_TARGET_WIN=1`) emits PE32+
correctly but hardcodes:

- `Subsystem = 0x3` (WINDOWS_CUI) — UEFI firmware rejects with `Not Found`
  or refuses to invoke `LoadImage`.
- A `kernel32!ExitProcess` import table — UEFI binaries have no
  Win32 imports; all services come through the `EFI_SYSTEM_TABLE*`
  argument the firmware passes to the entry function.

Need a sibling mode — call it `_TARGET_EFI_APPLICATION`, gated by env var
`CYRIUS_TARGET_EFI=1`, sibling of `CYRIUS_TARGET_WIN=1`. Per
`[[feedback-language-extension-invasiveness]]` this should be a build flag,
not a new directive. The `kernel;` (or whatever directive we land on for
EFI apps) stays unchanged at the language surface.

## Why this is the right level of cyrius surface

The MS x64 ABI work is already done in `_TARGET_PE` — UEFI uses the same
calling convention (RCX/RDX/R8/R9 + 32-byte shadow space + 16-byte stack
alignment). PE32+ emit is already done. The deltas are entirely in:

1. **Subsystem byte**: 0x3 → 0xA when `_TARGET_EFI_APPLICATION == 1`.
2. **Import table emit**: skip the kernel32!ExitProcess emission path
   when EFI. UEFI binaries have no imports; the .idata section
   shouldn't appear at all.
3. **Base relocation directory (`.reloc`)**: UEFI firmware loads images at
   addresses it picks (memory map state at boot time). It expects either
   `IMAGE_FILE_RELOCS_STRIPPED` (rare and frowned upon) or a populated
   `.reloc` directory. Cyrius's current PE emit does not appear to
   emit base relocations (search for `IMAGE_DIRECTORY_ENTRY_BASERELOC` in
   `src/backend/pe/emit.cyr` — happy to be wrong here).
4. **DLL Characteristics**: `IMAGE_DLLCHARACTERISTICS_NX_COMPAT` (0x0100)
   + ideally `_HIGH_ENTROPY_VA` (0x0020). Good citizens. Not strictly
   required for boot but Modern UEFI firmware checks these.
5. **Entry function name**: cyrius emits `_start` for Windows; UEFI
   firmware calls whatever the PE header's `AddressOfEntryPoint` points
   at — name doesn't matter at the binary level, but the entry signature
   matters: `EFI_STATUS efi_main(EFI_HANDLE ImageHandle, EFI_SYSTEM_TABLE *SystemTable)`.
   On MS x64 ABI: `RCX=ImageHandle, RDX=SystemTable`, returns in `RAX`.

## Reproduction

Repro doesn't exist yet — `gnoboot` source is blocked on this. The
intended repro shape (post-fix):

```sh
# In a new gnoboot/ repo:
cyrius build src/main.cyr build/BOOTX64.EFI
# (cyrius.cyml has `cyrius = "5.11.X"` with the EFI emit flag set,
#  OR the wrapper sets CYRIUS_TARGET_EFI=1 explicitly)

file build/BOOTX64.EFI
# Expected: "MS-DOS executable, MZ for MS-DOS" (PE32+, subsystem=EFI)
# Verifiable with:
#   objdump -p build/BOOTX64.EFI | grep -i "subsystem"
# Should report: "Subsystem 0x0000000A (EFI application)"
```

The downstream gate (what gnoboot does with the .efi binary):

```sh
# Copy to a FAT ESP image:
mcopy -i esp.img build/BOOTX64.EFI ::/EFI/BOOT/BOOTX64.EFI
qemu-system-x86_64 \
    -drive if=pflash,format=raw,readonly=on,file=OVMF_CODE.4m.fd \
    -drive if=pflash,format=raw,file=OVMF_VARS.4m.fd \
    -drive file=esp.img,format=raw \
    -serial stdio -display none
# UEFI firmware should load BOOTX64.EFI and call efi_main.
# Pre-fix: rejected as "Not Found" or "Invalid format."
```

## Why this is the AGNOS-critical issue right now

The Path A iron-boot work (cyrius 5.11.43 ELF64 multiboot2 emit) is
correct and produces a kernel GRUB accepts. But GRUB's
`grub_relocator64_efi_boot` writes kernel register state directly into
its own `.text` (the `grub_relocator64_efi_start` stub's embedded
register-state immediates, .text 0x8AA-0x8F7), and modern UEFI firmware
(OVMF 2024+ confirmed, real-iron NUC AMD likely) enforces the UEFI
Memory Attributes Protocol RO bit on code pages. Those writes fault.

Full diagnosis: `agnosticos/docs/development/iron-boot-testing-log.md`
§ *Diagnosis 2 — 2026-05-13 GRUB relocator W^X*. AGNOS Path A (ELF64
multiboot2 via GRUB) is dead because of GRUB itself, not cyrius and not
the kernel. Resolution is Path C — sovereign UEFI bootloader (`gnoboot`),
no GRUB on the boot path. `gnoboot` will be ~2000 LoC of Cyrius
implementing: UEFI app entry → SimpleFileSystem protocol open of the ESP
→ read `/boot/agnos` + `/boot/initramfs.cpio.gz` → ELF parse and
LoadImage-pattern allocation → build sovereign boot-info struct →
`GetMemoryMap` → `ExitBootServices` → jump to kernel entry.

`gnoboot` cannot be written in any other language without breaking the
AGNOS sovereignty pattern (cyrius replaced gcc/clang/llvm; gnoboot is the
next external dep — GRUB — to dissolve). This is the canonical
"someone is working around this in production code right now" case the
issues README asks for, modulo "working around" = "cannot start writing."

## Root cause (speculation)

Not a bug — a missing mode. Anchor points in the existing PE backend
(speculation — Cyrius agent please verify):

- `src/backend/pe/emit.cyr:722` writes `Magic = 0x020B (PE32+)`. Keep.
- `src/backend/pe/emit.cyr` ~line range covering Subsystem write — emits
  `0x3`. Branch on the flag.
- Import table emit path (anchored on the kernel32!ExitProcess strings,
  IAT/ILT setup at ~line 473 per the file comment): wrap in
  `if (_TARGET_EFI_APPLICATION == 0) { ... existing path ... }`.
- New `.reloc` section emit: needed for UEFI. Per the MS PE/COFF spec
  § 6.6, each block covers up to 4 KB of an image-section page, with
  16-bit entries: top 4 bits = type (typically `IMAGE_REL_BASED_DIR64`
  = 10 for x86_64 absolute 64-bit fixups), bottom 12 bits = page-relative
  offset. Block header is `(VirtualAddress: u32, SizeOfBlock: u32)`. ~80
  LoC of new emit plus the directory-entry plumbing.
- Flag definition: new `var _TARGET_EFI_APPLICATION = 0;` near the
  existing `_TARGET_PE` in `src/backend/cx/emit.cyr:22`.
- Env-var plumbing: `src/main.cyr:989` + `src/main_win.cyr:512` (or a
  new sibling `src/main_efi.cyr`). Probably small.

## Proposed fix

Per `[[feedback-language-extension-invasiveness]]`: build-flag-based,
NOT a new language directive. The `kernel;` directive stays. Selection
is via env var `CYRIUS_TARGET_EFI=1` that sets `_TARGET_EFI_APPLICATION = 1`.
The PE backend reads that flag and:

| Behavior | When `_TARGET_EFI_APPLICATION == 0` (Windows mode) | When `_TARGET_EFI_APPLICATION == 1` (EFI mode) |
|---|---|---|
| Subsystem byte | `0x3` (CUI) | `0xA` (EFI_APPLICATION) |
| Import table | emit kernel32!ExitProcess | skip entirely (no .idata section) |
| `.reloc` directory | (today's behavior — verify) | emit populated `.reloc` |
| Entry name resolution | `_start` | same; firmware reads `AddressOfEntryPoint`, doesn't care about name |
| DLL Characteristics | as today | OR in NX_COMPAT (0x0100), HIGH_ENTROPY_VA (0x0020) |
| ABI | MS x64 (unchanged) | MS x64 (unchanged) |

Cyrius source code on the gnoboot side then looks like normal cyrius
code — no UEFI-specific syntax — with the entry function having the
expected `(handle, system_table)` signature and returning `int` (= EFI_STATUS).

Estimate: ~150-300 LoC patch under `src/backend/pe/emit.cyr` + small
plumbing in main.cyr/main_win.cyr. New `programs/efi_probe.cyr` (sibling
of `pe_probe.cyr`) would be a great verification-floor probe — emit a
minimal "call SystemTable->ConOut->OutputString('hello, uefi')" binary,
verify it boots under OVMF.

## Consumer-side workaround (if any)

**None.** gnoboot cannot start until this lands. The pe_probe-style
hand-rolled byte-emit approach is gross at gnoboot's scale (~2000 LoC
of bootloader logic — file I/O, ELF parsing, memmap consumption,
ExitBootServices). The probe is a fine *verification* artifact for
this issue's fix; it is not a substitute for proper cyrius emit.

## Acceptance criteria

1. `cyrius build src/efi_hello.cyr build/HELLO.EFI` with
   `CYRIUS_TARGET_EFI=1` produces a binary where:
   - `objdump -p HELLO.EFI` reports `Subsystem 0x0000000A (EFI application)`
   - `objdump -p HELLO.EFI` reports a non-empty `.reloc` directory
   - No `.idata` section (or an empty one)
2. `programs/efi_probe.cyr` (or equivalent) boots under
   `qemu-system-x86_64 + OVMF` and writes "hello, uefi" to the
   firmware ConOut serial.
3. `gnoboot` (separate repo, to be created) compiles against the
   same toolchain version and produces a working `BOOTX64.EFI`.
   Verified by booting AGNOS through it on QEMU OVMF, then on the
   NUC AMD iron.

## Pointers

- Path C plan (where this fits): `agnosticos/docs/development/path-c-sovereign-uefi.md`
  (drafted alongside this issue).
- Path A history (why we're moving to Path C):
  `agnosticos/docs/development/path-a-elf64-multiboot2.md` + iron-boot
  log Diagnosis 2.
- Memory pin: `[[project-agnos-bootloader-roadmap]]` (will be updated
  to reflect Path C as MVP, Path A as abandoned).
- Existing PE work reference: `src/backend/pe/emit.cyr`,
  `programs/pe_probe.cyr`, `programs/pe_probe_hello.cyr`.

# Kernel-PIE boot metadata targets the link base, not a slid base

> **OPEN — HELD, gnoboot-coupled.** Surfaced by the 2026-06-27 kernel-PIE
> ground-truth review. Deliberately NOT fixed in v6.2.45 (which shipped the
> structural gate + the `_entry_base` landmine fix): the correct fix depends on
> a decision the in-flight AGNOS `gnoboot --pie` boot test forces, and shipping
> it un-boot-tested would be the "structural ≠ verified" placebo.

**Filed:** 2026-06-27 · **Severity:** P2 (blocks live full-binary KASLR; no
consumer is mid-boot on it yet). **Owner split:** cyrius (metadata emit) +
gnoboot (slide-capable loader). **Parent:** the v6.1.x carry-in "Kernel-PIE ELF
boot-test for AGNOS KASLR" (`roadmap.md`).

## What's already correct

A `kernel; --pie` build is genuinely position-independent in its **code**.
Verified by building a kernel exercising globals, a 4-case switch jump table,
and a `&fn` function pointer:

- 0 `movabs` / 0 absolute 64-bit immediate in `.text`; the only absolute is
  `mov $0xb8000` (VGA MMIO — legitimately fixed hardware, must not slide).
- string load → `lea (%rip)`, `&fn` → `lea (%rip)`, every global → `lea (%rip)`,
  switch table is rip-relative base + 32-bit relative offsets (PIC by
  construction). No `.rela`, no `PT_DYNAMIC`.
- ELF wrapper: ET_DYN, first PT_LOAD `p_vaddr=0`, base-relative `e_entry=0xA8`.

This is now guarded by `_kernel_pie_struct_gate` (check.sh, v6.2.45).

## The gap

The emitted **boot metadata still pins the image to its link base**, so with
every loader that exists today it boots un-slid:

- `src/backend/x86/fixup.cyr:969` — PIE sets `p_paddr = base = 0`. Stock
  multiboot2/GRUB loads each PT_LOAD at `p_paddr` → physical 0 (the link base).
- `src/backend/x86/fixup.cyr:983` — the multiboot2 `ENTRY_ADDRESS_EFI64` tag
  bakes an **absolute** `entry = 0xA8`; on EFI handoff GRUB jumps to absolute
  `0xA8`, not a slid entry. (Verified: tag at file offset 0x88, entry bytes
  `a8 00 00 00` at 0x90.)
- No `MULTIBOOT_HEADER_TAG_ADDRESS` (type 2) is emitted to redirect the load;
  no relocation/dynamic info exists, so the image cannot self-relocate.

Net: the PIC `.text` is necessary but not sufficient. The slide can only happen
via a loader that ignores `p_paddr`/the entry tag and biases by a random base.

## Two ways to close it (decide WITH the gnoboot boot test)

1. **gnoboot biases manually.** The `gnoboot --pie` loader reads the ET_DYN,
   picks a random base, loads PT_LOAD there, and jumps to `base + e_entry`,
   ignoring `p_paddr`/the EFI64 entry tag. cyrius emits nothing new. Simplest;
   keeps the slide policy in the bootloader where KASLR entropy lives.
2. **cyrius emits slide-aware metadata.** Add a multiboot2 relocatable
   `ADDRESS`/`reloc` tag (or equivalent) so a stock multiboot2 loader performs
   the relocation. Larger cyrius-side change; only worth it if a non-gnoboot
   loader must slide cyrius kernels.

**Do not pick blind.** The live `gnoboot --pie` boot test (in flight 2026-06-27)
determines which is needed. Whatever lands must be validated by an actual slid
boot (two-boot base-diff), not structurally — per "running it on the hardware
IS the test."

## Verify

A real slid boot: build `kernel; --pie`, have gnoboot load it at two different
random bases, confirm both boot and the in-memory base differs (the existing
agnos two-boot QEMU+OVMF base-diff harness, wired to `--pie`).

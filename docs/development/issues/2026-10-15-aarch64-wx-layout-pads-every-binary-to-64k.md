# aarch64 W^X ELF layout pads every executable with up to 64 KiB of zeros — open

**Status:** 🟡 **OPEN**. This is a size cost of a deliberate layout, so it needs a decision (keep it and document it, or narrow it), not a bug fix.
**Placement:** unpinned — 6.x-line backlog.
**Discovered:** 2026-10-15, during bannermanor 1.8.1. bannermanor was accounting for a +65,984-byte aarch64 size jump at its 1.5.0 that the x86_64 and AGNOS builds did not show (+4.5 KB each).
**Severity:** Low. It is a doc mismatch and a papercut: nothing fails, and nothing costs time at run time. The cost is file and download size only, and the padding is never mapped.
**Affects:** aarch64 Linux ELF executables built with segment-level W^X on (`_wx_active`, the default; `EMITELF_USER`). Measured on the cyrius 6.7.11 release. The code is the same at HEAD `7f57e532`. Its comment dates the layout to v6.3.12.

## Summary

With W^X on, the aarch64 ELF writer rounds the data segment's **file offset** up to 64 KiB (`src/backend/aarch64/fixup.cyr:733`), and writes the bytes between the end of the code and that boundary as zeros. So every aarch64 executable carries 0–64 KiB of zero padding, and no aarch64 program is smaller than about 64 KiB. A one-line program builds to:
- **65,888 bytes** on aarch64;
- 4,448 bytes on x86_64, where the file offset is aligned to 4 KiB;
- 520 bytes on aarch64 with `CYRIUS_WX=0`.

The layout is very likely deliberate (see "Why it is there" below). What is missing is that nothing says what it costs. The aarch64 comment at `:719-722` explains the alignment but not the file bytes. The x86 peer's comment (`src/backend/x86/fixup.cyr:78-84`) says its own split "costs near-zero file bytes", which is true at 4 KiB and not at 64 KiB. Meanwhile the size of an aarch64 binary moves in 64 KiB steps: a 6 KB code change can add 64 KB to the file.

## Reproduction

```sh
printf 'syscall(60, 7);\n' > tiny.cyr            # 60 = exit; the aarch64 backend translates the literal
cyrius build --aarch64 tiny.cyr tiny-aarch64
cyrius build tiny.cyr tiny-x86_64
CYRIUS_WX=0 cyrius build --aarch64 tiny.cyr tiny-aarch64-nowx
ls -l tiny-*; readelf -l -W tiny-aarch64 | grep LOAD
qemu-aarch64 ./tiny-aarch64; echo $?             # 7
```

Measured with the 6.7.11 release (a manifest pinning `cyrius = "6.7.11"`):

| build | bytes | program headers |
|---|---|---|
| aarch64, W^X (default) | **65,888** | `LOAD 0x000000 … filesz 0x0000e0 R E align 0x10000` / `LOAD 0x010000 0x600000 … filesz 0 memsz 0x1000 RW align 0x10000` |
| x86_64, W^X (default) | 4,448 | `LOAD 0x000000 … 0x0000d0 R E align 0x1000` / `LOAD 0x001000 0x600000 … RW align 0x1000` |
| aarch64, `CYRIUS_WX=0` | 520 | `LOAD 0x000000 … filesz 0x0000a8 memsz 0x10a8 RWE align 0x10000` |

In the W^X aarch64 file, bytes 0xe0–0xffff (65,312 bytes) are all zero.

**On a real program** (bannermanor 1.8.0, `build/bnrmr-aarch64`): the code `LOAD` ends at 0x54578 and the data `LOAD` starts at file offset 0x60000. That is 47,752 bytes of zeros in a 407,696-byte file: 12%. With `CYRIUS_WX=0` the same program is 359,888 bytes. bannermanor's 1.5.0 shows the step itself:
- the code segment grew 6,440 bytes (0x4eb00 → 0x50428), past 0x50000;
- the data segment moved from file offset 0x50000 to 0x60000;
- the file grew 65,984 bytes.

## Root cause

`src/backend/aarch64/fixup.cyr`, `EMITELF_USER`'s W^X layout block:

```cyrius
    # v6.3.12 (W^X): layout — mirror of x86 EMITELF_USER. aarch64 p_align is 64 KB
    # (0x10000), so the data file offset aligns to 64 KB; the 2 MB data vaddr is a
    # multiple of 64 KB, so p_vaddr ≡ p_offset (mod p_align). ...
        data_foff = (text_foff + cp + 0xFFFF) & (0 - 0x10000);   # :733 — 64 KB-align file offset
        dbase = _wx_data_vaddr(S, base + text_foff, cp);          # 2 MB-align vaddr (:65)
```

## Why it is there (verify — this is the reporter's reading)

Arm64 Linux kernels run with 4, 16 or 64 KiB pages. The loader maps whole pages, so if the end of the code and the start of the data shared a page-sized block of the file, that page would be mapped executable with data in it, and writable with code in it. Only a 64 KiB gap keeps the two segments apart on every one of those page sizes. That is what segment-level W^X is for, so the padding looks like its intended price, not an oversight.

The usual non-separate-code linker layout avoids padding: an unpadded file offset, and a virtual address congruent to it. That is not an option here, because it puts the first data bytes into the last executable page on every kernel. (GNU ld's `-z separate-code` pads for the same reason.)

## Proposed fix

A decision, in order of cost:

- **(a) Keep it; document the cost.** Add to the `:719` comment, and wherever cyrius reports or compares binary sizes, that an aarch64 W^X executable carries up to 64 KiB of padding and is at least ~64 KiB. Size deltas between aarch64 builds then read as 64 KiB-quantized. This keeps exact W^X on every page size.
- **(b) Pad to 16 KiB, not 64 KiB.** Set the data vaddr congruent to the file offset modulo 64 KiB: the 2 MiB base plus `data_foff & 0xFFFF`. The file then still loads on a 64 KiB-page kernel.
  - **Gain.** The maximum padding drops to 16 KiB. W^X stays exact on 4 KiB- and 16 KiB-page kernels, which covers most arm64 Linux, including the 16 KiB kernels common on Apple silicon.
  - **Loss.** On a 64 KiB-page kernel, the one 64 KiB block at the boundary is mapped by both segments, so the separation is lost for that block. Whether that trade is acceptable is the maintainer's call.
  - **Must stay in step.** `FIXUP` bakes addresses against `_wx_data_vaddr` / `_wx_dbase_frozen`, and `EMITELF_USER` must emit the same `dbase`. That is v6.6.3's lesson, and a change here touches both.
- **(c)** An opt-in for a known deployment page size. It is more surface for a size-only gain; listed for completeness, not recommended.

## Consumer-side workaround

None needed: nothing is broken. `CYRIUS_WX=0` removes the padding, but also W^X, so it is not a workaround anyone should ship. To read aarch64 code growth, use the code segment's `filesz` (`readelf -l -W <bin> | grep LOAD`), not the file size. bannermanor records this in its `docs/architecture/003-aarch64-size-moves-in-64k-steps.md`.

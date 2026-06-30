# ELF W^X — `cyrld` emit separate code / rodata / data PT_LOAD segments

**Filed:** 2026-06-29 (by an agnos-kernel consumer — the 1.50.6 ELF-loader W^X
work). The kernel side is already done; this is the one upstream piece that
unlocks true segment-level W^X for every cyrius binary.

**Severity:** Security / hardening gap — `cyrld` emits **one `RWE` PT_LOAD per
binary** (`.text` + `.rodata` + `.data` + `.bss` packed into a single
read-write-execute segment). So every cyrius program runs with its **code
writable AND its data executable** — the textbook W^X violation. A memory-write
bug can overwrite live code; a data/heap-spray can be jumped into.

**Affects:** every cyrius-compiled ELF that runs on agnos under a hardened
loader — `agnsh`, `kriya`, `owl`, `bnrmr`, `iam`, the net tools, cyrius-doom,
and every future userland binary. (Host-Linux execution is unaffected — Linux
maps the RWE segment as the linker requests; this only bites a W^X-enforcing
kernel.)

**Target slot:** a `cyrld` (linker) change — maintainer direction. **Not a
release blocker:** agnos already NX's the anonymous mmap arena (1.50.5) and the
user stack (1.50.6), and its loader is PF_X-aware *today* (it maps `PF_X`
segments executable / non-`PF_X` segments NX). The moment `cyrld` emits separate
segments, that existing loader logic delivers full W^X with **zero further kernel
work**. This closes the last writable-executable surface in the agnos userland.

**Template:** standard ELF segment layout — `ld`/`lld` emit (at minimum) a
`R E` text segment and a `RW ` data segment, page-aligned, with `.rodata` either
in the text segment (R E) or its own `R  ` segment. cyrius already emits valid
multi-PT_LOAD ELF for the kernel path (`EMITELF64_KERNEL`); this applies the same
machinery to userland output.

## Trigger

agnos 1.50.6 made the kernel ELF loaders (`elf_load_from_file`, `elf_load`)
read each `PT_LOAD`'s `p_flags` and map the segment **executable only if `PF_X`
is set**, else **NX** — and NX'd the user stack. Verifying it, `readelf -lW` on
the cyrius-built userland binaries shows the wall:

```
$ readelf -lW build/agnsh_agnos
  Type   Offset   VirtAddr           FileSiz  MemSiz   Flg Align
  LOAD   0x000000 0x0000000000400000 0x03c710 0x03d710 RWE 0x1000
```

One `PT_LOAD`, flags **`RWE`** — identical shape on `kriya_agnos` and
`owl_agnos`. Because that single segment legitimately contains code, it has
`PF_X`, so the kernel must map it executable; and because it also contains data,
it has `PF_W`, so it stays writable. **Result: the whole binary image is RWX.**
The kernel cannot split code from data within one segment — it has no section
information at load time, only program headers. So segment-level W^X is
impossible to achieve from the kernel alone; it requires the linker to *emit* the
permission boundary as separate segments.

## What

Have `cyrld` lay out userland ELF output as **permission-separated, page-aligned
`PT_LOAD` segments**, e.g.:

| Segment | Sections | Flags | Notes |
|---|---|---|---|
| text   | `.text` (+ `.rodata`, optional) | `R E` (5) | executable, **not** writable |
| rodata | `.rodata` (if split out)        | `R  ` (4) | read-only constants (optional) |
| data   | `.data`, `.bss`                 | `RW ` (6) | writable, **not** executable |

Page-align each segment's vaddr to the load granularity (the agnos loader uses
2 MB huge pages, so 2 MB alignment is ideal — but any alignment that doesn't pack
a writable section into the same *kernel page* as code suffices; see "agnos page
granularity" below). The entry point stays in the text segment.

## Why it matters (and why it's the *last* W^X piece on agnos)

agnos has been closing W^X surfaces patch by patch:

- **1.50.5** — anonymous `mmap` arena pages are NX (heap can't be executed).
- **1.50.6** — the user stack is NX (no stack shellcode), and the loader is
  already PF_X-aware.

The **only remaining RWX surface** is this single cyrius code+data segment. With
separate segments, agnos maps text `R+X` (code can't be overwritten) and data
`R+W+NX` (data can't be executed) — **full W^X**, with no additional kernel
change. Without it, a single linker decision keeps every cyrius program's entire
image writable-and-executable, which undercuts the rest of the hardening.

## Implementation notes / caveats

- **agnos page granularity.** The agnos loader maps 2 MB huge pages, so a text
  and data segment that share a 2 MB page can't get distinct permissions. If
  `cyrld` aligns the data segment to a fresh 2 MB boundary (or agnos later adds
  4 KB-page support for segment tails), the split is clean. Worst case, agnos
  maps any 2 MB page that overlaps a `PF_X` segment executable — so a 2 MB-padded
  data segment is the robust target. (4 KB alignment + 4 KB loader pages would be
  the tighter long-term form.)
- **Binary size.** Page-aligning a second segment adds up to one alignment gap of
  padding per binary (≤ 2 MB virtual, near-zero file bytes with `p_offset`
  sharing). Acceptable for the security win; the linker can keep `.rodata` in the
  text segment to avoid a third segment.
- **`.bss`.** Already handled by `p_memsz > p_filesz` (the loader zero-fills the
  tail) — it just needs to live in the `RW ` data segment, not the `RWE` one.
- **Self-modifying code.** None known in the cyrius userland (no JIT, no
  trampolines); `R+X` text is safe. If a future consumer needs W+X it can request
  an explicit RWE segment (opt-in), keeping the default hardened.

## Consumer-side readiness (already done)

No kernel work remains. agnos `kernel/core/elf.cyr` (1.50.6) already:
- reads `p_flags = load32(ph + 4)` per `PT_LOAD`;
- maps `PF_X` segments via `proc_map_page` (executable), non-`PF_X` via
  `proc_map_page_nx` (NX);
- maps the user stack NX.

So a `cyrld` that emits the segments above yields W^X immediately — verifiable by
re-running `exec-smoke` / `ring3-smoke` against re-linked binaries and confirming
a write to `.text` faults and a jump into `.data` faults.

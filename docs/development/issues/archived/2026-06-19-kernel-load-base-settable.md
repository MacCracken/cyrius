# Settable kernel load base (env/flag) — deferred from v6.2.28 D6

> **RESOLVED in v6.3.3** — folded into bare-metal deliverable **#5** (`[sections]`),
> which IS this feature viewed at the manifest level. Implemented exactly the
> recommended path below: (1) de-dup'd the base into ONE `_kernel_load_base(S)`
> accessor (x86 + aarch64 `fixup.cyr`), used by `_entry_base` + all three kernel
> emitters — byte-identical (ELF32 + ELF64 kernels `cmp`-identical pre/post, self-host
> + seed-derive hold); (2) added the knob — `CYRIUS_KERNEL_BASE=0x<hex>` env
> (`_parse_hex_env` in `runtime.cyr`, read in `main.cyr` + `main_aarch64.cyr` into cell
> `0x18FCE8`) AND the `[sections] base = "0x.."` manifest surface (cbt appends the env);
> (3) verified — a `0x200000` build shifts e_entry + p_vaddr in lockstep
> (`_sections_base_override_gate`, check.sh 101→102) AND **BOOTS under QEMU emitting
> "AGNOS"** (fixups followed the base). The D6 build-report is now base-aware (prints the
> real entry/base, no drift). See CHANGELOG [6.3.3]. Original deferral notes preserved
> below.
>
> **OPEN (historical) — deferred follow-on to v6.2.28 D6.** v6.2.28 *exposed* the kernel
> entry/load-base VA via the triple (the build prints `kernel: entry 0x1000a8,
> load base 0x100000`, and the qemu-boot-gate asserts it). It did NOT make the
> load base *settable* — that is this item.

**Filed:** 2026-06-19 · **Parent:** v6.2.28 D6. **Severity:** P3 (no consumer
needs it yet — 1 MiB / 0x40000000 are the canonical multiboot / AArch64 kernel
bases; agnos hardcodes `exp_entry = 0x1000a8`).

## Why deferred

Making the base settable is all-or-nothing across **five** sites that must agree
or every absolute fixup garbles (`dbase = entry + acp`):
- `_entry_base()` — `src/backend/x86/fixup.cyr` (the `0x100000 + 120 + 48` /
  `+ 84 + 12` ladder) and `src/backend/aarch64/fixup.cyr` (`0x40000000 + 120`).
- the `var base` literal repeated inside each ELF emitter:
  `EMITELF_KERNEL` (x86 ELF32, base repeated ~6× across text/bss/rod/p_vaddr/
  p_paddr), `EMITELF64_KERNEL` (x86 ELF64), `EMITELF_KERNEL` (aarch64 ELF64).

A partial edit (update `_entry_base` but miss an emitter's `p_vaddr`) produces an
ELF whose fixups point at a different base than its PT_LOAD declares — boots to
garbage. No automated test catches that except a real boot (now we have one: the
qemu-boot-gate).

## Recommended implementation (when a consumer needs it)

1. **First, de-duplicate** the base into ONE source of truth — a
   `_kernel_load_base(S)` accessor (arch-dispatched) used by both `_entry_base()`
   and all three emitters. This removes the 6×-per-emitter duplication that makes
   the change dangerous, and is verifiable byte-identical (self-host + boot gate).
2. **Then** add the env knob: `CYRIUS_KERNEL_BASE=0x<hex>` read once in the
   `main_*.cyr` (after the `CYRIUS_KERNEL` read, into a state cell adjacent to
   `kernel_mode` at `S+0x18FCA0`; default 0 = built-in), consumed by the single
   accessor. A hex env parser (~10 lines) is net-new — no `0x`-hex env parser
   exists today (`CYRIUS_DCE_CAP` is decimal).
3. **Verify** with the qemu-boot-gate at a non-default base (build with
   `CYRIUS_KERNEL_BASE=0x200000`, confirm e_entry shifted AND it still boots →
   the fixups followed the base).

Until a real consumer needs a non-canonical base, the v6.2.28 expose-only D6 (the
build reports the VA, the boot gate asserts it) is the right scope.

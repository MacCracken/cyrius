# `load64`/`store64` don't reach a ≥4 GB virtual address — silent wrong access

> **Filed 2026-06-28 by agnos (kernel, RAM-arc bite 3b).** Surfaced building the
> kernel's >256 MB RAM extension: a `store64`/`load64` to a correctly-mapped VA
> *at or above 4 GB* doesn't touch the mapped physical page — the access appears
> to use only the low bits of the address. It's silent (no fault, wrong/zero
> data), which is why it hid: agnos's first direct-map probe only tested a VA
> whose low bits already aliased a live low mapping, so it "passed". Consumer
> stopgap: agnos holds kernel-reachable RAM at the 256 MB identity ceiling
> (`pmm_2mb_top_region` cap) until this lands — see CHANGELOG `[1.49.9]`.

**Filed:** 2026-06-28 · **Status:** open / unscheduled · **Severity:** P1 (silent correctness — a ≥4 GB-VA load/store reads/writes the wrong physical address with no fault) · **Consumer:** agnos kernel

## What

`load64`/`store64` (and almost certainly all `loadN`/`storeN`) appear to compute
or use only the **low bits** of the effective address, so any virtual address
**≥ 4 GB** is silently mis-addressed. The address *value* is correct in cyrius
arithmetic — `kprint_hex` shows the full 64-bit value — so it's the emitted
load/store instruction's effective address, not the value computation.

## Why it matters

- **Silent** — no page fault, just a wrong (or zero) result. The worst failure
  mode: a high-VA store lands on a *different* physical page than intended.
- **Blocks the agnos >256 MB RAM extension.** The kernel reaches PMM pages above
  the 256 MB identity window only through a direct-map placed at an 8 GB VA
  (`DIRECTMAP_BASE = 0x200000000`, mapped in the kernel PDPT). That map is
  unusable from cyrius, so kernel-reachable RAM is capped at 256 MB on a box with
  60 GB installed.
- Retroactively, it means agnos's direct-map (kernel 1.49.7) was never truly
  validated — the probe aliased the identity map and passed regardless.

## Repro (observed in agnos, `-m 1024M` so phys 320 MB is real RAM)

```
# kernel reads the live page-table chain for VA 0x214000000 (= 8 GB + 320 MB):
PDPT[8] = 0xffff003           # -> PD page, present
PD[160] = 0x14000083          # -> phys 0x14000000 (320 MB), present + writable + 2 MB
# the mapping is exactly right. now access it:
store64(0x214000000, 0xA5A5A5A5);
load64(0x214000000)  ==>  0   # WRONG: expected 0xA5A5A5A5, got 0, no fault
```

A VA whose **low 32 bits alias a live low mapping "works"**: `0x206400000`
(8 GB + 100 MB) reads the same bytes as identity `0x6400000` (100 MB), because
the low bits coincide. That aliasing is exactly what masked the bug.

## Minimal standalone repro (suggested, no agnos)

In a freestanding/bare-metal target: build a fresh PML4/PDPT/PD that maps one
physical page at a virtual address ≥ 4 GB, load CR3, then:

```cyrius
store64(0x200000000, 0xDEADBEEF);   # some VA >= 4 GB that you mapped
var x = load64(0x200000000);        # expect 0xDEADBEEF; currently won't round-trip
```

`store64(va, x); load64(va) == x` should hold for any correctly-mapped
`va >= 4 GB`. A `repros/` program demonstrating the truncated effective address
(e.g. comparing the access against a known low alias) would pin it precisely.

## Fix

`loadN`/`storeN` should emit a **full 64-bit effective address**. Once a ≥4 GB VA
round-trips, agnos lifts its `pmm_2mb_top_region` cap + re-grows the PMM bitmap
and >256 MB RAM comes online with no further VM work.

## Cross-reference

Mirror of `agnos/docs/development/issue/2026-06-28-cyrius-high-va-load-store.md`
(the consumer-side copy, with the agnos impact + the held-state details).

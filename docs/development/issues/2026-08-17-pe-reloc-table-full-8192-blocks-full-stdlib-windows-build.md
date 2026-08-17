# `error: PE reloc table full (8192)` blocks a full-stdlib Windows build

> ### ✅ RESOLVED — FIXED in v6.5.26
>
> The relocation coff buffer is now **lazily allocated** (`_pe_reloc_base`, cap
> `_PE_RELOC_CAP` = 65536) instead of a fixed 64 KB window at `S + 0x1DC000`. All three large
> folds now build for Windows against the full 27-module preamble: mabda 2,792,448 B,
> yukti 2,186,240 B, sigil 2,181,120 B. Linux builds of the same sources unaffected.
>
> **Cap chosen by MEASUREMENT, not guess:** cap 8192 reports FULL, cap 16384 fits, so the
> real requirement for the largest fold is between 8k and 16k slots. 65536 is 4× the
> known-sufficient figure and 8× the old ceiling.
>
> ⚠ **An in-place raise was impossible, exactly as this file predicted.** The window was
> exactly 64 KB and `0x1DC000 + 0x10000` **is** `0x1EC000` (`gvar_initval`) — zero adjacent
> slack — so growing it would have MOVED a region: a heap LAYOUT change and a two-step
> bootstrap. The v6.4.75 `_fnvb_base` lazy-alloc precedent this file named is what avoided
> both; 0x1DC000 is now recorded FREED in the heap map and the heapmap gate still reports
> 100 regions / 0 overlaps.
>
> **On the "silent wrap" question this file asked to check:** the old bound was `>= 8192`
> tested AFTER the write, which was safe only by arithmetic coincidence (the insertion shift
> tops out at index count-1, so the last legal write is slot 8191 and the error fires before
> 8192 is touched). It is now compared against the cap and no longer depends on that.
>
> ⭐ **Added the capacity WARNING this class needed.** The reason this cost a release to find
> is that it was silent right up to fatal: no signal at 90 % full, then a hard error and no
> binary. It now warns at 75 %, mirroring the fn-table warning in `src/common/util.cyr`.
> ⚠ Deliberately WITHOUT `_emit_decimal` in the message: that fn lives in `src/main.cyr`
> only, while this file is also included by `main_win.cyr` and `main_x86_macho.cyr`, neither
> of which defines it — calling it would have broken those two forks and only a real
> cass / Intel-Mac build would have caught it (the v6.4.26 fork-stub trap). All three
> PE-capable forks verified building.
>
> Gate `tests/gates/platform/pe_reloc_cap_full_stdlib.sh` — which is also **the `cycc_win`
> axis `folds_agnos_parity.sh` never had**, the gap this file identified as the reason a
> PE-only ceiling could sit unnoticed. Mutation-proven: at cap 8192, mabda and yukti go red.
>
> ⚠ **The related reachable-undef ASYMMETRY is still open and is a maintainer decision** — an
> undefined `random_bytes` makes PE exit 1 while Linux exits 0. Not touched here.

**Status:** ✅ RESOLVED in v6.5.26 — archive at slot close.
**Discovered:** 2026-08-17, v6.5.25, while verifying the `SYS_IOCTL` PE fix against the
folded stdlib.
**Severity:** Medium-High — it is a hard ceiling, not a degrade: no binary is produced. It
bounds how much stdlib a single Windows program can link, and the folded stdlib is already
past that bound.

## What

Compiling the `folds_agnos_parity.sh` dependency-ordered preamble (26 stdlib modules) plus
`lib/random.cyr` plus any one fold for Windows fails:

```
error: PE reloc table full (8192)
```

`rc=1`, no output binary. The identical source compiles for Linux.

## Reproduction

```sh
# the gate's own PREAMBLE, + lib/random.cyr, + one fold, targeting PE
CYRIUS_TARGET_WIN=1 build/cycc < probe.cyr > out.exe
# -> error: PE reloc table full (8192)
```

Measured at cycc **1,177,808 B**. All 12 folds hit it once `random_bytes` is satisfied, so
it is a property of the preamble's size, not of any one fold.

## Why it was not seen earlier

Two things masked it, and both are worth recording because each looked like the answer:

1. **`SYS_IOCTL` failed first.** Until v6.5.25 a PE build of anything including
   `lib/yukti.cyr` died on `undefined variable 'SYS_IOCTL'` — a hard compile error that
   stopped the build before relocation ever ran. Fixing the earlier error is what exposed
   this one. A ceiling behind a hard error is invisible.
2. **A too-small probe reads as a different bug.** Including a fold WITHOUT its declared
   dependencies produces undefined ordinary-stdlib names (`alloc`, `memcpy`, `file_open`,
   `map_new`, `fncall1..6`). Those look exactly like missing Windows-peer wrappers, and were
   initially recorded as such (`PROT_READ`/`MAP_SHARED` "absent from the Windows peer"). They
   are not. Use the gate's dependency-ordered preamble, never a hand-rolled two-include probe.

## Related asymmetry, worth fixing alongside or separately

With the same preamble and **no** `lib/random.cyr`, an undefined `random_bytes` reference
makes **PE exit 1** while **Linux exits 0** (the reference is pruned as unreachable there).
So the reachable-undef analysis disagrees per target. That is a second, smaller finding: it
means a program can build on Linux and hard-fail on Windows for a symbol neither target
actually calls. Decide deliberately which behaviour is correct rather than letting the two
drift — the Linux one is more permissive, the PE one is arguably more honest.

## Fix (when picked up)

Raise the PE relocation table cap, following the `fn_table` 8192 precedent from v6.4.75:

- Find the 8192 bound in the PE emitter (`src/backend/pe/emit.cyr`) and every table sized or
  indexed by it — v6.4.75's lesson is that such a constant is rarely alone (32768 there was
  coupled across four regions plus a second bounds check).
- Prefer lazy-allocate-at-a-larger-cap over a static raise if the region is in the heap map,
  to avoid a layout change and its two-step bootstrap.
- ⚠ Check whether the cap goes **silently** wrong past the limit anywhere, as the fn_table
  one did (index 8192 aliasing index 0 of the neighbour). A hard error is the good case; a
  wrap is a silent miscompile.
- Gate it: extend `tests/gates/platform/folds_agnos_parity.sh` with a `cycc_win` axis, which
  it currently lacks entirely (it has an agnos axis only). That gate is the natural home and
  its absence is why a PE-only ceiling could sit here unnoticed.

## Acceptance

`CYRIUS_TARGET_WIN=1` compiles the full 26-module preamble + `lib/random.cyr` + each of the
12 folds to a PE binary, `rc=0`, and a `folds_agnos_parity.sh` PE axis asserts it so the
ceiling cannot return silently.

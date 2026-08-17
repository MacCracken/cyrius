# `error: PE reloc table full (8192)` blocks a full-stdlib Windows build

**Status:** 🔴 OPEN — filed, not fixed. **Named reason:** it is a backend capacity/layout
change in the PE emitter needing its own full gate cycle (self-host + seed-derive + four-host
cross-OS), and v6.5.25 already carries one compiler change to the PE syscall path. Packing a
second, independent PE change into the same release would leave two candidate causes for any
Windows breakage — the exact reason the maintainer scoped `.22` to a single heap change.
**Placement:** next available `.NN` in the 6.x line. ⛔ **NOT 7.x** — this is codegen.
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

# `cyrius fuzz --poison` has no guard pages: a read that jumps a whole redzone is invisible — OPEN

**Status:** 🟡 **OPEN** — re-verified 2026-10-08 against 6.7.6 @ 2fb6ad8b: under `#define CYRIUS_POISON` two
`alloc(16)` blocks sit 104 B apart and `load8(a + 104)` returns the neighbour's live byte with no trap and exit 0
(`repros/2026-10-08-poison-redzone-jumping-read.cyr`); `grep -n mprotect lib/poison.cyr lib/alloc.cyr
lib/freelist.cyr` finds nothing, and the `--poison` banner (`cbt/cyrius.cyr:1188`) still says "no guard pages".
**Placement:** unpinned — 6.x-line backlog (proposal P6's step S7, left out of 6.6.18) — never 7.x.
**Discovered:** 6.6.18 (the P6 poison arc; CHANGELOG [6.6.18] *Known / not fixed*, and the archived
`proposals/archived/2026-09-20-fuzz-poison-should-follow-a-custom-allocator-seam.md` "Backlog: guard pages");
filed 2026-10-08 from roadmap.md.
**Severity:** Low — a coverage gap in fuzz tooling, stated in the tool's own banner; no wrong answer is reported.
**Affects:** cycc 6.6.18 – 6.7.6 (guard pages were never built).

## Summary

Poison mode catches writes into a redzone (trap, exit 86) and, under `--poison=ab`, overreads that land IN a
redzone or freed fill (the two fills differ). A read that strides past a whole 32-byte redzone into the next
block's user bytes reads live data that is identical under both fills, so neither mechanism can see it. Placing
an inaccessible page after (or before) a block is the one way to fault on such a read.

## Reproduction

`docs/development/issues/repros/2026-10-08-poison-redzone-jumping-read.cyr`:

```sh
cat docs/development/issues/repros/2026-10-08-poison-redzone-jumping-read.cyr | build/cycc > /tmp/pz \
  && chmod +x /tmp/pz && /tmp/pz; echo $?
```

Expected (with guard pages, in some opt-in mode): a SIGSEGV / poison report on the overread.
Actual (6.7.6): `a->b distance: 104  byte read through a: 66`, exit 0. 104 = 16 user bytes + 32 trailing redzone
+ 24-byte header + 32 leading redzone (`lib/poison.cyr:31` `_POISON_RZ = 32`, `:51` `_POISON_HDR = 24`).

## Root cause

Not a defect in what exists — the mechanism is absent. `lib/poison.cyr`'s block layout (comment at `:40-49`) is
header + redzones packed back to back in the bump heap; nothing maps a `PROT_NONE` page anywhere.

## Proposed fix

An opt-in guard mode under `--poison` (it costs a page or two per block, so not the default): place each block so
its trailing (or leading) edge abuts a `PROT_NONE` page. Per-target constraints the roadmap names:

1. Linux: `mprotect` (`lib/mmap.cyr:43` `cyr_mprotect`), 4 KiB pages.
2. Apple arm64: 16 KiB pages — the page size must be queried or fixed per target, not assumed 4096.
3. Windows: `VirtualProtect` reaches no stdlib path today (`grep -rn VirtualProtect lib/ src/` is empty) — a new
   PE route is needed, or Windows reports "unguarded".
4. agnos: `cyr_mprotect` is a no-op that returns 0 (`lib/mmap.cyr:44-45`), so an agnos run must REPORT
   "unguarded" rather than claim coverage it does not have.

Then update the `--poison` banner (`cbt/cyrius.cyr:1188`) to name the guard mode and its per-target coverage.

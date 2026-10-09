# `esysxlat_fold.sh` passes a fold that never updates `cur` (mutation (c) is not caught) — OPEN

**Status:** 🟡 **OPEN** — re-verified 2026-10-08 against 6.7.6 @ 2fb6ad8b: in a `git archive` copy of HEAD with
`_esx_fold`'s cur update deleted (`src/backend/aarch64/emit.cyr:1950`), `sh tests/gates/platform/esysxlat_fold.sh`
prints **PASS** on all six axes (qemu-aarch64 present, axis 2 ran).
**Placement:** 6.7.11 — Break 2, repair 2: the platform release (roadmap.md § *The releases after 6.7.7*) — placed 2026-10-09 — never 7.x.
**Discovered:** 6.6.18 (2026-10-06) — written into the gate's own mutation ledger as "(c) … NOT CAUGHT"; filed
2026-10-08 from roadmap.md.
**Severity:** Low — a test-coverage gap; no wrong output today.
**Affects:** the gate at 6.6.18 – 6.7.6.

## Summary

`_esx_fold` simulates ESYSXLAT in emission order: for each row whose `cmp x8,#src` equals `cur` it keeps the body
and, when the body's last word is `movz x8,#d`, sets `cur = d` so a LATER row can match the renumbered value. No live
input exercises that update: `esysxlat_row_order.sh` keeps the ELF chain free of live re-captures (no row's output is
a later row's source), and Mach-O bodies end in `movz x16`, never `movz x8`. So the gate's axes 1–6 cannot tell a
correct fold from one that never updates `cur`; the ledger says so (`esysxlat_fold.sh:40-42`). The day a legitimate
chained row lands (or the row-order rule is relaxed), a broken update ships green.

## Reproduction

```sh
T=$(mktemp -d); cd /home/macro/Repos/cyrius && git archive HEAD | tar -x -C "$T" && cp build/cycc "$T/build/cycc"
cd "$T" && grep -n 'cur = (lw >> 5) & 0xFFFF;' src/backend/aarch64/emit.cyr      # 1950
sed -i '1950s/.*/            # MUTANT (c): cur never updated/' src/backend/aarch64/emit.cyr
sh tests/gates/platform/esysxlat_fold.sh      # → "PASS esysxlat_fold …" (all six axes)
```

Expected: the gate fails. Actual: PASS.

## Root cause

Coverage, not code: `_esx_fold`'s update (`src/backend/aarch64/emit.cyr:1949-1950`) is reachable only through a
chained row, and the chain the gate compiles has none by construction.

## Proposed fix

Give the gate a live re-capture of its own, outside the shipped chain: in a temp copy of `src/`, append two
synthetic ELF rows (the `cmp x8,#src` / `b.ne` / `movz x8,#dst` shape) at the chain's end — `4000 → 4001` then
`4001 → 4002` (`cmp` takes a 12-bit immediate) —
cross-build, and require (a) `syscall(4000)` folds to `movz x8,#4002`, and (b) under `qemu-aarch64 -strace` it makes
the same call as its `var`-number twin through the runtime stub. Then mutation (c) fails the gate; move the ledger
line from NOT CAUGHT to the new axis. Gate-only change — no compiler output moves.

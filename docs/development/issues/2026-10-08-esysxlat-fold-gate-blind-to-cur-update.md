# `esysxlat_fold.sh` passes a fold that never updates `cur` (mutation (c) is not caught) — RESOLVED

> ✅ **RESOLVED in v6.7.9** (the quick lane's bite 18; CHANGELOG [6.7.9]) The gate has a new axis 7, a chained row of
> its own built outside the shipped chain. It copies `src/backend/aarch64/emit.cyr` with two synthetic ELF rows added
> before ESYSXLAT's `return 0;`, 4000 → 4001 and then 4001 → 4002, splices that copy into a copy of
> `src/main_aarch64.cyr` in place of its include, and cross-builds it from the live tree. Three checks follow. The
> fold check: a one-literal `syscall(4000)` leaves no `cmp x8` and has `movz x8,#4002` directly before its `svc`. The
> stub check: the twin probe's shared stub carries NROWS + 2 rows. The qemu check: under `qemu-aarch64 -strace` the
> literal makes the same call as its `var` twin, and that call names 4002. The three numbers are first checked
> against every shipped ELF row source. Mutation-proven in a copy of the tree: the filed mutant (c) fails the fold
> check (the literal folds to `movz x8,#4001`), and with the fold check removed it fails the qemu check ("Unknown
> syscall 4001" against the twin's 4002). A fold that stops at the first matching row also fails the fold check. The
> pre-fix gate PASSes both mutants. The mutation ledger's (c) line now names axis 7. The change is to the gate only;
> no compiler output moves.

**Status:** ✅ **RESOLVED** in v6.7.9 (the quick lane's bite 18; see the banner). Was: 🟡 OPEN — re-verified
2026-10-08 against 6.7.6 @ 2fb6ad8b: in a `git archive` copy of HEAD with `_esx_fold`'s cur update deleted
(`src/backend/aarch64/emit.cyr:1950`), `sh tests/gates/platform/esysxlat_fold.sh` prints **PASS** on all six axes
(qemu-aarch64 present, axis 2 ran). Reproduced again 2026-10-11 on the 6.7.9 quick lane (l679-quick @ 5457db8b; the
update is now at `:1956`): PASS on all six axes.
**Placement:** 6.7.9 — the repair batch, the quick-fix lane (user, 2026-10-11) — never 7.x.
**Discovered:** 6.6.18 (2026-10-06) — written into the gate's own mutation ledger as "(c) … NOT CAUGHT"; filed
2026-10-08 from roadmap.md.
**Severity:** Low — a test-coverage gap; no wrong output today.
**Affects:** the gate at 6.6.18 – 6.7.8.

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

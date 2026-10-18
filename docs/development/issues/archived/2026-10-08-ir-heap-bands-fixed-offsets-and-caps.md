# The IR heap family is six fixed `S + 0x…` bands with fixed caps — one `alloc()` arena (HEAP-12) — RESOLVED

> ✅ **RESOLVED in v6.7.14** (IN-1, `937384a0f` (no decision needed: a tooling defect): the IR tables are one `alloc()`'d arena that `IR_SENABLE` takes when `CYRIUS_IR` switches recording on (a default build never takes it) — nodes + CPs and BBs + live-in + live-out grow 2x from 262,144 nodes / 32,768 BBs, with named runaway ceilings at 64M nodes / 16M BBs — and the six fixed bands (ir_nodes, ir_cp, ir_blocks, ir_live_in, ir_live_out, ir_state: 26 MB + 4 KB) left `src/main.cyr`'s heap map; brk-final unchanged. It is the release's heap-layout change: two-step bootstrap gen1 == gen2 == gen3, seed-derive OK, `heapmap.sh` 115 regions (was 121). The filed 3.0 MB repro builds and exits 203 by default, under `CYRIUS_IR=1` (1,405,628 nodes) and under `CYRIUS_IR=3`, on x86_64, on PE under wine and on real Windows (cass); a 150,751-BB program that stopped with `IR block table full` builds too. The default pipeline is byte-identical on a 717-input differential (x86 default / IR=1 / IR=3, aarch64, PE default / IR=1 / IR=3, cx), and cycc's IR self-compile counts are unchanged (654,161 nodes / 68,054 BBs / 3,249 LASE; IR=3 output 2,282,760 B). Rows: new `tests/gates/ir-opt/ir_arena_grows.sh` (axis 1 the filed generator verbatim under default / IR=1 / IR=3, with the IR=3 statistics an exact 8x of a never-grown build's; axis 2 the 150k-BB program, 6x; axis 3 cycc's IR=1 / IR=3 self-builds reproduce the default build; axis 4 no retired-band literal in src/, no IR heap-map row); mutations: the pre-fix compiler and tree RED 6, a grow skipping the CP copy RED axis 1, one skipping the BB copy RED axis 2. CHANGELOG [6.7.14])

**Status:** ✅ **RESOLVED in v6.7.14** (see the banner). Was: 🟡 **OPEN** — re-verified 2026-10-08 against 6.7.6 @ 2fb6ad8b: a generated 3.0 MB program
(`repros/2026-10-08-ir-heap-bands-fixed-offsets-and-caps.sh`, 400 fns × 500 statements) compiles and runs by
default (rc 0, exit 203) and stops under `CYRIUS_IR=1` with `error: IR node buffer full` (rc 1); 200 fns pass. The
bands and the literal cap are unchanged in `src/common/ir.cyr`.
**Placement:** 6.7.14 — repair 4: generics, the frontend, infra (infra lane, wave 1, unit I1; placed at the 6.7.14 open, 2026-10-16) — never 7.x.
**Discovered:** the 6.6.20 closeout planning (2026-10-07), deferred at planning as HEAP-12 (CHANGELOG [6.6.20]
*Known / not fixed*; `src/main.cyr:642-648`'s ir_nodes margin note points here); filed 2026-10-08 from roadmap.md.
**Severity:** Low — opt-in IR modes only; the default pipeline is unaffected (the bands are lazy VA it never
touches).
**Affects:** cycc ≤ 6.7.6 under `CYRIUS_IR` (all non-cx forks).

## Summary

The IR's storage is six fixed regions of the compiler arena, each with its own hard cap: `ir_nodes` S + 0x5E9D000
(16 MB, 1,048,576 nodes), `ir_cp` 0x6E9D000 (4 MB), `ir_blocks` 0xB3A000 (4 MB, 131,072 BBs), `ir_live_in` /
`ir_live_out` 0x207B000 / 0x217B000 (1 MB each), `ir_state` 0xF3A000 (4 KB) — scattered between unrelated tables
(the liveness pair was relocated into the gap after `fixup_tbl` at v6.5.23 because nothing else fit). The 6.6.20
audit measured cycc itself at 448,518 of the 1,048,576 nodes, but sixteen stdlib folds (8.3 MB preprocessed) at
1,017,828 (97 %) — so an IR build stops at about a third of the 24 MB preprocess cap, and every cap raise is another
relocation. The fixed offsets are spelled as literals at ~40 sites (`grep -rn "0x5E9D000\|0x6E9D000\|0xB3A000\|0x207B000\|0x217B000\|0xF3A0" src/ | grep -v ':\s*#'`:
6 / 3 / 15 / 2 / 2 / 12, in `src/common/ir.cyr` and `src/common/util.cyr`).

## Reproduction

```sh
cd /home/macro/Repos/cyrius
sh docs/development/issues/repros/2026-10-08-ir-heap-bands-fixed-offsets-and-caps.sh > /tmp/big.cyr   # 3,015,934 B
./build/cycc < /tmp/big.cyr > /tmp/big && chmod +x /tmp/big && /tmp/big; echo $?   # 203
CYRIUS_IR=1 ./build/cycc < /tmp/big.cyr > /dev/null; echo $?                       # 1
#   error: IR node buffer full
```

Expected: an IR build of a program the default build accepts succeeds (or the IR arena grows). Actual: a hard stop
at a fixed node cap.

## Root cause

`ir_emit` (`src/common/ir.cyr:315-319`) refuses past `ni >= 1048576`; `_ir_set_node` / `IR_NODE_*`
(`src/common/ir.cyr:212-241`) address `S + 0x5E9D000 + ni * 16` directly, and the other bands likewise.

## Proposed fix

Size the whole IR family from ONE `alloc()`'d arena carved into its sub-tables (base pointers in vars, as the
growable fixup / fn tables did in Phase 0 v6.2.0 — `src/common/heap_regions.cyr`), allocated only when
`CYRIUS_IR` is on, and grown (or sized from the preprocessed input length) instead of hard-stopping; retire the six
`src/main.cyr` heap-map rows and reclaim the bands. Must stay byte-identical for default builds (the default never
touches the bands); verify with the two-step bootstrap, seed-derive (cybs compiles `src/common/ir.cyr`), `heapmap.sh`,
and an IR=1 / IR=3 self-compile plus the repro under IR=1.

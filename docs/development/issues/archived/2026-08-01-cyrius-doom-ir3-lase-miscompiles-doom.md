# `CYRIUS_IR=3` miscompiles cyrius-doom — bisected to the LASE apply pass; wrong pixels, wrong thing classification, 3 failing tests

**Status:** ✅ **RESOLVED in cyrius 6.5.5** — but **not as diagnosed**. The bug is in **DCE**, not
LASE. `CYRIUS_LASE_OFF=1` is not LASE-specific: `ir_apply_lase` is the only NOP-filler and applies
`IR_ELIMINATED` marks from three passes (`ir_lase`, DCE, dead-store), so that knob disables all
three. `CYRIUS_DCE_CAP=0` fixes doom; `CYRIUS_DSE_CAP=0` does not.

Root cause: `ESWITCH_DISPATCH_PRE` (`src/backend/x86/emit.cyr`) recorded one `IR_RAW_EMIT` marker at
the top of the fn, then emitted four RECORDED nodes before its raw `sub rax, rcx` / `cmp rax, rcx`.
A marker only shields raw bytes until the next recorded node, so those reads of **rcx** were invisible
to DCE, which eliminated the `MOV_CA` feeding them — the switch then dispatched on a stale rcx.
`player_try_fire` is a `switch`, which is why it was the failing function. Fixed by re-arming the
marker before each raw emit; markers emit no bytes, so default codegen is byte-identical.

Verified on the filed repro: `CYRIUS_IR=3` now gives **380/380** and the E1M1 census matches default
(`6 monsters, 52 items, 33 decor`). Closes `switch_dispatch`, one of the eight residual IR=3
mismatches (18 → 0); **seven remain and are not this bug**. The **+8.6 % IR=3 size growth is
untouched** — elimination NOP-fills rather than removes, so it cannot shrink output.

Notes on the report, none of which weaken it: the root-cause section (explicitly flagged as
speculation) pointed at `ir_lase`'s `last_store` tracking in if/else-if ladders — LASE was never
involved, and `IR_SWITCH` is defined but never emitted anywhere in the tree. The repro commit also
moved (`7c56b24` → `b5178ae`; 366 tests → 380). The symptom table reproduced exactly.
Gated by `tests/ir3_switch_dce.sh`. See CHANGELOG [6.5.5].

**Original status:** 🟡 OPEN — verified against cycc **6.5.4** on x86-64 Linux. `CYRIUS_IR=3 CYRIUS_LASE_OFF=1`
restores correct behaviour; `CYRIUS_FOLD_OFF=1` does not.
**Placement:** unpinned — belongs to the `CYRIUS_IR=3` substrate arc. cyrius-doom is one of the **8 remaining
default-vs-IR=3 mismatches** the v6.5.2 entry recorded (35 → 8); this is that population, named.
**Reproducibility:** the table below re-verified immediately before filing, on the installed
`cycc 6.5.4` (sha256 `41eb0b19…`, identical to `~/Repos/cyrius/build/cycc`).
**Discovered:** 2026-08-01 while bumping cyrius-doom's toolchain pin 6.4.78 → 6.5.4 and testing whether
v6.5.2's "IR=3 substrate unblocked" opened doom's deep-perf hold (roadmap HOLD-C). It does not.
**Severity:** High — silently wrong output on a shipping consumer, no diagnostic. Not Critical because
`CYRIUS_IR=3` is opt-in and default codegen is unaffected.
**Affects:** cycc 6.5.4 under `CYRIUS_IR=3` only. Default builds are byte-identical to 6.4.78 output.

## Summary

Building cyrius-doom with `CYRIUS_IR=3` produces a binary that compiles and links clean and then behaves
differently: **all 9 shareware maps render differently**, the E1M1 thing census shifts by one item, and
**3 of 366 tests fail**, all in the weapon-fire path. Disabling only the LASE apply pass makes every one of
those go away. The binary is also **8.6 % larger**, not smaller.

## Reproduction

Consumer: cyrius-doom at commit `7c56b24`, WAD `DOOM1.WAD` (shareware).

```sh
cd ~/Repos/cyrius-doom

# 1. default build — reference
cyrius build src/main.cyr build/doom
cyrius build tests/doom.tcyr build/test_doom && ./build/test_doom wad/DOOM1.WAD   # 366 passed, 0 failed

# 2. IR=3 build
CYRIUS_IR=3 cyrius build tests/doom.tcyr /tmp/test_ir3 && /tmp/test_ir3 wad/DOOM1.WAD

# 3. isolate the pass
CYRIUS_IR=3 CYRIUS_LASE_OFF=1 cyrius build tests/doom.tcyr /tmp/test_nolase && /tmp/test_nolase wad/DOOM1.WAD
```

Results:

| build | test_doom | binary |
|---|---|---|
| default | **366 / 366** | 477,072 B |
| `CYRIUS_IR=3` | **363 / 366** | **518,032 B (+8.6 %)** |
| `CYRIUS_IR=3 CYRIUS_LASE_OFF=1` | **366 / 366** | — |
| `CYRIUS_IR=3 CYRIUS_FOLD_OFF=1` | 363 / 366 | — |

The three failures under IR=3:

```
FAIL: pistol fires with ammo (got 0, expected 1)
FAIL: pistol deducts 1 bullet (got 3, expected 2)
FAIL: fist always fires (no ammo) (got 0, expected 1)
```

All three are `player_try_fire` (`src/player.cyr`) returning 0 where it should return 1 — one function,
returning the wrong value, consistently.

Two further symptoms from the same binary, both independent of the test suite:

- **Renders differ on 9 of 9 maps.** `./build/doom wad/DOOM1.WAD E1M<N> --ppm` writes
  `/tmp/doom_e1m1.ppm`; every map's PPM differs from the default build's. All 5 menu screens are
  byte-identical, so it is not a global framebuffer/palette effect.
- **Thing classification moves.** E1M1 boot line reads `things: 91 total (6 monsters, 52 items, 33 decor)`
  on the default build and `(6 monsters, 51 items, 34 decor)` under IR=3 — a classification boundary in
  `thing_classify` (`src/things.cyr:219+`, a long `if` ladder over DoomEd type numbers) evaluating
  differently. Same total, so nothing is lost — one thing changes category.

## Root cause (not determined — this is a report, not a diagnosis)

Bisected to **LASE apply** (`ir_apply_lase`, called at `src/main.cyr:2072`) and no further. I did not
minimise it to a standalone function, and I have not identified which LASE elimination is unsound.

What the symptoms suggest, flagged as **speculation**: both `player_try_fire` and `thing_classify` are long
`if` / `else if` ladders returning small integers. `ir.cyr:526`'s LASE tracks "which local is live in rax"
across a BB and NOPs a redundant `LOAD_LOCAL`; `ir.cyr:135` already records one historical case where a
clobber was not visible to that tracking. A missing clobber in a branch-heavy ladder — where control can
enter a BB from several predecessors with different rax state — would produce exactly this shape: the right
function, the wrong small integer, no crash. `ir.cyr:568-571`'s `last_store` reset markers are the place I
would look first.

The `+8.6 %` size increase under IR=3 is worth noting on its own for a minor whose theme is generated-code
quality — the v6.5.2 entry recorded `+4.7 %` for the self-built compiler and correctly flagged it as a live
data point rather than a footnote; doom is nearly double that.

## Proposed fix

None — surfacing. doom is a useful corpus entry here precisely because it is large, branch-dense, and has a
**deterministic behavioural oracle** beyond exit codes: 366 WAD-gated asserts, a 14-capture byte-exact PPM
comparison, and an `--ai-probe` fingerprint. If it would help, `--ppm` + `--ai-probe` make a good
differential harness for the remaining 8 mismatches, since they detect wrong *behaviour*, not just wrong
exit status.

## Consumer-side workaround

Do not set `CYRIUS_IR=3`. cyrius-doom ships on default codegen; the 6.5.4 pin bump was verified byte-identical
to 6.4.78 across 14 `--ppm` captures and the full `--ai-probe` fingerprint, so nothing in the shipped path is
affected. Recorded in doom's `docs/development/state.md` (Known issue #4); doom's roadmap HOLD-C (the deep
perf pass) stays closed on this evidence rather than opening on the v6.5.2 announcement.

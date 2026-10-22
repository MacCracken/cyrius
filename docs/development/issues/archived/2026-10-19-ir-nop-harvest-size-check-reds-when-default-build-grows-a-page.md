# ir_nop_harvest.sh's size check is two-sided on page-rounded sizes: the DEFAULT build growing one page past the IR=3 build turns it red (delta 20,480 > 20,000) — RESOLVED

> ✅ **RESOLVED in v6.7.16** (FF-1, `c70b59bae` — no decision needed (a gate defect). The fix itself — step 2 one-sided, RED only when the IR=3 build is more than 20,000 B LARGER than the default — landed as the genbind lane's GB-8 (`13200c3d1`, wave 3; the receives lane made the same change). FF-1 re-measured it on `450ecf2c9` under `sh` and `bash -eo pipefail` (the merged tree, −16,384, PASS; SI planted at SD − 20,480, the filed F4 shape, PASS; SD + 20,000 PASS; SD + 24,576 RED "+24576"), and the lane's own default build then reached −20,480 against IR=3 (2,656,768 vs 2,636,288 B) and passed. Met running those rows: step 3's bare `cmd; rc=$?` and a failing llvm-objdump exited the gate silent under `bash -eo pipefail`; now `|| rc=$?` / `|| true`, each with its FAIL line (rows: an IR=3 compiler planted as `exit 7` → "rc=7"; llvm-objdump planted as `false` → "disassembles to 0 instructions"). Rows: tests/gates/codegen/ir_nop_harvest.sh's header ledger. CHANGELOG [6.7.16])

**Status:** ✅ **RESOLVED in v6.7.16** (see the banner). Was: 🟡 **OPEN** — found 2026-10-19 by the 6.7.16 frontend lane (unit F4) in its full `sh scripts/check.sh` on the
lane head f626ea03c. Deterministic (not load): the gate builds stage1 = cycc(src) and stage1's `CYRIUS_IR=3` build and
compares their sizes.
**Placement:** 6.7.16 — Break 2, repair 6 (filed from the 6.7.16 frontend lane, wave 1; placed at the wave-1 integration, 2026-10-20 — the user, asked where what 6.7.16 files goes: "INTO .16"; f16 lane, wave 4, unit FF1) — never 7.x.
**Severity:** Medium for the release (check.sh is red, so release-gate step 3 is red) — the compiler is correct: the
gate's own real assertion (the IR=3-built cycc reproduces the default cycc byte-identically) passes.
**Kind:** bug (gate).

## Reproduction

```sh
# on the 6.7.16 frontend lane head (f626ea03c), build/cycc its fixpoint
sh tests/gates/codegen/ir_nop_harvest.sh
# FAIL ir_nop_harvest: IR=3 build is 2530088 B vs default 2550568 B (delta 20480). Un-harvested delta was +65320.
```

Measured sizes (default = cycc(src), IR=3 = that compiler under CYRIUS_IR=3):

| tree | default | IR=3 | IR=3 - default |
|---|---|---|---|
| b2053aff7 (F3 head) | 2,546,472 | 2,530,088 | -16,384 (4 pages) — PASS |
| f626ea03c (F4 head) | 2,550,568 | 2,530,088 | -20,480 (5 pages) — FAIL |
| 478e4f6cd (lane head; the lane review, 2026-10-20) | 2,550,672 | 2,534,288 | -16,384 (4 pages) — PASS |

The lane head is green again only because F5 grew the IR=3 build by 4,200 B and the default by 104 B; the gate's real
assertion (IR=3 reproduces the default byte-identically) passed on all three. Growth from the other lanes on the merged
tree can cross the next page either way, so release-gate step 3 can flip red at integration.

F4's frontend code moved the default build across one 4,096 B page; the IR=3 build (NOPs harvested) stayed in its page.
Every lane's growth lands on the default the same way, so the merged 6.7.16 tree will meet this whichever lane ships
the page.

## Root cause

Step 2 of the gate ("no size regression against the default path", against the un-harvested +65,320) takes the
ABSOLUTE difference: `D=$(( SI - SD )); [ "$D" -lt 0 ] && D=$(( -D ))`, limit 20,000. An IR=3 build SMALLER than the
default is no regression, and both sizes move in whole pages, so the limit is "at most 4 pages either way".

## Direction

Make the check one-sided (`SI - SD > 20000` is the regression the comment names), keeping step 3's byte-identical
reproduction as the correctness assertion; mutation: a planted IR=3 size above the default by > 20,000 still RED.

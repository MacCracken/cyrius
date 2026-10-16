# struct_value_codegen.sh's A rows (struct_value_codegen.tcyr) carry no row-count floor — a gutted values file passes — RESOLVED

> ✅ **RESOLVED in v6.7.13** (VC-1, `88d81a4e`: `tests/gates/codegen/struct_value_codegen.sh`'s A rows carry a row-count floor and require the derived count exactly — NA, the `assert_eq(` rows outside `#ifdef CYRIUS_TARGET_WIN` blocks (220 on the lane), is the exact "N passed, 0 failed (N total)" A1-A6 require (x86_64, IR=1, IR=3, DCE=1, aarch64, cx), NAW (every row, 221) is A7's on PE, and FLOORA refuses a file that lost rows, so the filed gutted values file is RED ("only 0 rows (floor 220)"). The filing's counts (152 / 151, no PE leg) were stale at the open: A7 existed. No decision needed (a gate weakness). Mutations in the gate header, measured: a row deleted RED 1, a row that never runs RED 7, the file gutted RED 1 — the last two were green before. The merge raised FLOORA to 227, the merged file's derived count. CHANGELOG [6.7.13])

**Status:** ✅ **RESOLVED in v6.7.13** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-14 on the 6.7.11 callargs lane. tests/gates/codegen/struct_value_codegen.sh
builds tests/tcyr/crossos/struct_value_codegen.tcyr on six legs (A1-A6: x86_64, CYRIUS_IR=1, CYRIUS_IR=3, CYRIUS_DCE=1,
aarch64 qemu, cx) and passes a leg on any output containing " 0 failed" — so a values file that lost its rows ("0 passed,
0 failed (0 total)", or a run that ends early after its summary) keeps A1-A6 green. CLAUDE.md requires every gate to carry
a corpus floor. The B rows (fncall_struct_result.tcyr) got one in the 6.7.11 callargs review fix (N derived from the
file's `assert_eq(` count, floor 48, the exact "N passed, 0 failed (N total)" line required); the A rows did not, because
their count is target-dependent: the file has 152 `assert_eq(` rows but row F21 sits under `#ifdef CYRIUS_TARGET_WIN`, so
every A leg runs 151 (and no A leg is PE).
**Placement:** 6.7.13 — repair 3: struct values (vectors lane; re-placed at the 6.7.13 open, 2026-10-15) — never 7.x.
**Discovered:** 2026-10-14, the review of the 6.7.11 callargs lane.
**Severity:** Low — a gate weakness (no wrong code); pre-existing since the gate's 6.7.6 A rows.
**Affects:** tests/gates/codegen/struct_value_codegen.sh (6.7.6 onward).

## Reproduction

```
$ awk '/^[[:space:]]*#/{next} /assert_eq\(/{n++} END{print n+0}' tests/tcyr/crossos/struct_value_codegen.tcyr
152
$ build/cycc < tests/tcyr/crossos/struct_value_codegen.tcyr > svc && ./svc | tail -1
151 passed, 0 failed (151 total)            # F21 (`#ifdef CYRIUS_TARGET_WIN`) is not in a non-PE build
# Replace the file's rows by nothing (a scratch copy): A1-A6 stay green — tcyr() greps only ' 0 failed'.
```

## Root cause

`tcyr()` (struct_value_codegen.sh) tests `grep -q ' 0 failed'`; only the B rows set `TN` (the wanted count, 6.7.11).

## Proposed fix

Derive the A count excluding `#ifdef CYRIUS_TARGET_WIN` blocks (the awk `n_cx()` in cx_crossos_rows_run.sh shows the
shape for `#ifndef CYRIUS_TARGET_CX`), set `TN` for A1-A6, and add a floor (151); optionally an A7 PE leg (152, which
would also run F21 off the release gate's cass leg). Mutation: one row deleted -> RED the floor.

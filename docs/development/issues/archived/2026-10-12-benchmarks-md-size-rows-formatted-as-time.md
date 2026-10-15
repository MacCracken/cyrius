# BENCHMARKS.md prints the cycc size rows (byte counts) as milliseconds — `cc5_bytes | 1ms | 2ms | 2ms` — and the file-size row is still named `size/cc5_bytes` — RESOLVED

> ✅ **RESOLVED in v6.7.11** (TL-7: BENCHMARKS.md prints the size group in bytes (`| cycc_bytes | 2,053,536 B | 2,057,736 B | 2,114,376 B | +3.0% |`, the delta a percentage) through a new `fmt_bytes`; every other row is unchanged. The CSV row is written as `size/cycc_bytes` and bench-history.csv's 417 `size/cc5_bytes` rows are renamed, so CSV, markdown and console agree and the series stays one; the header no longer calls the size rows timed; `fmt_ns`'s duplicate branch folded; new `--report` regenerates BENCHMARKS.md from the CSV alone. No decision needed. Rows: `bench_history_size_rows.sh` (32 checks: a fixture CSV through `--report`, the whole script with a stub cycc, the tree read-only); mutations RED (size via `fmt_ns` 5). CHANGELOG [6.7.11])

**Status:** ✅ **RESOLVED in v6.7.11** (see the banner). Was: 🟡 **OPEN** — reproduced 2026-10-12 against the 6.7.10 slot-open tree (`efb6623f`, `build/cycc`
2,057,744 B): the committed `BENCHMARKS.md` (`:155-160`) shows `| cc5_bytes | 1ms | 2ms | 2ms | +7.2% |` and
`| cycc_text_bytes | 1ms | 1ms | 1ms | +7.3% |` for rows whose CSV values are 2,057,736 and 1,845,440 bytes; a fresh
`sh scripts/bench-history.sh` in a `git archive HEAD` copy regenerates the same shape (`| cc5_bytes | 2ms | 2ms |
2ms | +0.2% |`). The CSV row is `size/cc5_bytes` (`scripts/bench-history.sh:215`). The generated header says
"`compiler/*` and `size/*` are timed by `bench_cmd`" (`:312`); the size rows are not timed. ⚠ The hand-off's third
claim does NOT reproduce: release-gate step 5 (`scripts/release-gate.sh:328`) greps the script's STDOUT, where the
file size prints as `size/cycc  2057744 bytes` (`:216`), so the gate shows both `size/cycc` and `size/cycc_text`
(measured in the copy: `compiler/self_compile`, `size/cycc 2057744 bytes`, `size/cycc_text 1845440 bytes`). Only the
CSV / markdown name is stale.
**Placement:** 6.7.11 — repair 1, the scanners / CLI lane (roadmap.md § *6.7.11*) — placed 2026-10-12 — never 7.x.
**Discovered:** 2026-10-12, the 6.7.9 doc sweep (reported in its tools findings; the sweep re-verified
`docs/benchmarks.md` and `benchmark-regimes.md` against these scripts); re-verified and filed by the 6.7.10 planning
lane.
**Severity:** Low — a generated report misstates a metric the CHANGELOG records every release (the growth-tax rule
reads the size delta); the CHANGELOG's number itself comes from the console line, which is right.
**Affects:** `scripts/bench-history.sh` and the `BENCHMARKS.md` it generates since the size rows were added (the
`cc5` name predates the v6.0.0 rename; the `.text` row is v6.5.38).

## Summary

The markdown generator formats every row with `fmt_ns`, the time formatter, whatever its group. For the `size` group
the value is a byte count, so 2,057,736 B prints as `2ms` (÷ 1,000,000) and 1,845,440 B as `1ms`. The delta column is
a byte percentage presented beside "ms" values. The file-size row kept its pre-6.0.0 name `size/cc5_bytes` in the CSV
while the console line beside it says `size/cycc`, so the CSV, the markdown and the console disagree on the name.
(`fmt_ns` also has two identical `ms` branches, `>= 1e9` and `>= 1e6` — cosmetic.)

## Reproduction

```sh
cd /home/macro/Repos/cyrius
grep -n -A5 '^## size' BENCHMARKS.md
grep 'size/' bench-history.csv | tail -2
grep -n 'size/cc5_bytes\|"size/cycc"' scripts/bench-history.sh
# regenerate in a throwaway copy (about two minutes; never in the tree — it rewrites BENCHMARKS.md / the CSV):
W=$(mktemp -d); git archive HEAD | tar -x -C "$W"
( cd "$W" && sh scripts/bench-history.sh 2>&1 | grep -iE 'self_compile|size/cycc'; grep -n -A5 '^## size' BENCHMARKS.md )
rm -rf "$W"
```

```
actual:   159-| cc5_bytes | 1ms | 2ms | 2ms | +7.2% |
          160-| cycc_text_bytes | 1ms | 1ms | 1ms | +7.3% |
          2026-10-12T04:01:21Z,fbcbc512,main,size/cc5_bytes,2057736
          2026-10-12T04:01:21Z,fbcbc512,main,size/cycc_text_bytes,1845440
          scripts/bench-history.sh:215: … size/cc5_bytes …   :216: printf … "size/cycc" …
          (copy)  compiler/self_compile   1499ms / size/cycc 2057744 bytes / size/cycc_text 1845440 bytes
                  | cc5_bytes | 2ms | 2ms | 2ms | +0.2% |
expected: | cycc_bytes | 2,057,736 B | … | +0.2% |  — bytes shown as bytes, one name in CSV, markdown and console
```

## Root cause

- `scripts/bench-history.sh:287-298` `fmt_ns`, applied to every row (`:349-351`) with no per-group formatter.
- `scripts/bench-history.sh:215`: the CSV name `size/cc5_bytes`; `:216` prints `size/cycc` to the console.
- `scripts/bench-history.sh:312`: the header line saying `size/*` rows are timed by `bench_cmd`.

## Proposed fix

In the generator: format the `size` group as bytes (`2,057,736 B`) — a `fmt_bytes` chosen by `GROUP` — keeping the
delta as a percentage. Rename the CSV row `size/cc5_bytes` → `size/cycc_bytes` and rewrite the existing rows of
`bench-history.csv` in the same commit, so the three-run window and the history keep one series. Correct the header
line (only `compiler/*` is timed by `bench_cmd`; `size/*` are byte counts). Fold the duplicate `fmt_ns` branch. Rows
(`tests/gates/toolchain/`, the generator run on a fixture CSV, never on the tree's): a size row renders as bytes, a
time row as ms, the old name absent. Mutation: route `size` back through `fmt_ns` → RED.

## Consumer-side workaround

Read the size from the console line (`size/cycc … bytes`) or the CSV's last `size/cc5_bytes` value, not the
markdown table.

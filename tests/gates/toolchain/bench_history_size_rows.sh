#!/bin/sh
# tests/gates/toolchain/bench_history_size_rows.sh — 6.7.11
#
# BENCHMARKS.md prints the size rows as BYTES, and the cycc file-size row has ONE name.
#
# THE FILED DEFECT (docs/development/issues/2026-10-12-benchmarks-md-size-rows-formatted-as-time.md).
# scripts/bench-history.sh formatted every BENCHMARKS.md row with fmt_ns, the time formatter,
# whatever its group, so the two `size/*` rows — byte counts — printed as milliseconds:
# `| cc5_bytes | 2ms | 2ms | 2ms | +3.0% |` for 2,053,536 / 2,057,736 / 2,114,376 bytes. The CSV row
# kept its pre-6.0.0 name `size/cc5_bytes` while the console line beside it said `size/cycc`, and
# the generated header said `size/*` rows were timed by `bench_cmd` (they are `wc -c` / readelf).
# The fix: the size group is formatted by fmt_bytes (`2,114,376 B`; the delta stays a percentage),
# the row is written as `size/cycc_bytes` and the CSV's 417 old rows were renamed in the same
# commit (one series across the three-run window), the header says what each group is.
#
# HOW. Never on the tree's CSV: every run below is a COPY of scripts/bench-history.sh in a scratch
# root (the script derives its root from its own path), over a fixture CSV.
#   R  `--report` (BENCHMARKS.md from the CSV alone) on a three-run fixture: each size row in
#      bytes, grouped by thousands (999 / 1,000 / 1,000,000 B), each timed row in ms / us / ns
#      exactly as before, every cell of the size section bytes-shaped and none outside it; the CSV
#      is left byte-for-byte and nothing but BENCHMARKS.md is written; with no CSV it is refused
#      by name and writes nothing.
#   E  the WHOLE script (every tier) with a stub build/cycc of exactly 4,096 bytes: the console
#      line release-gate step 5 greps (`size/cycc … 4096 bytes`), one appended `size/cycc_bytes`
#      row of 4096 and no `size/cc5_bytes` row, the fixture's rows untouched, and BENCHMARKS.md's
#      newest column `4,096 B`.
#   T  the tree, read only: no `size/cc5_bytes` row in bench-history.csv (and a floor of renamed
#      `size/cycc_bytes` rows), no `cc5_bytes` in BENCHMARKS.md or the script's code, and
#      BENCHMARKS.md's committed size section bytes-shaped.
#
# MUTATION PROOF (each a scratch root holding this gate, the script and the tree's CSV /
# BENCHMARKS.md, one of them mutated; all RED, "checks failed"; GREEN 32/32 on the real tree):
#   m1  the size group routed back through fmt_ns (`FMT=fmt_bytes` dropped)          5
#   m2  the writer's name back to `size/cc5_bytes`                                     4
#   m3  fmt_bytes without the thousands grouping                                       5
#   m4  the 6.7.10 script (0f733aea: no --report, fmt_ns everywhere, cc5_bytes)       18
#   m5  --report not recognised (it falls through to a bench run)                     14
#   m6  the 6.7.10 bench-history.csv (the 417 rows not renamed)                        2
#   m7  the 6.7.10 BENCHMARKS.md (`| cc5_bytes | 2ms | 2ms | 2ms |`)                   2
set -u
G=bench_history_size_rows
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || exit 2
fails=0
checks=0

check() {
    checks=$((checks + 1))
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 — expected [$2], got [$3]"; fails=$((fails + 1)); fi
}

[ -f "$ROOT/scripts/bench-history.sh" ] || { echo "FAIL: $G — scripts/bench-history.sh missing"; exit 1; }
command -v timeout > /dev/null 2>&1 || { echo "FAIL: $G — needs timeout(1)"; exit 1; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $G: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT

# A scratch root: scripts/bench-history.sh (a copy) + the CSV given as $2.
mkroot() {
    mkdir -p "$1/scripts" && cp "$ROOT/scripts/bench-history.sh" "$1/scripts/bench-history.sh" \
        && cp "$2" "$1/bench-history.csv"
}
# md_row FILE NAME -> the table row whose first cell is NAME (empty when absent)
md_row() { grep -E "^\| $2 \|" "$1" | head -1; }
# md_section FILE GROUP -> the data rows of that group's table
md_section() {
    awk -v g="## $2" '$0 == g {on = 1; next} /^## / {on = 0} on && /^\| / && !/^\| Benchmark / && !/^\|---/' "$1"
}

cat > "$T/fixture.csv" <<'EOF'
timestamp,commit,branch,benchmark,estimate_ns
2026-01-01T00:00:00Z,aaaa1111,main,alloc/8B,42
2026-01-01T00:00:00Z,aaaa1111,main,compiler/self_compile,1499000000
2026-01-01T00:00:00Z,aaaa1111,main,size/cycc_bytes,2053536
2026-01-01T00:00:00Z,aaaa1111,main,size/cycc_text_bytes,1840016
2026-01-01T00:00:00Z,aaaa1111,main,size/tiny_bytes,999
2026-01-01T00:00:00Z,aaaa1111,main,vec/push_100,3566
2026-01-02T00:00:00Z,bbbb2222,main,alloc/8B,43
2026-01-02T00:00:00Z,bbbb2222,main,compiler/self_compile,1504000000
2026-01-02T00:00:00Z,bbbb2222,main,size/cycc_bytes,2057736
2026-01-02T00:00:00Z,bbbb2222,main,size/cycc_text_bytes,1845440
2026-01-02T00:00:00Z,bbbb2222,main,size/tiny_bytes,1000
2026-01-02T00:00:00Z,bbbb2222,main,vec/push_100,3600
2026-01-03T00:00:00Z,cccc3333,main,alloc/8B,41
2026-01-03T00:00:00Z,cccc3333,main,compiler/self_compile,1529000000
2026-01-03T00:00:00Z,cccc3333,main,compiler/trivial,999
2026-01-03T00:00:00Z,cccc3333,main,size/cycc_bytes,2114376
2026-01-03T00:00:00Z,cccc3333,main,size/cycc_text_bytes,1900296
2026-01-03T00:00:00Z,cccc3333,main,size/tiny_bytes,1000000
2026-01-03T00:00:00Z,cccc3333,main,vec/push_100,2146
EOF

echo "== R: --report on a fixture CSV =="
R="$T/r"
mkroot "$R" "$T/fixture.csv" || { echo "FAIL: $G — could not stage $R"; exit 1; }
rc=0
(cd "$T" && timeout 30 sh "$R/scripts/bench-history.sh" --report) > "$T/r.out" 2> "$T/r.err" || rc=$?
check "R0 --report exits 0" 0 "$rc"
check "R0 --report says it updated BENCHMARKS.md" "Updated BENCHMARKS.md" "$(tail -n 1 "$T/r.out")"
M="$R/BENCHMARKS.md"
[ -f "$M" ] || : > "$M"
check "R1 a size row is bytes" "| cycc_bytes | 2,053,536 B | 2,057,736 B | 2,114,376 B | +3.0% |" "$(md_row "$M" cycc_bytes)"
check "R1 the .text size row is bytes" "| cycc_text_bytes | 1,840,016 B | 1,845,440 B | 1,900,296 B | +3.3% |" "$(md_row "$M" cycc_text_bytes)"
check "R1 grouping at 999 / 1,000 / 1,000,000" "| tiny_bytes | 999 B | 1,000 B | 1,000,000 B | +100000.1% |" "$(md_row "$M" tiny_bytes)"
check "R2 a timed row is ms" "| self_compile | 1499ms | 1504ms | 1529ms | +2.0% |" "$(md_row "$M" self_compile)"
check "R2 a timed row is us" "| push_100 | 3us | 3us | 2us | -39.8% |" "$(md_row "$M" push_100)"
check "R2 a timed row is ns" "| 8B | 42ns | 43ns | 41ns | -2.4% |" "$(md_row "$M" 8B)"
check "R2 a missing cell is -" "| trivial | - | - | 999ns | - |" "$(md_row "$M" trivial)"
nsz=$(md_section "$M" size | wc -l | tr -d ' ')
check "R3 the size section has the fixture's three rows" 3 "$nsz"
bad=$(md_section "$M" size | awk -F'|' '{for (i = 3; i <= 5; i++) {c = $i; gsub(/^ +| +$/, "", c); if (c != "-" && c !~ /^[0-9]{1,3}(,[0-9]{3})* B$/) n++}} END {print n + 0}')
check "R3 every size cell is a byte count or -" 0 "$bad"
other=$(for g in alloc compiler vec; do md_section "$M" "$g"; done | grep -c ' B |' || :)
check "R3 no timed row is formatted as bytes" 0 "$other"
check "R3 the header no longer says size/* is timed" 0 "$(grep -c 'and `size/\*` are timed' "$M" || :)"
check "R3 the header says size/* rows are byte counts" 1 "$(grep -c '`size/\*` rows are' "$M" || :)"
cmp -s "$T/fixture.csv" "$R/bench-history.csv"; check "R4 --report leaves the CSV byte-for-byte" 0 "$?"
check "R4 --report writes nothing but BENCHMARKS.md" "BENCHMARKS.md bench-history.csv scripts" "$(ls "$R" | paste -sd' ' -)"
N="$T/n"
mkdir -p "$N/scripts" && cp "$ROOT/scripts/bench-history.sh" "$N/scripts/"
rc=0
(cd "$T" && timeout 30 sh "$N/scripts/bench-history.sh" --report) > "$T/n.out" 2> "$T/n.err" || rc=$?
[ "$rc" -ne 0 ] && rc=refused
check "R5 --report with no CSV is refused" refused "$rc"
check "R5 the refusal names the missing CSV" 1 "$(grep -c "error: no .*bench-history.csv" "$T/n.err" || :)"
check "R5 the refusal writes nothing" "scripts" "$(ls "$N" | paste -sd' ' -)"

echo "== E: the whole script, stub build/cycc of 4,096 bytes =="
E="$T/e"
head -n 7 "$T/fixture.csv" > "$T/fixture2.csv"
grep '^2026-01-02' "$T/fixture.csv" >> "$T/fixture2.csv"
mkroot "$E" "$T/fixture2.csv" || { echo "FAIL: $G — could not stage $E"; exit 1; }
mkdir -p "$E/build"
{ printf '#!/bin/sh\ncat > /dev/null\nexit 0\n#'; head -c 4096 /dev/zero | tr '\0' x; } | head -c 4095 > "$E/build/cycc"
echo >> "$E/build/cycc"
chmod +x "$E/build/cycc"
check "E0 the stub compiler is 4,096 bytes" 4096 "$(wc -c < "$E/build/cycc" | tr -d ' ')"
rc=0
(cd "$T" && GIT_DIR="$T/no-git" timeout 120 sh "$E/scripts/bench-history.sh") > "$E.out" 2> "$E.err" || rc=$?
check "E1 the full run exits 0" 0 "$rc"
check "E2 the console line release-gate step 5 greps" 1 "$(grep -cE '^  size/cycc +4096 bytes$' "$E.out" || :)"
check "E3 one size/cycc_bytes row of 4096 appended" 1 "$(awk -F, 'NR > 1 && $1 !~ /^2026-01-0/ && $4 == "size/cycc_bytes" && $5 == 4096' "$E/bench-history.csv" | wc -l | tr -d ' ')"
check "E3 no size/cc5_bytes row" 0 "$(awk -F, '$4 == "size/cc5_bytes"' "$E/bench-history.csv" | wc -l | tr -d ' ')"
n2=$(wc -l < "$T/fixture2.csv" | tr -d ' ')
head -n "$n2" "$E/bench-history.csv" | cmp -s - "$T/fixture2.csv"; check "E4 the fixture's rows are untouched" 0 "$?"
check "E5 BENCHMARKS.md's newest cycc_bytes cell" "| cycc_bytes | 2,053,536 B | 2,057,736 B | 4,096 B | -99.8% |" "$(md_row "$E/BENCHMARKS.md" cycc_bytes)"

echo "== T: the tree (read only) =="
check "T1 bench-history.csv holds no size/cc5_bytes row" 0 "$(awk -F, '$4 == "size/cc5_bytes"' "$ROOT/bench-history.csv" | wc -l | tr -d ' ')"
nren=$(awk -F, '$4 == "size/cycc_bytes"' "$ROOT/bench-history.csv" | wc -l | tr -d ' ')
[ "$nren" -ge 417 ] && nren=ok
check "T1 the renamed series is whole (>= 417 size/cycc_bytes rows)" ok "$nren"
check "T2 no cc5_bytes in BENCHMARKS.md" 0 "$(grep -c 'cc5_bytes' "$ROOT/BENCHMARKS.md" || :)"
check "T2 no cc5_bytes in the script's code (its comments may name it)" 0 "$(grep -v '^ *#' "$ROOT/scripts/bench-history.sh" | grep -c 'cc5_bytes' || :)"
tsz=$(md_section "$ROOT/BENCHMARKS.md" size | wc -l | tr -d ' ')
[ "$tsz" -ge 1 ] && tsz=ok
check "T3 BENCHMARKS.md has a size section" ok "$tsz"
tbad=$(md_section "$ROOT/BENCHMARKS.md" size | awk -F'|' '{for (i = 3; i <= 5; i++) {c = $i; gsub(/^ +| +$/, "", c); if (c != "-" && c !~ /^[0-9]{1,3}(,[0-9]{3})* B$/) n++}} END {print n + 0}')
check "T3 every committed size cell is a byte count or -" 0 "$tbad"

echo ""
if [ "$fails" -gt 0 ]; then
    for f in r.err e.err; do [ -s "$T/$f" ] && { echo "  ($f, first lines)"; sed -n '1,5p' "$T/$f" | sed 's/^/    /'; }; done
    echo "FAIL: $G — $fails of $checks checks failed"
    exit 1
fi
echo "PASS: $G — $checks checks"
exit 0

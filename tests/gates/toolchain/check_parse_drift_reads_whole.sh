#!/bin/sh
# Gate: the check driver's path-A drift row reads each src/frontend/parse/*.cyr WHOLE (6.6.17).
#
# THE DEFECT. `_parse_emit_drift_gate` (programs/checks/lint_fmt.cyr) read every parse file into
# one fixed 256 KB buffer, and file_read_all stops at the cap without a word. parse/decl.cyr
# (264,737 B), parse/expr.cyr (266,510 B) and parse/fn.cyr (474,667 B) had outgrown it, so a
# direct emit (`EB(S, 0x..`) in their tails was never seen and the row read PASS.
#
# ROWS — the driver built from this tree, its `--parse-drift-row` mode run over a staged root
# holding copies of the eight parse files (6.7.10: parse/cov.cyr joined the six; 6.7.15: parse/fn_def.cyr,
# split from parse/fn.cyr):
#   tree     the real eight files                                -> PASS, "read whole"
#   tail     a direct emit appended to parse/fn.cyr (past 256 KB) -> FAIL naming parse/fn.cyr
#   huge     parse/types.cyr replaced by a 17 MiB (sparse) file    -> FAIL, refused by name
#   missing  parse/ctrl.cyr removed                               -> FAIL, "missing"
#   window   the read-back window opens on a mid-line `fn `      -> PASS (6.6.17 review: offset 0
#            of the window used to count as a line start, a spurious "truncated" FAIL)
# MUTATION (measured by hand, not run here): the read capped back at 262144 bytes fails rows
# tree (the scan read 262144 bytes, fstat says ...) and tail.
#
# Exit 77 (named) when there is no compiler. CHANGELOG [6.6.17]
set -u

NAME=check_parse_drift_reads_whole
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: $NAME — cannot cd to $ROOT"; exit 1; }
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: $NAME — no compiler at $CC"; exit 77; }
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $NAME — mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
fails=0
check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1"
    else echo "  FAIL: $1 — expected $2, got $3"; fails=$((fails + 1)); fi
}
strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

( cd "$ROOT" && "$CC" < programs/checks/main.cyr > "$T/drv" 2> "$T/drv.err" ) \
    || { echo "FAIL: $NAME — the check driver does not compile"; sed 's/^/    /' "$T/drv.err"; exit 1; }
chmod +x "$T/drv"
n=$(ls "$ROOT"/src/frontend/parse/*.cyr | wc -l)
[ "$n" -eq 8 ] || { echo "FAIL: $NAME — expected the 8 parse files the row names, found $n under src/frontend/parse/"; exit 1; }
big=$(wc -c < "$ROOT/src/frontend/parse/fn.cyr")
[ "$big" -gt 262144 ] || { echo "FAIL: $NAME — parse/fn.cyr is $big bytes; the tail row needs a file past 256 KB"; exit 1; }

# stage <dir>: a root holding copies of the eight parse files
stage() { mkdir -p "$1/src/frontend/parse" && cp "$ROOT"/src/frontend/parse/*.cyr "$1/src/frontend/parse/"; }
# row <dir> -> rc; output in <dir>.out (ANSI stripped)
row() { rc=0; ( cd "$1" && timeout 120 "$T/drv" --parse-drift-row ) > "$1.raw" 2>&1 || rc=$?; strip_ansi < "$1.raw" > "$1.out"; echo "$rc"; }

echo "row tree: the real eight files (copied — the row never runs in the tree)"
stage "$T/tree"
check "the row passes" 0 "$(row "$T/tree")"
check "  and says each file was read whole" yes "$(grep -q 'each read whole through its last fn' "$T/tree.out" && echo yes || echo no)"

echo "row tail: a direct emit appended to parse/fn.cyr ($big B)"
stage "$T/tail"
printf '\nfn _pd_tail_probe(S): i64 {\n    EB(S, 0x90);\n    return 0;\n}\n' >> "$T/tail/src/frontend/parse/fn.cyr"
check "the row fails" 1 "$(row "$T/tail")"
check "  naming parse/fn.cyr's direct emit" yes \
    "$(grep -q 'parse/fn.cyr — direct-emit site' "$T/tail.out" && echo yes || echo no)"

echo "row huge: parse/types.cyr replaced by a 17 MiB file"
stage "$T/huge"
rm -f "$T/huge/src/frontend/parse/types.cyr"
truncate -s 17M "$T/huge/src/frontend/parse/types.cyr" 2>/dev/null \
    || dd if=/dev/zero of="$T/huge/src/frontend/parse/types.cyr" bs=1 count=0 seek=17825792 2>/dev/null
check "the row fails" 1 "$(row "$T/huge")"
check "  refusing parse/types.cyr by name" yes \
    "$(grep -q 'parse/types.cyr — refused: empty, or larger than' "$T/huge.out" && echo yes || echo no)"

echo "row missing: parse/ctrl.cyr removed"
stage "$T/miss"
rm -f "$T/miss/src/frontend/parse/ctrl.cyr"
check "the row fails" 1 "$(row "$T/miss")"
check "  naming parse/ctrl.cyr as missing" yes \
    "$(grep -q 'parse/ctrl.cyr — missing' "$T/miss.out" && echo yes || echo no)"

echo "row window: the tail read's first byte is \`fn \` in mid-line, the file's last fn far above it"
stage "$T/win"
# pd_real at offset 0 is the only line-start fn; the last 64 KiB open with "fn " right after
# "# x", so offset 0 of the read-back window is NOT a line start. Exactly 65536 bytes of fill.
{ printf 'fn pd_real(S): i64 {\n    return 0;\n}\n# x'
  awk 'BEGIN { printf "fn "; for (i = 0; i < 1023; i++) { for (j = 0; j < 63; j++) printf "a"; printf "\n" }
               for (j = 0; j < 61; j++) printf "a" }'; } > "$T/win/src/frontend/parse/ctrl.cyr"
check "the row passes (a mid-line \`fn \` at the window's edge is not the last fn)" 0 "$(row "$T/win")"

if [ "$fails" -gt 0 ]; then
    echo "FAIL: $NAME: $fails problem(s)"
    for r in tree tail huge miss win; do [ -f "$T/$r.out" ] && { echo "  -- $r"; sed 's/^/     /' "$T/$r.out" | head -6; }; done
    exit 1
fi
echo "PASS: $NAME (the drift row reads each parse/*.cyr whole, through its last fn; a tail emit past 256 KB, an absurd size and a missing file each fail by name)"
exit 0

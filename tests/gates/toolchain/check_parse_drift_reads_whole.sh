#!/bin/sh
# Gate: the check driver's path-A drift row reads each src/frontend/parse/ file WHOLE (6.6.17), and names
# exactly the files the tree has (6.7.18).
#
# THE DEFECT. `_parse_emit_drift_gate` (programs/checks/lint_fmt.cyr) read every parse file into
# one fixed 256 KB buffer, and file_read_all stops at the cap without a word. parse/decl.cyr
# (264,737 B), parse/expr.cyr (266,510 B) and parse/fn.cyr (474,667 B) had outgrown it, so a
# direct emit (`EB(S, 0x..`) in their tails was never seen and the row read PASS.
#
# ROWS — the driver built from this tree, its `--parse-drift-row` mode run over a staged root
# holding a copy of src/frontend/parse/ (6.7.10: parse/cov.cyr joined the six; 6.7.15: parse/fn/def.cyr,
# split from parse/fn.cyr; 6.7.18: parse/fn.cyr, parse/decl.cyr, parse/expr.cyr and parse/types.cyr split into
# parse/fn/, parse/decl/, parse/expr/ and parse/types/, and parse.cyr's own body into the pieces beside it):
#   list     the row's files (programs/checks/lint_fmt.cyr) == `find src/frontend/parse -name '*.cyr'`
#            -> a file the tree has and the row does not, or the reverse, FAILS by name (6.7.18: the
#            row's list was held to `ls parse/*.cyr | wc -l` = 8, a top-level count a split defeats)
#   tree     the real files                                    -> PASS, "read whole"
#   tail     a direct emit appended to parse/fn/def.cyr (past 256 KB) -> FAIL naming parse/fn/def.cyr
#            (parse/expr.cyr until 6.7.18 split it into pieces under 256 KB)
#   huge     parse/types/type.cyr replaced by a 17 MiB (sparse) file -> FAIL, refused by name
#   missing  parse/ctrl.cyr removed                               -> FAIL, "missing"
#   window   the read-back window opens on a mid-line `fn `      -> PASS (6.6.17 review: offset 0
#            of the window used to count as a line start, a spurious "truncated" FAIL)
#   nofn     a parse file holding no `fn ` at all (parse.cyr once its body is split: the pending flags
#            and the includes) -> PASS, read whole. It was "truncated": the read-back found no fn and
#            took that for a failed read (6.7.18; now a failed read-back is told apart from none)
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
# row list: the row names every parse file the tree has, and nothing else — recursive, sorted, compared
# as sets (a top-level glob or a count would miss a folder's files).
sed -n 's|^ *fail = fail + _parse_drift_scan(_root_path("\(src/frontend/parse/[a-z_/]*\.cyr\)"));.*|\1|p' \
    programs/checks/lint_fmt.cyr | LC_ALL=C sort > "$T/row.list"
find src/frontend/parse -name '*.cyr' | LC_ALL=C sort > "$T/tree.list"
nrow=$(grep -c . "$T/row.list" || true); ntree=$(grep -c . "$T/tree.list" || true)
[ "$ntree" -ge 8 ] || { echo "FAIL: $NAME — only $ntree .cyr under src/frontend/parse/ (corpus floor 8)"; exit 1; }
echo "row list: the drift row names $nrow files, the tree has $ntree"
check "the row's list equals the tree's parse files" "" "$(LC_ALL=C comm -3 "$T/row.list" "$T/tree.list" | tr -d '\t' | tr '\n' ' ')"
big=$(wc -c < "$ROOT/src/frontend/parse/fn/def.cyr")
[ "$big" -gt 262144 ] || { echo "FAIL: $NAME — parse/fn/def.cyr is $big bytes; the tail row needs a file past 256 KB"; exit 1; }

# stage <dir>: a root holding a copy of src/frontend/parse/, its folders included
stage() { mkdir -p "$1/src/frontend" && cp -R "$ROOT/src/frontend/parse" "$1/src/frontend/"; }
# row <dir> -> rc; output in <dir>.out (ANSI stripped)
row() { rc=0; ( cd "$1" && timeout 120 "$T/drv" --parse-drift-row ) > "$1.raw" 2>&1 || rc=$?; strip_ansi < "$1.raw" > "$1.out"; echo "$rc"; }

echo "row tree: the real files (copied — the row never runs in the tree)"
stage "$T/tree"
check "the row passes" 0 "$(row "$T/tree")"
check "  and says each file was read whole" yes "$(grep -q 'each read whole through its last fn' "$T/tree.out" && echo yes || echo no)"

echo "row tail: a direct emit appended to parse/fn/def.cyr ($big B)"
stage "$T/tail"
printf '\nfn _pd_tail_probe(S): i64 {\n    EB(S, 0x90);\n    return 0;\n}\n' >> "$T/tail/src/frontend/parse/fn/def.cyr"
check "the row fails" 1 "$(row "$T/tail")"
check "  naming parse/fn/def.cyr's direct emit" yes \
    "$(grep -q 'parse/fn/def.cyr — direct-emit site' "$T/tail.out" && echo yes || echo no)"

echo "row huge: parse/types/type.cyr replaced by a 17 MiB file"
stage "$T/huge"
rm -f "$T/huge/src/frontend/parse/types/type.cyr"
truncate -s 17M "$T/huge/src/frontend/parse/types/type.cyr" 2>/dev/null \
    || dd if=/dev/zero of="$T/huge/src/frontend/parse/types/type.cyr" bs=1 count=0 seek=17825792 2>/dev/null
check "the row fails" 1 "$(row "$T/huge")"
check "  refusing parse/types/type.cyr by name" yes \
    "$(grep -q 'parse/types/type.cyr — refused: empty, or larger than' "$T/huge.out" && echo yes || echo no)"

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

echo "row nofn: a parse file that holds no \`fn \` (an entry of flags and includes) is read whole and passes"
stage "$T/nofn"
printf '# an entry: flags and includes, no fn\nvar _pd_nofn = 0;\n' > "$T/nofn/src/frontend/parse/cov.cyr"
check "the row passes (a file with no fn is not a truncated file)" 0 "$(row "$T/nofn")"
check "  and says each file was read whole" yes "$(grep -q 'each read whole through its last fn' "$T/nofn.out" && echo yes || echo no)"

if [ "$fails" -gt 0 ]; then
    echo "FAIL: $NAME: $fails problem(s)"
    for r in tree tail huge miss win nofn; do [ -f "$T/$r.out" ] && { echo "  -- $r"; sed 's/^/     /' "$T/$r.out" | head -6; }; done
    exit 1
fi
echo "PASS: $NAME (the drift row names every parse file the tree has and reads each whole, through its last fn; a file with no fn passes; a tail emit past 256 KB, an absurd size and a missing file each fail by name)"
exit 0

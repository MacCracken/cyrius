#!/bin/sh
# Gate: the check driver's CVE-05 scan (no magic-256 NPOS_GUARD in a source-identifier copy site) reads
# every file it names, and a file it names and cannot find FAILS BY NAME (6.7.18).
#
# THE DEFECT. `_cve05_guard_gate` (programs/checks/heap_audit.cyr) walked a hand-kept list of compiler
# sources and SKIPPED a path that did not exist, in silence. A file split or renamed under it (the 6.7.18
# frontend layout moved every one of its parse files, and split two of them) left a path that scanned
# nothing, and the row still read PASS. Now a missing path is a failure naming it, and the PASS line
# counts the files actually scanned.
#
# ROWS — the driver built from this tree, its `--cve05-row` mode run over a staged root holding copies
# of src/frontend/ and src/main*.cyr:
#   tree     the real files                                    -> PASS, "files scanned"
#   missing  src/frontend/parse/expr/factor.cyr removed        -> FAIL, naming it as missing
#   planted  `NPOS_GUARD(S, 256)` appended to parse/types/type.cyr -> FAIL, naming it
# MUTATION (measured, a scratch copy of the tree): `_cve05_scan`'s missing-file arm back to the silent
# skip (`return 0`) -> RED on row missing (the row passes, as it did through 6.7.17).
#
# Exit 77 (named) when there is no compiler. CHANGELOG [6.7.18]
set -u

NAME=check_cve05_scan_names_missing
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
[ -f "$ROOT/src/frontend/parse/expr/factor.cyr" ] && [ -f "$ROOT/src/frontend/parse/types/type.cyr" ] \
    || { echo "FAIL: $NAME — the rows edit parse/expr/factor.cyr and parse/types/type.cyr, and one is gone"; exit 1; }

# stage <dir>: a root holding copies of src/frontend/ and the compiler forks
stage() { mkdir -p "$1/src" && cp -R "$ROOT/src/frontend" "$1/src/" && cp "$ROOT"/src/main*.cyr "$1/src/"; }
# row <dir> -> rc; output in <dir>.out (ANSI stripped)
row() { rc=0; ( cd "$1" && timeout 120 "$T/drv" --cve05-row ) > "$1.raw" 2>&1 || rc=$?; strip_ansi < "$1.raw" > "$1.out"; echo "$rc"; }

echo "row tree: the real files (copied — the row never runs in the tree)"
stage "$T/tree"
check "the row passes" 0 "$(row "$T/tree")"
check "  and counts the files it scanned" yes "$(grep -qE 'mangle-path source file \([0-9]+ files scanned\)' "$T/tree.out" && echo yes || echo no)"

echo "row missing: src/frontend/parse/expr/factor.cyr removed"
stage "$T/miss"
rm -f "$T/miss/src/frontend/parse/expr/factor.cyr"
check "the row fails" 1 "$(row "$T/miss")"
check "  naming parse/expr/factor.cyr as missing" yes \
    "$(grep -q "the scan's file is missing.*src/frontend/parse/expr/factor.cyr" "$T/miss.out" && echo yes || echo no)"

echo "row planted: NPOS_GUARD(S, 256) appended to src/frontend/parse/types/type.cyr"
stage "$T/plant"
printf '\n# NPOS_GUARD(S, 256)\n' >> "$T/plant/src/frontend/parse/types/type.cyr"
check "the row fails" 1 "$(row "$T/plant")"
check "  naming parse/types/type.cyr" yes \
    "$(grep -q 'NPOS_GUARD reappeared in .*src/frontend/parse/types/type.cyr' "$T/plant.out" && echo yes || echo no)"

if [ "$fails" -gt 0 ]; then
    echo "FAIL: $NAME: $fails problem(s)"
    for r in tree miss plant; do [ -f "$T/$r.out" ] && { echo "  -- $r"; sed 's/^/     /' "$T/$r.out" | head -8; }; done
    exit 1
fi
echo "PASS: $NAME (the CVE-05 scan reads every file it names; a missing one and a planted guard each fail by name)"
exit 0

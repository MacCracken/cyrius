#!/bin/sh
# Gate: docs/ecosystem.md's fold table states the version actually vendored in lib/ (v6.5.37).
#
# WHY THIS EXISTS — THE TABLE HAS ROTTED TWICE, THE SAME WAY, AND THE FILE RECORDS THE
# FIRST TIME. docs/ecosystem.md itself says: "At the v6.4.77 fold, 5 of 11 rows were stale
# (sandhi 1.8.2->1.9.3, sankoch 2.5.5->2.7.5, two minors behind; vani, bayan, ganita each
# one)". At v6.5.37 the count was **9 of 11** — and four of those (vani, yukti, mabda,
# yantra) were stale BEFORE that release's fold: their lib/ copies were already current,
# and only the table was wrong. So the rot is not "someone forgot during a fold"; it is
# that nothing ever checked, and a doc with no compile-time check drifts silently.
#
# ⭐ WHY IT MATTERS RATHER THAN BEING A TIDINESS GATE. This table is what a human reads to
# answer "which sigil is in this release?" before deciding whether an upstream fix has
# landed. A stale row is a WRONG ANSWER to that question, and the whole point of the
# fold discipline ("fix the SOURCE repo, not the fold") is that people can trust the
# stated version. The v6.4.77 pass mis-audited it precisely because of the parsing trap
# below, so it under-reported its own staleness.
#
# ⛔ THE PARSING TRAP THAT MADE THE LAST AUDIT UNDERCOUNT: there are THREE bundle header
# formats in this tree, not one.
#   1. `# Version: X.Y.Z`                      — stock `cyrius distlib` output
#   2. `# Bundled distribution of <name> vX.Y.Z` — sakshi's hand-written header
#   3. `var <NAME>_VERSION = "X.Y.Z";`          — an in-source constant
# A scan that knows only format 1 reads sakshi as "(none)" and silently skips it, which is
# exactly how a stale row survives an audit that believes it checked everything. All three
# are handled below; axis 2 asserts every row parsed, so a NEW fourth format fails the gate
# loudly instead of being skipped into a false pass.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
DOC="$ROOT/docs/ecosystem.md"
fail() { echo "FAIL: fold_table_matches_vendored: $1"; exit 1; }
[ -f "$DOC" ] || fail "docs/ecosystem.md not found"

vendored_version() {
    f="$1"
    [ -f "$f" ] || { echo ""; return; }
    v=$(grep -m1 -oE "^# Version: *[0-9][0-9.]*" "$f" 2>/dev/null | grep -oE '[0-9][0-9.]+' || true)
    [ -n "$v" ] || v=$(grep -m1 -oE "Bundled distribution of [a-z]+ v[0-9][0-9.]*" "$f" 2>/dev/null | grep -oE '[0-9][0-9.]+' || true)
    [ -n "$v" ] || v=$(grep -m1 -oE "var [A-Z_]+VERSION[[:space:]]*=[[:space:]]*\"[0-9][0-9.]*\"" "$f" 2>/dev/null | grep -oE '[0-9][0-9.]+' || true)
    echo "$v"
}

ROWS=0
BAD=0
UNPARSED=0
# Table rows look like:  | `lib/<dep>.cyr` | <fold stamp> | <dep> <version> | <prose> |
grep -oE '^\| `lib/[a-z0-9_]+\.cyr` \|[^|]*\| [a-z0-9_]+ [0-9][0-9.]*' "$DOC" | while read -r _; do :; done
grep -E '^\| `lib/[a-z0-9_]+\.cyr` \|' "$DOC" > /tmp/_foldrows.$$ || true
while IFS= read -r line; do
    dep=$(printf '%s' "$line" | sed -nE 's/^\| `lib\/([a-z0-9_]+)\.cyr`.*/\1/p')
    [ -n "$dep" ] || continue
    stated=$(printf '%s' "$line" | sed -nE "s/^\| \`lib\/${dep}\.cyr\` \|[^|]*\| ${dep} ([0-9][0-9.]*) \|.*/\1/p")
    ROWS=$((ROWS + 1))
    if [ -z "$stated" ]; then
        echo "  row for $dep: could not parse a stated version from the table"
        UNPARSED=$((UNPARSED + 1)); continue
    fi
    actual=$(vendored_version "$ROOT/lib/$dep.cyr")
    if [ -z "$actual" ]; then
        echo "  $dep: lib/$dep.cyr has NO parseable version header (a fourth header format?)"
        UNPARSED=$((UNPARSED + 1)); continue
    fi
    if [ "$stated" != "$actual" ]; then
        echo "  $dep: table says $stated, lib/$dep.cyr is $actual"
        BAD=$((BAD + 1))
    fi
    echo "$dep $stated $actual" >> /tmp/_foldres.$$
done < /tmp/_foldrows.$$

# The while-loop above runs in this shell (input redirection, not a pipe), so the counters
# survive — but recompute from the result file too, because a subshell here would silently
# zero them and the gate would pass vacuously. That failure mode is the whole reason axis 2
# exists.
[ -f /tmp/_foldres.$$ ] || fail "no fold rows were parsed at all — the table shape changed"
NROWS=$(wc -l < /tmp/_foldres.$$ | tr -d ' ')
MISMATCH=$(awk '$2 != $3' /tmp/_foldres.$$ | wc -l | tr -d ' ')
rm -f /tmp/_foldrows.$$ /tmp/_foldres.$$

# ── axis 1: every stated version equals the vendored one ────────────────────────────
[ "$MISMATCH" -eq 0 ] || fail "$MISMATCH fold-table row(s) disagree with lib/ (see above)"

# ── axis 2: anti-vacuous — the gate actually inspected a plausible number of rows ────
# Without this, a table-shape change (or a regex that stops matching) makes the gate pass
# while checking NOTHING. The tree has had 11-12 folds for several minors; 8 is a floor,
# not a target, and it should be raised only alongside a real change in the fold set.
[ "$NROWS" -ge 8 ] || fail "only $NROWS fold rows parsed (expected >= 8) — the table shape or the parser changed"

# ── axis 3: nothing was skipped for want of a header format ─────────────────────────
[ "$UNPARSED" -eq 0 ] || fail "$UNPARSED fold row(s) unparsed — a header format is unhandled, which is how the last audit undercounted"

echo "PASS: fold_table_matches_vendored ($NROWS rows, all stated versions match lib/)"

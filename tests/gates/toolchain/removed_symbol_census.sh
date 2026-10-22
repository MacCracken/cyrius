#!/bin/sh
# Gate: a public stdlib symbol cannot DISAPPEAR without its accounting record (6.7.16: in-tree only).
#
# ⛔ THE INCIDENT THIS EXISTS FOR (v6.6.0). `tagged_new` and `payload` were deleted from
# lib/tagged.cyr, justified in the source header and restated in seven other places as
# "nothing in the ecosystem called it (verified across all 12 sibling stdlibs at the v6.6.0 cut)".
#
# The survey was REAL and its RESULT was CORRECT — the twelve fold-table stdlibs genuinely have
# zero callers, historically too. The failure is entirely in the SCOPE of the claim:
#   * `CHANGELOG.md` carried the honest qualifier ("in any of the 12 sibling stdlibs")
#   * `docs/stdlib-reference.md`, ONE FILE AWAY, dropped it ("nothing in the ecosystem")
#   * the membership list of "the 12" appears NOWHERE in the tree
# `tagged_new` is not Result scaffolding — it is the general runtime-tag box constructor, and its
# users are DOMAIN libraries, a class the stdlib survey could not see. agnostik calls it 19 times
# and agnova 9. A primitive was removed on a survey that structurally could not find its consumer.
#
# ⭐ WHAT IT DOES (6.7.16 — re-scoped to THIS checkout). When a public symbol vanishes from
# docs/api-surface.snapshot (vs the last release tag), the gate is RED unless the symbol has a row
# in docs/retired-symbols.allow — the ACCOUNTING record, with its migration reference — and it
# names every file in this checkout that still calls the symbol. Forcing the answer to be WRITTEN
# DOWN is the whole fix. It is `find` + `grep`, not a build.
#
# ⛔ 6.7.16: IT NO LONGER CENSUSES OTHER REPOS. It used to walk every repo beside this checkout
# (CYRIUS_SIBLING_ROOT, default the checkout's parent: ~146 consumer repos) and to require a row
# only when one of them still called the symbol — a consumer survey inside a gate, and a language
# does not gate on other projects (the user, 2026-10-19;
# docs/development/issues/archived/2026-10-19-gates-read-other-projects-checkouts.md). The census reads the
# source roots of THIS checkout (lib/ src/ cbt/ programs/ tests/ benches/ fuzz/ bootstrap/), and
# lib/ vendors the 12 folded stdlibs, so the folds are covered as vendored. Since a tree that
# compiles rarely still calls a removed name, EVERY removed public name now needs its row — the
# accounting is forced for each removal, not only for one some consumer happened to call. A
# consumer meets a removal at its pin bump, through the ledger and ecosystem-migration.md.
#
# It never SKIPs: everything it reads is in this checkout. (It SKIPped without sibling checkouts,
# and without build/cyrius_api_surface, which it never ran.)
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
SNAPSHOT="$ROOT/docs/api-surface.snapshot"
ALLOW="$ROOT/docs/retired-symbols.allow"
WORK=$(mktemp -d) && [ -d "$WORK" ] || { echo "FAIL: removed_symbol_census: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: removed_symbol_census: $1"; exit 1; }
cd "$ROOT"

[ -f "$SNAPSHOT" ] || fail "docs/api-surface.snapshot missing"
[ -f "$ALLOW" ]    || fail "docs/retired-symbols.allow missing — the accounting ledger IS the fix"

# ── 1. what disappeared since the last RELEASED tag? ────────────────────────────────────
# ⚠ THE BASELINE IS THE LAST RELEASE TAG, NOT HEAD, AND THAT IS LOAD-BEARING. The first cut of
# this gate diffed against HEAD and reported "0 removed" for a release that had just deleted
# `tagged::tag/1` — because the deletion was already committed. HEAD moves as work lands, so it
# answers "what changed since the last commit", which is never the question. The question is
# "what does THIS RELEASE remove from the surface consumers are pinned to", and only a release
# tag answers it. Falls back to HEAD when no tag is reachable (a fresh clone / shallow CI).
# The newest tag comes from `for-each-ref --count=1`, not `git tag … | head -1`: head exits after
# one line, git dies of SIGPIPE on its next write, and under `bash -eo pipefail` (GitHub's `run:`
# shell) that 141 ended the gate here with no verdict. tests/gates/toolchain/
# gates_verdict_under_pipefail.sh runs this file that way. CHANGELOG [6.7.15]
BASE_TAG=$(git -C "$ROOT" for-each-ref --count=1 --sort=-v:refname --format='%(refname:short)' 'refs/tags/[0-9]*.[0-9]*.[0-9]*' 2>/dev/null || true)
if [ -n "$BASE_TAG" ] && git -C "$ROOT" show "$BASE_TAG:docs/api-surface.snapshot" > "$WORK/head.snap" 2>/dev/null; then
    :
elif git -C "$ROOT" show HEAD:docs/api-surface.snapshot > "$WORK/head.snap" 2>/dev/null; then
    BASE_TAG="HEAD (no release tag reachable)"
else
    cp "$SNAPSHOT" "$WORK/head.snap"; BASE_TAG="(none — census degraded to allowlist-only)"
fi
# name only, arity stripped — a re-arity is a different (also breaking) class, handled by the
# api-surface gate; this one is about a name that can no longer be called AT ALL.
sed 's|.*::||; s|/.*||' "$WORK/head.snap" | sort -u > "$WORK/before.txt"
sed 's|.*::||; s|/.*||' "$SNAPSHOT"       | sort -u > "$WORK/after.txt"
comm -23 "$WORK/before.txt" "$WORK/after.txt" > "$WORK/removed.txt"

# ── 2. the allowlist ────────────────────────────────────────────────────────────────────
sed 's/#.*//' "$ALLOW" | awk -F'|' 'NF>=3 {gsub(/ /,"",$1); if ($1!="") print $1}' | sort -u > "$WORK/allowed.txt"
[ -s "$WORK/allowed.txt" ] || fail "the allowlist parsed to ZERO rows — the format changed and this gate is now vacuous"

# ── 3. census helper: comment-stripped, definitions excluded ────────────────────────────
# The census root is the CURRENT directory (the checkout, or 3b's scratch root) and the walk is
# RELATIVE (`./lib/…`), so a `/build/` in the checkout's own absolute path cannot prune it.
# `|| true`: `head -400` closing the pipe kills the loop with SIGPIPE past 400 files, and the
# loop's own status is its last file's miss — under `bash -eo pipefail` either one made the
# caller's `HITS=$(…)` end the gate with no verdict. Each file's calls are COUNTED (`grep -c`,
# which reads to the end), not `grep -q`'d: -q exits on its first hit, the `sed | grep -v` feeding
# it die of SIGPIPE on a file past the 64 KB pipe buffer, and pipefail made that the line's status
# — so under `bash -eo pipefail` a large file calling the symbol early was silently NOT counted.
# 3b below pins it. CHANGELOG [6.7.15]
CENSUS_DIRS="lib src cbt programs tests benches fuzz bootstrap"
_census_all() {
    _sym=$1
    for _d in $CENSUS_DIRS; do
        [ -d "$_d" ] || continue
        find "./$_d" \( -name '*.cyr' -o -name '*.tcyr' -o -name '*.bcyr' -o -name '*.fcyr' \) \
             -not -path './build/*' -not -path '*/.git/*' 2>/dev/null || true
    done | while IFS= read -r f; do
        _n=$(sed 's/#.*//' "$f" 2>/dev/null \
             | grep -vE "^[[:space:]]*(pub[[:space:]]+)?fn[[:space:]]+${_sym}[[:space:]]*\(" \
             | grep -cE "(^|[^_a-zA-Z0-9.])${_sym}[[:space:]]*\(" || true)
        if [ "${_n:-0}" -gt 0 ]; then echo "$f"; fi
      done || true
}
_census() { _census_all "$1" | head -400 || true; }

# ── 3b. the census reads a file to its end, under either shell ──────────────────────────
# A ~200 KB file whose only `alloc(` call is on its FIRST line, in a scratch census root (walked
# relatively, so no `*/build/*` in TMPDIR's own path can hide it), must be found once.
mkdir -p "$WORK/scr/lib"
{ echo 'fn f() { return alloc(8); }'; _i=0
  while [ "$_i" -lt 3000 ]; do echo "var pad$_i = $_i;   # padding past the 64 KB pipe buffer ........"; _i=$((_i + 1)); done
} > "$WORK/scr/lib/big.cyr"
BIG=$( (cd "$WORK/scr" && _census "alloc") | wc -l | tr -d ' ')
[ "$BIG" = 1 ] || fail "self-test: the census found ${BIG} files calling 'alloc' in a scratch root holding one $(wc -c < "$WORK/scr/lib/big.cyr")-byte file that calls it on line 1 (want 1) — a large caller is invisible to it"

# ── 4. every removal must be accounted for ──────────────────────────────────────────────
# Every removed public name needs its row (6.7.16 — see the header); the in-tree callers, if
# any, are named with it.
UNACCOUNTED=""
while IFS= read -r sym; do
    [ -n "$sym" ] || continue
    case "$sym" in _*) continue ;; esac          # private names were never ecosystem surface
    if grep -qx "$sym" "$WORK/allowed.txt"; then continue; fi
    HITS=$(_census "$sym" | wc -l | tr -d ' ')
    echo "  ⛔ '$sym' was REMOVED from the public surface with no row in docs/retired-symbols.allow"
    if [ "${HITS:-0}" -gt 0 ]; then
        echo "     and this checkout still calls it in $HITS file(s):"
        _census "$sym" | sed 's|^\./||' | head -12 | sed 's/^/       /' || true
    fi
    UNACCOUNTED="$UNACCOUNTED $sym"
done < "$WORK/removed.txt"

if [ -n "$UNACCOUNTED" ]; then
    echo ""
    echo "  A public stdlib symbol disappeared without its accounting record (the v6.6.0 shape)."
    echo "  Removing one is the user's call: either restore it, or add a row to"
    echo "  docs/retired-symbols.allow naming the migration doc and what a consumer meets at its pin"
    echo "  bump. A row is an ACCOUNTING RECORD, not a mute button."
    fail "unaccounted removed symbols:$UNACCOUNTED"
fi

# ── 5. ANTI-VACUOUS: the census must actually be able to FIND things ────────────────────
# Without this the gate passes on a broken find, an unreadable root, or a comment-stripping regex
# that stopped matching — reporting "all clear" while looking at nothing. `alloc` is called
# throughout the tree and is not going anywhere. The floors are DERIVED from the 6.7.16 tree (the
# probe found 356 files: lib 63, src 21, cbt 9, programs 37, tests 218, benches 5, fuzz 3): the
# total must reach about half of that (175), so a regex or walk that broke reads ~0, and every
# root that calls it then (lib src cbt programs tests) must still show at least one, so a walk
# that lost a whole root fails by name. Raise them as the tree grows; never lower them to pass.
_census_all "alloc" > "$WORK/probe.txt"
PROBE=$(wc -l < "$WORK/probe.txt" | tr -d ' ')
[ "${PROBE:-0}" -ge 175 ] || fail "anti-vacuous: the census found only ${PROBE} files calling 'alloc' in this checkout (floor 175) — it is not actually searching, so a clean result proves nothing"
for _d in lib src cbt programs tests; do
    _pn=$(grep -c "^\./$_d/" "$WORK/probe.txt" || true)
    [ "${_pn:-0}" -ge 1 ] || fail "anti-vacuous: the census found no file calling 'alloc' under $_d/ — the walk lost that root"
done

# ── 6. every allowlist row must still be JUSTIFIED ──────────────────────────────────────
# A row whose symbol is back on the public surface is stale, and a stale row silences a future
# real removal of that same name. This is the rot direction the ledger is otherwise prone to.
STALE=""
while IFS= read -r a; do
    [ -n "$a" ] || continue
    grep -qx "$a" "$WORK/after.txt" && STALE="$STALE $a"
done < "$WORK/allowed.txt"
[ -z "$STALE" ] || fail "allowlist rows for symbols that are PUBLIC again (stale, and they would mask a future removal):$STALE"

NREM=$(wc -l < "$WORK/removed.txt" | tr -d ' ')
NALLOW=$(wc -l < "$WORK/allowed.txt" | tr -d ' ')
echo "PASS: removed_symbol_census (${NREM} removed vs ${BASE_TAG}, ${NALLOW} accounted in the ledger, census probe ${PROBE} files in this checkout)"

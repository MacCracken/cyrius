#!/bin/sh
# Gate: a public stdlib symbol cannot DISAPPEAR without an ecosystem census being taken.
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
# ⭐ WHAT THIS GATE CAN AND CANNOT DO. It cannot PROVE an ecosystem survey from inside this repo —
# ~/Repos may be absent, partial, or stale. It can FORCE one: when a public symbol vanishes from
# docs/api-surface.snapshot, this censuses every repo it can see and goes RED unless the symbol is
# accounted for in docs/retired-symbols.allow with a migration reference. Forcing the census, and
# forcing the answer to be WRITTEN DOWN, is the whole fix. It is `find` + `grep`, not a build.
#
# ⚠ IT CENSUSES VENDORED lib/ AND dist/ TOO, and that is deliberate: 55-68 sibling repos gitignore
# their vendored stdlib, so `git status` is structurally blind to it, and the vendored copies are
# where the damage actually lands on the next `cyrius deps`. Excluding them understated the v6.6.0
# radius by an order of magnitude.
#
# ⚠ SKIPS CLEANLY when ~/Repos is absent (CI has no sibling checkouts). A gate that cannot run
# must say so out loud rather than passing quietly — that is the macOS-rot lesson.
set -eu

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
SIBLINGS=${CYRIUS_SIBLING_ROOT:-"$(dirname "$ROOT")"}
SNAPSHOT="$ROOT/docs/api-surface.snapshot"
ALLOW="$ROOT/docs/retired-symbols.allow"
TOOL="$ROOT/build/cyrius_api_surface"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
fail() { echo "FAIL: removed_symbol_census: $1"; exit 1; }
cd "$ROOT"

[ -f "$SNAPSHOT" ] || fail "docs/api-surface.snapshot missing"
[ -f "$ALLOW" ]    || fail "docs/retired-symbols.allow missing — the accounting ledger IS the fix"
[ -x "$TOOL" ]     || { echo "SKIP: removed_symbol_census (build/cyrius_api_surface not built)"; exit 0; }
[ -d "$SIBLINGS" ] || { echo "SKIP: removed_symbol_census (no sibling checkouts at $SIBLINGS)"; exit 0; }

# ── 1. what disappeared since the last RELEASED tag? ────────────────────────────────────
# ⚠ THE BASELINE IS THE LAST RELEASE TAG, NOT HEAD, AND THAT IS LOAD-BEARING. The first cut of
# this gate diffed against HEAD and reported "0 removed" for a release that had just deleted
# `tagged::tag/1` — because the deletion was already committed. HEAD moves as work lands, so it
# answers "what changed since the last commit", which is never the question. The question is
# "what does THIS RELEASE remove from the surface consumers are pinned to", and only a release
# tag answers it. Falls back to HEAD when no tag is reachable (a fresh clone / shallow CI).
BASE_TAG=$(git -C "$ROOT" tag --list '[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname 2>/dev/null | head -1)
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
_census() {
    _sym=$1
    find "$SIBLINGS" -maxdepth 3 \( -name '*.cyr' -o -name '*.tcyr' \) \
         -not -path '*/build/*' -not -path '*/.git/*' 2>/dev/null \
    | while IFS= read -r f; do
        sed 's/#.*//' "$f" 2>/dev/null \
        | grep -vE "^[[:space:]]*(pub[[:space:]]+)?fn[[:space:]]+${_sym}[[:space:]]*\(" \
        | grep -qE "(^|[^_a-zA-Z0-9.])${_sym}[[:space:]]*\(" && echo "$f"
      done | head -400
}

# ── 4. every removal must be accounted for ──────────────────────────────────────────────
UNACCOUNTED=""
while IFS= read -r sym; do
    [ -n "$sym" ] || continue
    case "$sym" in _*) continue ;; esac          # private names were never ecosystem surface
    if grep -qx "$sym" "$WORK/allowed.txt"; then continue; fi
    HITS=$(_census "$sym" | wc -l | tr -d ' ')
    if [ "${HITS:-0}" -gt 0 ]; then
        echo "  ⛔ '$sym' was REMOVED from the public surface and is still called in $HITS file(s):"
        _census "$sym" | sed "s|$SIBLINGS/||" | head -12 | sed 's/^/       /'
        UNACCOUNTED="$UNACCOUNTED $sym"
    fi
done < "$WORK/removed.txt"

if [ -n "$UNACCOUNTED" ]; then
    echo ""
    echo "  A public stdlib symbol disappeared while consumers still call it."
    echo "  This is the v6.6.0 shape: a survey that could not see the callers."
    echo "  Either restore it, or add a row to docs/retired-symbols.allow naming who calls it"
    echo "  and where the migration is tracked. A row is an ACCOUNTING RECORD, not a mute button."
    fail "unaccounted removed symbols:$UNACCOUNTED"
fi

# ── 5. ANTI-VACUOUS: the census must actually be able to FIND things ────────────────────
# Without this the gate passes in an empty/unreadable sibling tree, on a broken find, or if the
# comment-stripping regex ever stops matching — reporting "all clear" while looking at nothing.
# `alloc` is in every vendored stdlib and is not going anywhere.
PROBE=$(_census "alloc" | wc -l | tr -d ' ')
[ "${PROBE:-0}" -ge 5 ] || fail "anti-vacuous: the census found only ${PROBE} files calling 'alloc' across $SIBLINGS — it is not actually searching, so a clean result proves nothing"

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
echo "PASS: removed_symbol_census (${NREM} removed vs ${BASE_TAG}, ${NALLOW} accounted in the ledger, census probe ${PROBE} files)"

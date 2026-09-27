#!/bin/sh
# tests/gates/toolchain/version_bump_doc_anchors.sh — 6.6.7 (bite 10)
#
# The NEXT `version-bump.sh` can rewrite every document anchor in the LIVE tree, and a bump
# that fails to rewrite one says so and exits non-zero.
#
# THE DEFECT. Step 5 rewrote the roadmap stamp with
#   s/\*\*Current head: v$OLD\*\*[[:space:]]*([0-9-]*)/.../
# — basic regex, so `(`/`)` were literal and the parenthetical could hold ONLY a date, and
# OLD's dots were unescaped. The stamp is annotated by hand: at 6.6.6 it read
# `**Current head: v6.6.6** (2026-09-20, bump commit; tag pending)`, the 6.6.7 bump matched
# nothing, exited 0, and the stamp was fixed by hand (bump commit 99a03056); the 6.6.7 stamp
# `(2026-09-27, slot open; 6.6.6 tagged at …)` defeated the 6.6.8 bump the same way (measured
# on a copy: rc 0, zero `Current head: v6.6.8` lines). Steps 3 (CLAUDE.md) and 4 (CHANGELOG)
# ended in `|| true` with no verification at all, the summary printed VERSION, CLAUDE.md and
# CHANGELOG.md under "Updated:" unconditionally (the same-version path too) and never listed
# cyrius.cyml, and the only failure report was a string inside that list under exit 0.
# Nothing exercised the rewrites, and the stamp's only reader (the driver's doc-stamp row)
# accepts VERSION anywhere within 240 B of `Current head:`, so an unrewritable stamp read
# fine until bump day.
#
# THE FIX. Every rewrite is `sed -E` with the old version's dots escaped; step 5 replaces any
# parenthetical that has no nested parentheses; each step is VERIFIED (new anchor present,
# old anchor gone, exactly one CHANGELOG header), named on stderr at the step, and the script
# exits non-zero at the END; the summary reports what each file actually did. A
# `--docs-only <dir> <version>` mode runs only the document steps over copies, which is what
# lets this gate forecast the next bump over the live docs without rebuilding or installing.
#
# AXES
#   A  the LIVE docs (VERSION, CLAUDE.md, cyrius.cyml, CHANGELOG.md, roadmap.md, copied to a
#      scratch dir) bumped to the next patch version: rc 0, every anchor names it, the
#      roadmap stamp is `(YYYY-MM-DD)`, and each file differs by exactly one line (CHANGELOG:
#      one header + one blank). RED here means someone hand-wrote an anchor the next bump
#      cannot rewrite — fix the anchor (e.g. keep `)` out of the stamp's parenthetical).
#   B  fixture: the 6.6.6 annotated stamp rewrites; an in-flight `## [Unreleased] — …` header
#      is RENAMED, not duplicated.
#   C  fixture: dot-escaping — `v6x6x6` / `6x6x6` decoys beside the real 6.6.6 anchors are
#      left untouched.
#   D  fixture: a stamp with NESTED parentheses is refused (rc≠0, roadmap.md named, the line
#      byte-for-byte unchanged — not cut at the first `)`).
#   E  fixture: each missing anchor (CLAUDE.md line, cyrius.cyml pin, CHANGELOG header,
#      roadmap stamp) is rc≠0 and named on stderr; the OTHER files are still rewritten (the
#      exit is at the END, not the first failure); the summary does not call the file updated.
#   F  the FULL bump path (no --docs-only) in a scratch dir holding only docs: the summary
#      lists cyrius.cyml, says build/cycc and the install snapshot were NOT refreshed (none
#      exist there), and a failed anchor still exits non-zero after the build section ran.
#   G  the same-version path and a malformed version are refused by --docs-only, touching
#      nothing; the tree's own docs are untouched by the whole gate.
#
# MUTATIONS (each RED; run by hand when this gate was written)
#   m1 step 5 back on the basic-regex date-only pattern                    A, B1
#   m2 OLD_RE = OLD (dots unescaped)                                        C
#   m3 `[^)]*` for `[^()]*` in step 5                                       D
#   m4 _vb_result never counts a failure (exit 0)                           D, E, F2
#   m5 exit on the FIRST failed step instead of at the end                  E (others rewritten)
#   m6 cyrius.cyml dropped from the steps' report                           A, F1
#   m7 CLAUDE.md step unverified (`_vb_result … 1` regardless)              E(CLAUDE.md)
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
VB="$ROOT/scripts/version-bump.sh"
T=$(mktemp -d) && [ -d "$T" ] || { echo "  FAIL: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
# cwd is the scratch dir, never the tree: whatever the script does relative to its cwd lands here.
cd "$T" || exit 2

FAILS=0
CHECKS=0
_ok()  { CHECKS=$((CHECKS + 1)); }
_bad() { CHECKS=$((CHECKS + 1)); FAILS=$((FAILS + 1)); echo "  FAIL: $1"; }
_expect() { if eval "$2"; then _ok; else _bad "$1"; fi; }

_tree_sum() {
    for _f in VERSION CLAUDE.md cyrius.cyml CHANGELOG.md docs/development/roadmap.md; do
        cksum < "$ROOT/$_f"
    done
}
TREE_BEFORE=$(_tree_sum)

# ---- A: the live docs, bumped to the next patch -----------------------------------------
V=$(tr -d '[:space:]' < "$ROOT/VERSION")
case "$V" in
    [0-9]*.[0-9]*.[0-9]*) ;;
    *) echo "  FAIL: VERSION '$V' is not X.Y.Z[-N]"; exit 1 ;;
esac
_base=${V%%-*}
NEXT="${_base%.*}.$(( ${_base##*.} + 1 ))"
TODAY=$(date +%Y-%m-%d)
NEXT_RE=$(printf '%s' "$NEXT" | sed 's/\./\\./g')
V_RE=$(printf '%s' "$V" | sed 's/\./\\./g')

L="$T/live"
mkdir -p "$L/docs/development"
cp "$ROOT/VERSION" "$ROOT/CLAUDE.md" "$ROOT/cyrius.cyml" "$ROOT/CHANGELOG.md" "$L/"
cp "$ROOT/docs/development/roadmap.md" "$L/docs/development/"
rc=0
sh "$VB" --docs-only "$L" "$NEXT" > "$T/A.out" 2> "$T/A.err" || rc=$?
if [ "$rc" != 0 ]; then
    _bad "A: the next bump ($V -> $NEXT) over the LIVE docs exits $rc — an anchor in the tree cannot be rewritten:"
    sed 's/^/        /' "$T/A.err"
else
    _ok
fi
_expect "A: VERSION copy is not $NEXT" '[ "$(tr -d "[:space:]" < "$L/VERSION")" = "$NEXT" ]'
_expect "A: CLAUDE.md copy has no \`- **Version**: $NEXT\` line" 'grep -qE "^- \*\*Version\*\*: ${NEXT_RE}\$" "$L/CLAUDE.md"'
_expect "A: cyrius.cyml copy's self-pin is not $NEXT" 'grep -qE "^cyrius = \"${NEXT_RE}\"" "$L/cyrius.cyml"'
_expect "A: CHANGELOG.md copy does not have exactly one \`## [$NEXT]\` header" '[ "$(grep -cE "^## \[${NEXT_RE}\]" "$L/CHANGELOG.md")" = 1 ]'
_expect "A: roadmap.md copy's stamp is not \`**Current head: v$NEXT** ($TODAY)\`" 'grep -qE "^\*\*Current head: v${NEXT_RE}\*\* \(${TODAY}\)" "$L/docs/development/roadmap.md"'
_expect "A: a \`**Current head: v$V**\` stamp survived the bump" '! grep -qE "\*\*Current head: v${V_RE}\*\*" "$L/docs/development/roadmap.md"'
for _f in CLAUDE.md cyrius.cyml CHANGELOG.md docs/development/roadmap.md; do
    _d=$(diff "$ROOT/$_f" "$L/$_f" | grep -c '^[<>]')
    _expect "A: $_f copy changed $_d diff lines, expected exactly 2 (one anchor)" '[ "$_d" = 2 ]'
done
for _f in VERSION CLAUDE.md cyrius.cyml CHANGELOG.md docs/development/roadmap.md; do
    _expect "A: the report does not say $_f was updated" 'grep -qF "  $_f  (updated)" "$T/A.out"'
done

# ---- fixture builder ------------------------------------------------------------------------
# _fx <dir> [stamp-line] — a minimal tree at 6.6.6 with every anchor in its live shape.
_fx() {
    rm -rf "$1"; mkdir -p "$1/docs/development"
    printf '6.6.6\n' > "$1/VERSION"
    printf '# X\n\n- **Type**: compiler\n- **Version**: 6.6.6\n' > "$1/CLAUDE.md"
    printf '[package]\nname = "x"\ncyrius = "6.6.6"\n' > "$1/cyrius.cyml"
    printf '# Changelog\n\nIntro.\n\n## [6.6.6] — 2026-09-20\n\n- a fix\n\n## [6.6.5] — 2026-09-19\n' > "$1/CHANGELOG.md"
    printf '# Roadmap\n\n## Where we are\n\n%s — cycc **1 B** ·\nmore figures.\n' \
        "${2:-**Current head: v6.6.6** (2026-09-20, bump commit; tag pending)}" > "$1/docs/development/roadmap.md"
}
_run() { # <name> <dir> <version> — rc in $RC, stdout/stderr in $T/<name>.out/.err
    RC=0
    sh "$VB" --docs-only "$2" "$3" > "$T/$1.out" 2> "$T/$1.err" || RC=$?
}

# ---- B: annotated stamp; in-flight Unreleased header -------------------------------------
_fx "$T/b1"
_run B1 "$T/b1" 6.6.7
_expect "B1: the 6.6.6 annotated stamp was not rewritten (rc $RC): $(cat "$T/B1.err")" \
    '[ "$RC" = 0 ] && grep -qE "^\*\*Current head: v6\.6\.7\*\* \(${TODAY}\) — cycc" "$T/b1/docs/development/roadmap.md"'
_fx "$T/b2"
printf '# Changelog\n\n## [Unreleased] — `.7` in flight\n\n- wip\n\n## [6.6.6] — 2026-09-20\n' > "$T/b2/CHANGELOG.md"
_run B2 "$T/b2" 6.6.7
_expect "B2: the in-flight \`## [Unreleased] — …\` header was not renamed to \`## [6.6.7]\`" \
    '[ "$RC" = 0 ] && [ "$(grep -c "^## \[6\.6\.7\] — ${TODAY}\$" "$T/b2/CHANGELOG.md")" = 1 ] && ! grep -q "^## \[Unreleased\]" "$T/b2/CHANGELOG.md"'

# ---- C: dots are escaped ----------------------------------------------------------------
_fx "$T/c"
printf '\n**Current head: v6x6x6** (decoy)\n' >> "$T/c/docs/development/roadmap.md"
printf -- '- **Version**: 6x6x6\n' >> "$T/c/CLAUDE.md"
printf 'cyrius = "6x6x6"\n' >> "$T/c/cyrius.cyml"
_run C "$T/c" 6.6.7
_expect "C: rc $RC for the real anchors beside the decoys" '[ "$RC" = 0 ]'
_expect "C: the \`v6x6x6\` roadmap decoy was rewritten — OLD's dots are not escaped" \
    'grep -qxF "**Current head: v6x6x6** (decoy)" "$T/c/docs/development/roadmap.md"'
_expect "C: the \`6x6x6\` CLAUDE.md decoy was rewritten" 'grep -qxF -- "- **Version**: 6x6x6" "$T/c/CLAUDE.md"'
_expect "C: the \`6x6x6\` cyrius.cyml decoy was rewritten" 'grep -qxF "cyrius = \"6x6x6\"" "$T/c/cyrius.cyml"'

# ---- D: nested parentheses are refused, not cut --------------------------------------------
NESTED='**Current head: v6.6.6** (2026-09-20, slot open (tag pending)) — x'
_fx "$T/d" "$NESTED"
_run D "$T/d" 6.6.7
_expect "D: a nested-parenthesis stamp exited $RC, not non-zero" '[ "$RC" != 0 ]'
_expect "D: stderr does not name roadmap.md" 'grep -q "docs/development/roadmap.md NOT UPDATED" "$T/D.err"'
_expect "D: the nested-parenthesis stamp line was altered (cut at the first \`)\`?)" \
    'grep -qxF "$NESTED — cycc **1 B** ·" "$T/d/docs/development/roadmap.md"'

# ---- E: each missing anchor is loud, and the other files still get rewritten ------------------
_fx "$T/e1"; printf '# X\n\n- **Version**: 6.6.5\n' > "$T/e1/CLAUDE.md"
_fx "$T/e2"; printf '[package]\ncyrius = "6.6.4"\n' > "$T/e2/cyrius.cyml"
_fx "$T/e3"; printf '# Changelog\n\nno headers\n' > "$T/e3/CHANGELOG.md"
_fx "$T/e4" '**Current head: v6.6.5** (2026-09-19) — stale stamp naming another version'
# (_expect evals its condition inside a function, so the loop names its values _cd/_cf —
# positional parameters there would be _expect's own.)
for _c in "e1 CLAUDE.md" "e2 cyrius.cyml" "e3 CHANGELOG.md" "e4 docs/development/roadmap.md"; do
    _cd=${_c%% *}; _cf=${_c#* }
    _run "E_$_cd" "$T/$_cd" 6.6.7
    _expect "E($_cf): a missing anchor exited $RC, not non-zero" '[ "$RC" != 0 ]'
    _expect "E($_cf): stderr does not name $_cf" 'grep -qF "$_cf NOT UPDATED" "$T/E_$_cd.err"'
    _expect "E($_cf): the summary calls $_cf updated" '! grep -qE "^  $_cf  \((updated|already)" "$T/E_$_cd.out"'
    _expect "E($_cf): the summary does not mark $_cf NOT UPDATED" 'grep -qF "  $_cf  <-- NOT UPDATED" "$T/E_$_cd.out"'
    # the exit is at the END: every OTHER anchor was still rewritten
    [ "$_cf" = CLAUDE.md ] || _expect "E($_cf): CLAUDE.md was not rewritten — the script stopped at the first failure" \
        'grep -qx -- "- \*\*Version\*\*: 6\.6\.7" "$T/$_cd/CLAUDE.md"'
    [ "$_cf" = docs/development/roadmap.md ] || _expect "E($_cf): roadmap.md was not rewritten — the script stopped at the first failure" \
        'grep -q "^\*\*Current head: v6\.6\.7\*\*" "$T/$_cd/docs/development/roadmap.md"'
done

# ---- F: the full bump path, in a scratch dir that holds only docs -----------------------------
# No src/, build/ or scripts/ exist there, so nothing is regenerated, rebuilt or installed:
# every relative path the full path uses resolves inside $T/f*.
_fx "$T/f1"
RC=0; (cd "$T/f1" && sh "$VB" 6.6.7) > "$T/F1.out" 2> "$T/F1.err" || RC=$?
_expect "F1: full path over a good fixture exited $RC: $(cat "$T/F1.err")" '[ "$RC" = 0 ]'
_expect "F1: the summary does not list cyrius.cyml as updated" 'grep -qF "  cyrius.cyml  (updated)" "$T/F1.out"'
_expect "F1: the summary claims build/cycc was rebuilt where none exists" 'grep -qF "build/cycc  (NOT rebuilt" "$T/F1.out"'
_expect "F1: the summary claims an install refresh where install.sh is absent" 'grep -qF "install snapshot NOT refreshed" "$T/F1.out"'
_expect "F1: the old \"Updated:\" list (unconditional) is still printed" '! grep -q "^Updated:" "$T/F1.out"'
_fx "$T/f2" "$NESTED"
RC=0; (cd "$T/f2" && sh "$VB" 6.6.7) > "$T/F2.out" 2> "$T/F2.err" || RC=$?
_expect "F2: full path with an unrewritable stamp exited $RC, not non-zero" '[ "$RC" != 0 ]'
_expect "F2: the failure exited before the build/install section ran" 'grep -q "^Build + install:" "$T/F2.out"'

# ---- G: refusals that touch nothing; the tree is untouched --------------------------------
_fx "$T/g1"; G1_BEFORE=$(cat "$T/g1/VERSION" "$T/g1/CLAUDE.md" "$T/g1/CHANGELOG.md" | cksum)
_run G1 "$T/g1" 6.6.6
_expect "G1: --docs-only at the SAME version exited $RC, not non-zero" '[ "$RC" != 0 ]'
_run G2 "$T/g1" '6.6.7/x'
_expect "G2: --docs-only accepted a malformed version (rc $RC)" '[ "$RC" != 0 ]'
_expect "G: a refused run modified the fixture" '[ "$(cat "$T/g1/VERSION" "$T/g1/CLAUDE.md" "$T/g1/CHANGELOG.md" | cksum)" = "$G1_BEFORE" ]'
_expect "G: the gate modified the TREE's docs" '[ "$(_tree_sum)" = "$TREE_BEFORE" ]'

# anti-vacuous floor: every axis above contributes checks
if [ "$CHECKS" -lt 50 ]; then
    echo "  FAIL: only $CHECKS checks ran (floor 50) — the gate went vacuous"
    FAILS=$((FAILS + 1))
fi
if [ "$FAILS" -gt 0 ]; then
    echo "  FAIL: version_bump_doc_anchors — $FAILS of $CHECKS checks red"
    exit 1
fi
echo "  PASS: version_bump_doc_anchors — the next bump ($V -> $NEXT) rewrites every live anchor; $CHECKS checks (annotated stamp, dot-escaping, nested-paren refusal, loud missing anchors, honest summary, exit at the end)"
exit 0

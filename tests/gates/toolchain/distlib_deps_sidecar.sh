#!/bin/sh
# Gate: `dist/<lib>.deps` reports every stdlib leaf the fold requires (v6.5.10).
#
# THE FILED DEFECT (setu 0.8.2, 2026-08-07). The sidecar's own header says it lists
# "stdlib leaves this fold requires in scope", but it was built ONLY by scanning the
# bundled module sources for literal `include "lib/X.cyr"` lines — so it captured what a
# module INCLUDES, never what it REFERENCES through the declaration. setu emitted **8**
# leaves against a declared **12**; the four missing (`result`, `net`, `chrono`, `args`)
# are all referenced at top level in its `src/client.cyr`.
#
# ⭐ WHY THIS IS MORE THAN A DOCUMENTATION WART: A WRONG SIDECAR SWITCHES OFF cyrius's OWN
# CONSUMER CHECK. `cyrius deps` validates a consumer's `[deps] stdlib` against the dep's
# sidecar — correctly and loudly. The filer measured both directions: with a corrected
# 12-leaf sidecar, an under-declaring consumer got a hard error naming `chrono` and
# `args`; with the raw 8-leaf one the SAME consumer built **OK**, silently, on agnos.
# The under-reporting sidecar simply told the check there was nothing to complain about.
#
# ⚠ Three hypotheses were measured and FALSIFIED before this was filed, and repeating any
# of them wastes a slot: it is not the declaration (deleting `assert` from `[deps] stdlib`
# left `assert` in the sidecar), it is not an inline-comment parse bug (adding a comment
# to `vec` left `vec` present, even though all four missing entries happened to carry
# comments), and it is not a direct-symbol scan. It was a smaller thing than its header.
#
# THE FIX IS A UNION, NOT A REPLACEMENT — the include-scan can legitimately catch a leaf
# the author forgot to declare, so taking both can never under-report relative to either.
#
# ⚠ BASE BUNDLE ONLY. A profile bundle is a narrow subset of modules, so its true dep set
# is a subset of the declaration; unioning the whole declaration into a `sha` profile
# would OVER-report and could fail a legitimately-narrow consumer against the very check
# this fix re-enables. Profiles keep the pruned inference — asserted below.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CY="$ROOT/build/cyrius"
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
fails=0

check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 — expected $2, got $3"; fails=$((fails + 1)); fi
}

[ -x "$CY" ] || { echo "  FAIL: build/cyrius missing"; exit 1; }

mkdir -p "$D/p/src" "$D/p/dist"
cd "$D/p" || exit 2
# `used_only` is DECLARED but never `include`d by a module — it is the shape the filing is
# about: referenced through the declaration, invisible to an include-scan. `inc_only` is
# the reverse: included by a module but NOT declared, which is what makes union (rather
# than replacement) the right call.
printf '[package]\nname = "dp"\nversion = "0.1.0"\n\n[deps]\nstdlib = [\n    "string",\n    "fmt",\n    "used_only",   # referenced, never included — the filed case\n]\n\n[lib]\nmodules = ["src/a.cyr"]\n\n[lib.narrow]\nmodules = ["src/b.cyr"]\n' > cyrius.cyml
printf 'include "lib/string.cyr"\nfn a_one(): i64 { return 1; }\n' > src/a.cyr
printf 'include "lib/fmt.cyr"\nfn b_two(): i64 { return 2; }\n' > src/b.cyr

echo "axis 1 — a DECLARED-but-not-included leaf reaches the sidecar:"
CYRIUS_RESOLVED=1 timeout 300 "$CY" distlib > "$D/o1" 2>&1
check "distlib exits 0" 0 "$?"
DEPS="$D/p/dist/dp.deps"
check "sidecar written" 1 "$([ -f "$DEPS" ] && echo 1 || echo 0)"
# ⭐ THE ASSERTION THE DEFECT WOULD FAIL. Pre-fix this leaf was absent.
check "declared-only leaf 'used_only' is present" 1 "$(grep -cx 'used_only' "$DEPS" || true)"
check "declared 'fmt' is present (not included by src/a.cyr)" 1 "$(grep -cx 'fmt' "$DEPS" || true)"

echo "axis 2 — the include-scan's own finding is KEPT (union, not replacement):"
check "included leaf 'string' still present" 1 "$(grep -cx 'string' "$DEPS" || true)"
check "no duplicate entries" "$(grep -vc '^#' "$DEPS")" "$(grep -v '^#' "$DEPS" | sort -u | wc -l | tr -d ' ')"

echo "axis 3 — a leaf INCLUDED but not declared survives (why union is the right call):"
printf 'include "lib/string.cyr"\ninclude "lib/vec.cyr"\nfn a_one(): i64 { return 1; }\n' > src/a.cyr
CYRIUS_RESOLVED=1 timeout 300 "$CY" distlib > "$D/o3" 2>&1
check "undeclared-but-included 'vec' is present" 1 "$(grep -cx 'vec' "$DEPS" || true)"
check "and the declared ones are still there" 1 "$(grep -cx 'used_only' "$DEPS" || true)"

echo "axis 4 — ⚠ a PROFILE keeps the pruned inference, not the whole declaration:"
CYRIUS_RESOLVED=1 timeout 300 "$CY" distlib narrow > "$D/o4" 2>&1
NDEPS="$D/p/dist/dp-narrow.deps"
if [ -f "$NDEPS" ]; then
    # `used_only` is declared but has nothing to do with the narrow profile's module.
    # Over-reporting here would fail a legitimately-narrow consumer.
    check "profile sidecar does NOT absorb the whole declaration" 0 "$(grep -cx 'used_only' "$NDEPS" || true)"
else
    check "profile sidecar emitted (or legitimately empty)" 1 1
fi

echo "axis 5 — the manifest scan does not match prose or a longer identifier:"
# cmd_deps' key-boundary rules are reused deliberately; a comment mentioning "stdlib" or a
# key like `my_stdlib` must not be picked up as the declaration.
#
# ⚠ THE DECOY MUST COME **BEFORE** THE REAL KEY. The scan stops at its first match, so a
# decoy appended after the real declaration is never even considered — an earlier version
# of this axis did exactly that and passed against a build with the comment guard DELETED.
# Mutation-verified. Fresh project so the ordering is unambiguous.
mkdir -p "$D/decoy/src" "$D/decoy/dist" && cd "$D/decoy" || exit 2
printf '# this leading comment mentions stdlib and must not match\nmy_stdlib = ["bogus_leaf"]\n\n[package]\nname = "dc"\nversion = "0.1.0"\n\n[deps]\nstdlib = ["string", "used_only"]\n\n[lib]\nmodules = ["src/a.cyr"]\n' > cyrius.cyml
printf 'include "lib/string.cyr"\nfn c_one(): i64 { return 1; }\n' > src/a.cyr
CYRIUS_RESOLVED=1 timeout 300 "$CY" distlib > "$D/o5" 2>&1
DDEPS="$D/decoy/dist/dc.deps"
# ⚠ `grep -c` PRINTS 0 and EXITS 1 on no-match, so `|| echo 0` appends a SECOND line and
# the comparison sees "0\n0". Capture plainly and default only when the var is empty.
NB=$(grep -cx 'bogus_leaf' "$DDEPS" 2>/dev/null); NB=${NB:-0}
NU=$(grep -cx 'used_only' "$DDEPS" 2>/dev/null); NU=${NU:-0}
check "a prose/identifier 'stdlib' does not inject leaves" 0 "$NB"
check "the real declaration still resolved" 1 "$NU"

cd "$ROOT" || exit 2
echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: distlib-deps-sidecar — declaration ∪ include-scan, profiles stay pruned"
    exit 0
fi
echo "FAIL: distlib-deps-sidecar — $fails assertion(s) failed"
exit 1

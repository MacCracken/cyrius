#!/bin/sh
# Gate: `dist/<lib>.deps` is what the BUNDLE needs — compile-verified — and never what the
# manifest happens to declare (6.6.18, D4: P4 option 2; it was the v6.5.10 union gate).
#
# THE HISTORY THIS GATE CARRIES. v6.5.10 (setu 0.8.2) found the sidecar built only from a
# module include-scan, so a leaf REFERENCED but never included (`result`, `net`, `chrono`,
# `args` — 4 of setu's 12) was missing, and a wrong sidecar switched off `cyrius deps`' own
# consumer check. The fix then was to UNION the declared `[deps] stdlib` into the sidecar.
# v6.5.37 added the compile-verify fixpoint, which derives every referenced leaf on its own —
# and from then on the union's only remaining effect was to PUBLISH the package's own
# test-only leaves to every consumer: 75 ecosystem sidecars name `assert` and 68 of those
# bundles reference no assert symbol; 51 of 53 name `bench` and use none of it. It also hid
# real gaps behind a declaration (niyama's `unicode` family, mabda's agnos `io` — D1/D3).
#
# ⭐ NOW: the seed is the `lib/` includes the bundled modules KEEP (they ship in the bundle, so
# they are the artifact's own hard requirement); everything else is what the fixpoint finds
# undefined. The umbrella (src/lib.cyr, src/main.cyr) is not scanned and `[deps] stdlib` is
# not unioned — it still feeds auto-prepend and `cyrius deps` for the package's OWN builds.
#
# Axes
#   1  the setu case survives: `string` and `chrono` are REFERENCED (strlen, clock_now_ns) with
#      no include and land in the sidecar; `math` is a module-kept include and lands too.
#      (⚠ not `fmt`: fmt.cyr includes string.cyr and vec.cyr, so with fmt kept, strlen is never
#      undefined and `string` is correctly NOT a leaf — measured.)
#   2  ⛔ the inversion of the old axis 1: declared-only `assert` and `bench`, and `vec` (included
#      only by the NON-module umbrella), are NOT in the sidecar. Old code: all three present.
#   3  rekha's regression: adding `include "lib/fmt.cyr"` to the umbrella leaves the sidecar
#      byte-identical (the umbrella is not an input).
#   4  the sidecar is byte-identical with and without a `[deps] stdlib` key.
#   5  a profile's sidecar is scoped to its own module: it has `fmt`, not `chrono`.
#   6  no stdlib snapshot -> distlib refuses by name and writes no sidecar (the verify is the
#      only authority left; it used to publish unverified).
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CY=${CYRIUS_BIN:-"$ROOT/build/cyrius"}
D=$(mktemp -d) && [ -d "$D" ] || { echo "FAIL: distlib_deps_sidecar: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$D"' EXIT
fails=0

check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1 ($3)"
    else echo "  FAIL: $1 — expected $2, got $3"; fails=$((fails + 1)); fi
}
has() { n=$(grep -cx "$1" "$2" 2>/dev/null); echo "${n:-0}"; }

[ -x "$CY" ] || { echo "  FAIL: build/cyrius missing"; exit 1; }
CC=${CYCC:-"$ROOT/build/cycc"}
mkdir -p "$D/tools" && cp "$CY" "$D/tools/cyrius" && cp "$CC" "$D/tools/cycc" \
    && ( cd "$ROOT" && "$CC" < src/main_aarch64.cyr > "$D/tools/cycc_aarch64" 2>/dev/null ) \
    && chmod +x "$D/tools/cyrius" "$D/tools/cycc" "$D/tools/cycc_aarch64" \
    || { echo "SKIP: distlib_deps_sidecar: could not stage cycc + cycc_aarch64 beside the CLI"; exit 77; }
CY="$D/tools/cyrius"

mkdir -p "$D/p/src" "$D/p/dist"
cd "$D/p" || exit 2
manifest() {  # manifest <with-stdlib-key: 1|0>
    printf '[package]\nname = "dp"\nversion = "0.1.0"\n\n' > cyrius.cyml
    [ "$1" = 1 ] && printf '[deps]\nstdlib = ["string", "chrono", "assert", "bench"]\n\n' >> cyrius.cyml
    printf '[lib]\nmodules = ["src/a.cyr"]\n\n[lib.narrow]\nmodules = ["src/b.cyr"]\n' >> cyrius.cyml
}
manifest 1
printf 'include "lib/math.cyr"\nfn a_one(): i64 { return strlen("ab") + clock_now_ns(); }\n' > src/a.cyr
printf 'include "lib/math.cyr"\nfn b_two(): i64 { return 2; }\n' > src/b.cyr
printf 'include "lib/vec.cyr"\ninclude "src/a.cyr"\n' > src/lib.cyr
DEPS="$D/p/dist/dp.deps"

echo "axis 1 — referenced leaves and module-kept includes reach the sidecar:"
rc=0; CYRIUS_RESOLVED=1 timeout 300 "$CY" distlib > "$D/o1" 2>&1 || rc=$?
check "distlib exits 0" 0 "$rc"
check "sidecar written" 1 "$([ -f "$DEPS" ] && echo 1 || echo 0)"
check "referenced-only 'string' (strlen) is present" 1 "$(has string "$DEPS")"
check "referenced-only 'chrono' (clock_now_ns) is present — the setu case" 1 "$(has chrono "$DEPS")"
check "module-kept include 'math' is present" 1 "$(has math "$DEPS")"
check "no duplicate entries" "$(grep -vc '^#' "$DEPS")" "$(grep -v '^#' "$DEPS" | sort -u | wc -l | tr -d ' ')"

echo "axis 2 — declared-only and umbrella-only leaves are NOT published:"
check "declared-only 'assert' is absent" 0 "$(has assert "$DEPS")"
check "declared-only 'bench' is absent" 0 "$(has bench "$DEPS")"
check "umbrella-only 'vec' is absent" 0 "$(has vec "$DEPS")"
cp "$DEPS" "$D/base.deps"

echo "axis 3 — an umbrella include does not change the sidecar (rekha):"
printf 'include "lib/vec.cyr"\ninclude "lib/fmt.cyr"\ninclude "src/a.cyr"\n' > src/lib.cyr
CYRIUS_RESOLVED=1 timeout 300 "$CY" distlib > "$D/o3" 2>&1
check "sidecar byte-identical with lib/fmt.cyr added to src/lib.cyr" 0 "$(cmp -s "$D/base.deps" "$DEPS"; echo $?)"

echo "axis 4 — the [deps] stdlib key never reaches the sidecar:"
manifest 0
CYRIUS_RESOLVED=1 timeout 300 "$CY" distlib > "$D/o4" 2>&1
check "sidecar byte-identical without a [deps] stdlib key" 0 "$(cmp -s "$D/base.deps" "$DEPS"; echo $?)"
manifest 1

echo "axis 5 — a profile's sidecar is scoped to its own module:"
CYRIUS_RESOLVED=1 timeout 300 "$CY" distlib narrow > "$D/o5" 2>&1
NDEPS="$D/p/dist/dp-narrow.deps"
check "profile sidecar written" 1 "$([ -f "$NDEPS" ] && echo 1 || echo 0)"
check "profile sidecar has its kept include 'math'" 1 "$(has math "$NDEPS")"
check "profile sidecar does NOT carry the base module's 'chrono'" 0 "$(has chrono "$NDEPS")"

echo "axis 6 — no stdlib snapshot is a refusal, not an unverified sidecar:"
mkdir -p "$D/emptyhome" "$D/ns/src" && cd "$D/ns" || exit 2
printf '[package]\nname = "ns"\nversion = "0.1.0"\n\n[lib]\nmodules = ["src/a.cyr"]\n' > cyrius.cyml
printf 'fn ns_one(): i64 { return strlen("x"); }\n' > src/a.cyr
rc=0; CYRIUS_HOME="$D/emptyhome" CYRIUS_RESOLVED=1 timeout 300 "$CY" distlib > "$D/o6" 2>&1 || rc=$?
check "distlib exits non-zero with no snapshot" 1 "$([ "$rc" -ne 0 ] && echo 1 || echo 0)"
check "the refusal names the missing snapshot" 1 "$(grep -c 'no stdlib snapshot' "$D/o6")"
check "no sidecar written" 0 "$([ -f "$D/ns/dist/ns.deps" ] && echo 1 || echo 0)"

cd "$ROOT" || exit 2
echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: distlib-deps-sidecar — the sidecar is what the bundle needs (compile-verified); [deps] stdlib and the umbrella are not published"
    exit 0
fi
echo "FAIL: distlib-deps-sidecar — $fails assertion(s) failed"
exit 1

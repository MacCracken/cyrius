#!/bin/sh
# Gate: `cyrius distlib --all` regenerates EVERY declared bundle, and `--check` reports any
# that is stale instead of silently passing (v6.5.8, W1 item 6).
#
# THE MOTIVATING FAILURE. `cyrius distlib` regenerates exactly ONE bundle per invocation
# and nothing could ask the manifest which `[lib.<name>]` profiles exist — so every
# multi-profile repo ran an N+1 ritual maintained by hand in its release script. That is
# how sankoch 2.7.6's silent-data-corruption gzip fix nearly shipped with all NINE
# sub-bundles still carrying the buggy encoder under a fresh version string: the main
# bundle was regenerated, the profiles were not, and nothing compared them.
#
# ⛔ AND THE COMMAND THE ISSUE TOLD PEOPLE TO REACH FOR ALREADY "WORKED". Because the old
# arg loop skipped anything starting with `-`, `distlib --all` and `--check` were swallowed
# and ran the base-bundle-only path, exiting 0. A flag that is silently ignored is worse
# than one that errors, because the green tick is indistinguishable from success.
#
# ⚠ THE COMPARISON IS BYTE-FOR-BYTE, NOT VERSION-STRING. Comparing version strings is
# precisely what let sankoch's stale profiles look fresh — they carried the NEW version and
# the OLD encoder. Content is the only thing that answers "was this regenerated".
#
# ⚠ TESTED ON A LOCAL FIXTURE, NOT ON sigil/sankoch — those manifests pin an older cyrius
# (`cyrius = "6.4.69"`) and the CLI RE-EXECS the pinned version, so a run there exercises
# the pinned binary, not this build. Verified by `cyrius version` reporting 6.4.69 from
# inside sankoch. Do not "confirm" this feature against a pinned repo.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
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
# No `cyrius = "..."` pin: an unpinned manifest is what makes the CLI use THIS build.
printf '[package]\nname = "dp"\nversion = "0.1.0"\n\n[lib]\nmodules = ["src/a.cyr"]\n\n[lib.core]\nmodules = ["src/a.cyr"]\n\n[lib.extra]\nmodules = ["src/b.cyr"]\n' > cyrius.cyml
printf 'fn a_one(): i64 { return 1; }\n' > src/a.cyr
printf 'fn b_two(): i64 { return 2; }\n' > src/b.cyr

echo "axis 1 — --all regenerates the base bundle AND every [lib.X] profile:"
timeout 300 "$CY" distlib --all > "$D/o1" 2>&1
check "exit 0" 0 "$?"
check "reports 3 bundles (base + 2 profiles)" 1 "$(grep -c '3 bundle(s) regenerated' "$D/o1" || true)"
check "dist/dp.cyr written"       1 "$([ -f dist/dp.cyr ] && echo 1 || echo 0)"
check "dist/dp-core.cyr written"  1 "$([ -f dist/dp-core.cyr ] && echo 1 || echo 0)"
check "dist/dp-extra.cyr written" 1 "$([ -f dist/dp-extra.cyr ] && echo 1 || echo 0)"

echo "axis 2 — --check on a current tree passes and writes nothing:"
cp dist/dp-extra.cyr "$D/before-extra"
timeout 300 "$CY" distlib --check > "$D/o2" 2>&1
check "exit 0 when everything is current" 0 "$?"
check "all three reported current" 3 "$(grep -c 'current:' "$D/o2" || true)"
check "--check did not modify the bundle" 1 "$(cmp -s dist/dp-extra.cyr "$D/before-extra" && echo 1 || echo 0)"
check "no .check- temp files left behind" 0 "$(ls -a dist/ | grep -c '^\.check-' || true)"

echo "axis 3 — ⭐ the sankoch 2.7.6 shape: a source changes, the bundle does not:"
printf 'fn b_two(): i64 { return 222; }\n' > src/b.cyr
timeout 300 "$CY" distlib --check > "$D/o3" 2>&1
rc3=$?
check "exit NON-zero on drift" 1 "$([ "$rc3" -ne 0 ] && echo 1 || echo 0)"
check "the stale bundle is NAMED" 1 "$(grep -c 'STALE: dist/dp-extra.cyr' "$D/o3" || true)"
check "the unaffected bundles stay current" 2 "$(grep -c 'current:' "$D/o3" || true)"
check "still no temp files left behind" 0 "$(ls -a dist/ | grep -c '^\.check-' || true)"

echo "axis 4 — flags are parsed, not swallowed:"
timeout 60 "$CY" distlib --bogus > "$D/o4" 2>&1
check "unknown flag exits non-zero" 1 "$([ "$?" -ne 0 ] && echo 1 || echo 0)"
check "and names it" 1 "$(grep -c 'unknown option' "$D/o4" || true)"
timeout 60 "$CY" distlib --all core > "$D/o5" 2>&1
check "--all plus an explicit profile is rejected" 1 "$([ "$?" -ne 0 ] && echo 1 || echo 0)"

echo "axis 5 — profile enumeration is line-anchored (comments must not register):"
printf '\n# [lib.ghost] this is a comment, not a profile\n' >> cyrius.cyml
timeout 300 "$CY" distlib --check > "$D/o6" 2>&1
check "commented-out profile is NOT enumerated" 1 "$(grep -c '3 bundle(s) checked' "$D/o6" || true)"

cd "$ROOT" || exit 2
echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: distlib-all-profiles — every declared bundle regenerated, drift named and fatal"
    exit 0
fi
echo "FAIL: distlib-all-profiles — $fails assertion(s) failed"
exit 1

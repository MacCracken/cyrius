#!/bin/sh
# Gate: `cyrius distlib`'s bundle self-check ACTUALLY COMPILES the bundle, and a bundle
# that does not compile is a FAILURE rather than a reassuring note (v6.5.14).
#
# THE MOTIVATING DEFECT — a check that had never once run. The self-check was
#     var check_r = compile(out_path, "/dev/null");
# and `compile()` writes an intermediate `<output>.tmp.<pid>` for its atomic rename.
# `/dev/null.tmp.<pid>` cannot be created (/dev/ is not writable), so the call failed on
# the WRITE every single time — before cycc ever saw the bundle. The handler then printed
#     note: bundle has unresolved symbols (expected for consumer-included bundles...)
# and exited 0. So a syntactically broken bundle and a perfect one produced byte-identical
# reassuring output. This is the SAME defect v5.7.8 fixed for `cyrius check` (see the
# comment at cbt/commands.cyr ~line 566); distlib never got the same treatment.
#
# ⭐ TWO WRONGS THAT LOOKED LIKE ONE RIGHT. Fixing only the temp path exposes the second
# half: piping the bundle down cycc's STDIN hits the 1 MB `input_buf` cap, and sigil's main
# bundle passed 1 MB (1,079,068 B), so the largest and most load-bearing bundle in the
# ecosystem would have started failing for a reason no consumer ever meets — consumers
# `include` the bundle, which cycc resolves from DISK with no such cap. The check therefore
# compiles through a generated one-line entry that `include`s the bundle, which is exactly
# how a consumer uses it. Do not "simplify" this back to piping the bundle to stdin.
#
# ⚠ UNDEFINED FNS ARE THE ONE EXPECTED FAILURE and are downgraded with --allow-undef (a
# bundle deliberately ships no stdlib). EVERYTHING else must stay fatal — otherwise this
# is a green placebo again, just a slower one.
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
# Unpinned manifest so the CLI uses THIS build rather than re-execing a pinned version.
printf '[package]\nname = "bp"\nversion = "0.1.0"\n\n[lib]\nmodules = ["src/a.cyr"]\n' > cyrius.cyml
printf 'fn a_one(): i64 { return 1; }\n' > src/a.cyr

echo "axis 1 — a well-formed bundle passes cleanly, with NO 'unresolved symbols' note:"
timeout 300 "$CY" distlib > "$D/o1" 2>&1
check "exit 0" 0 "$?"
check "bundle written" 1 "$([ -f dist/bp.cyr ] && echo 1 || echo 0)"
check "no 'unresolved symbols' note on a clean bundle" 0 "$(grep -c 'unresolved symbols' "$D/o1" || true)"
check "no 'cannot write output' (the /dev/null tell)" 0 "$(grep -c 'cannot write output' "$D/o1" || true)"
check "no '1MB buffer' (the stdin-cap tell)" 0 "$(grep -c '1MB buffer' "$D/o1" || true)"

echo "axis 2 — ⭐ THE REGRESSION: a bundle that does not compile must FAIL, not reassure:"
printf 'fn a_one(): i64 { return 1; }\nfn broken( {\n' > src/a.cyr
timeout 300 "$CY" distlib > "$D/o2" 2>&1
rc2=$?
check "exit NON-zero on a broken bundle" 1 "$([ "$rc2" -ne 0 ] && echo 1 || echo 0)"
check "the bundle is NAMED in the error" 1 "$(grep -c 'does not compile' "$D/o2" || true)"
check "and it does NOT claim 'unresolved symbols'" 0 "$(grep -c 'unresolved symbols' "$D/o2" || true)"
printf 'fn a_one(): i64 { return 1; }\n' > src/a.cyr

echo "axis 3 — undefined fns stay EXPECTED (a bundle ships no stdlib) and do not fail:"
# Reference a stdlib symbol the bundle deliberately does not carry.
printf 'fn a_one(): i64 { return strlen("x"); }\n' > src/a.cyr
timeout 300 "$CY" distlib > "$D/o3" 2>&1
check "exit 0 despite the undefined fn" 0 "$?"
check "bundle still written" 1 "$([ -f dist/bp.cyr ] && echo 1 || echo 0)"
printf 'fn a_one(): i64 { return 1; }\n' > src/a.cyr

echo "axis 4 — the check leaves no temp entry behind, on success OR failure:"
timeout 300 "$CY" distlib > /dev/null 2>&1
check "no distchk entry after success" 0 "$(ls -a dist/ | grep -c 'distchk' || true)"
printf 'fn a_one(): i64 { return 1; }\nfn broken2( {\n' > src/a.cyr
timeout 300 "$CY" distlib > /dev/null 2>&1
check "no distchk entry after failure" 0 "$(ls -a dist/ | grep -c 'distchk' || true)"
printf 'fn a_one(): i64 { return 1; }\n' > src/a.cyr

echo "axis 5 — a bundle over cycc's 1 MB stdin cap is still checked (the sigil case):"
# Past input_buf (1,048,576) with headroom, split across TWO modules — which is both the
# real sigil shape (many modules summing past 1 MB) and a necessity: distlib enforces its
# own 1024 KB PER-MODULE read cap, so a single 1.2 MB module fails there (loudly, exit 1)
# and never reaches the self-check this axis is about. ~87 B/line, 8000 lines/module
# ~= 700 KB each ~= 1.4 MB bundled.
# ⚠ A first attempt used 12000 lines in one module and came to 1,045,977 B — 2,599 B UNDER
# the cap, so the axis proved nothing. The explicit >1 MB assertion below is what caught
# that; do not drop it and trust the line count.
i=0
: > src/big1.cyr
: > src/big2.cyr
while [ "$i" -lt 8000 ]; do
    printf 'fn big1_%d(): i64 { return %d; }  # padding padding padding padding padding padding\n' "$i" "$i" >> src/big1.cyr
    printf 'fn big2_%d(): i64 { return %d; }  # padding padding padding padding padding padding\n' "$i" "$i" >> src/big2.cyr
    i=$((i + 1))
done
printf '[package]\nname = "bp"\nversion = "0.1.0"\n\n[lib]\nmodules = ["src/a.cyr", "src/big1.cyr", "src/big2.cyr"]\n' > cyrius.cyml
timeout 600 "$CY" distlib > "$D/o5" 2>&1
check "exit 0 on a >1 MB bundle" 0 "$?"
check "bundle really is over 1 MB" 1 "$([ "$(wc -c < dist/bp.cyr)" -gt 1048576 ] && echo 1 || echo 0)"
check "no '1MB buffer' error" 0 "$(grep -c '1MB buffer' "$D/o5" || true)"
# ...and it is genuinely CHECKED at that size, not skipped: break it and expect a failure.
printf 'fn a_one(): i64 { return 1; }\nfn broken3( {\n' > src/a.cyr
timeout 600 "$CY" distlib > "$D/o6" 2>&1
rc6=$?
check "a broken >1 MB bundle still FAILS" 1 "$([ "$rc6" -ne 0 ] && echo 1 || echo 0)"

cd "$ROOT" || exit 2
echo ""
if [ "$fails" = "0" ]; then
    echo "PASS: distlib-bundle-selfcheck — the bundle is really compiled; broken bundles are fatal"
    exit 0
fi
echo "FAIL: distlib-bundle-selfcheck — $fails assertion(s) failed"
exit 1

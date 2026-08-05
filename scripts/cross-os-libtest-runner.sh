#!/bin/sh
# Remote batched lib-test runner (cyrius v6.5.8). Shipped by cross-os-selfhost.sh and run
# in ONE ssh session instead of one per test — the per-test loop it replaces spent ~1.8 s
# (cass) / 0.9 s (pi) of pure SSH handshake per file, which is what made a wider corpus
# look unaffordable when it is actually the connections, not the tests, that cost.
#
# $1 = compile command  $2 = 1 to codesign (macOS)  $3 = glob prefix ("" = whole corpus)
CC_CMD="$1"; DO_SIGN="$2"; PREFIX="$3"
cd ~/_cyaud || exit 2
p=0; f=0; bad=""
for t in tests/tcyr/${PREFIX}*.tcyr; do
    [ -e "$t" ] || continue
    b=$(basename "$t")
    ok=1
    sh -c "cat '$t' | $CC_CMD > _lt 2>/dev/null" || ok=0
    [ -s _lt ] || ok=0
    if [ "$ok" = "1" ]; then
        chmod +x _lt
        [ "$DO_SIGN" = "1" ] && codesign -s - -f _lt >/dev/null 2>&1
        rc=0
        ./_lt >/dev/null 2>&1 || rc=$?
        [ "$rc" -eq 0 ] || ok=0
    fi
    if [ "$ok" = "1" ]; then p=$((p + 1)); else f=$((f + 1)); bad="$bad $b"; fi
done
echo "__LIBTEST_SUMMARY__ $p $f"
[ -n "$bad" ] && echo "__LIBTEST_FAILED__$bad"
exit 0

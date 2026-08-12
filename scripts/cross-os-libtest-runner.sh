#!/bin/sh
# Remote batched lib-test runner (cyrius v6.5.8). Shipped by cross-os-selfhost.sh and run
# in ONE ssh session instead of one per test — the per-test loop it replaces spent ~1.8 s
# (cass) / 0.9 s (pi) of pure SSH handshake per file, which is what made a wider corpus
# look unaffordable when it is actually the connections, not the tests, that cost.
#
# $1 = compile command  $2 = 1 to codesign (macOS)  $3 = subdir under tests/tcyr ("" = whole corpus)
#
# v6.5.11: selection is a SUBDIRECTORY and the walk is RECURSIVE. It was a flat prefix
# glob (`tests/tcyr/${PREFIX}*.tcyr`) whose no-match case was swallowed by the `[ -e ]`
# guard below, so the loop ran ZERO tests and reported "__LIBTEST_SUMMARY__ 0 0" — which
# the caller graded GREEN. The caller now also cross-checks this count against the number
# it selected locally, so the two sides can no longer disagree silently.
CC_CMD="$1"; DO_SIGN="$2"; SUBDIR="$3"
cd ~/_cyaud || exit 2

# ⛔ EVERY TEST RUN IS TIME-BOUNDED (v6.5.19). A test that HANGS on the target used to
# wedge this loop forever: the caller's ssh has no command timeout (ConnectTimeout covers
# setup only), so the whole cross-OS leg produced no summary and no verdict until a human
# killed it. cass already had `timeout 90` around its per-test ssh for exactly this reason
# — the POSIX hosts never got the equivalent, and they are the ones running the batched
# loop where a single hang costs the entire corpus rather than one test.
#
# It matters more now than it did: tests/tcyr/crossos/ carries threading and allocator-lock
# tests as of v6.5.19, and the failure mode of a spinlock is a hang, not a fault. A hang has
# to COUNT AS A FAILURE and let the sweep continue; anything else and the gate reports
# nothing at all about the other 44 files.
#
# ⚠ NEITHER MAC HAS `timeout`. Checked on real ecb and ach: no `timeout`, no `gtimeout`
# (they are GNU coreutils, not part of the macOS base system), and pi has it. So this is
# hand-rolled rather than delegated — poll `kill -0` on a backgrounded child. `sleep 0.1`
# is honoured by BSD and GNU sleep alike; it costs at most one extra tenth of a second per
# test because the loop tests liveness BEFORE it sleeps.
#
# stdin is /dev/null explicitly: a background child's stdin is shell-dependent (some
# shells attach /dev/null when job control is off, some inherit), and the ssh channel is
# not a sane input for a test either way.
LT_TIMEOUT="${CYRIUS_LIBTEST_TIMEOUT:-90}"
run_bounded() {
    "$1" </dev/null >/dev/null 2>&1 &
    _bp=$!
    _bn=0
    _blim=$((LT_TIMEOUT * 10))
    while [ "$_bn" -lt "$_blim" ]; do
        kill -0 "$_bp" 2>/dev/null || break
        sleep 0.1
        _bn=$((_bn + 1))
    done
    if kill -0 "$_bp" 2>/dev/null; then
        kill -9 "$_bp" 2>/dev/null
        wait "$_bp" 2>/dev/null
        return 124
    fi
    wait "$_bp"
    return $?
}
ROOT="tests/tcyr"
[ -n "$SUBDIR" ] && ROOT="tests/tcyr/$SUBDIR"
if [ ! -d "$ROOT" ]; then echo "__LIBTEST_NODIR__ $ROOT"; exit 3; fi
p=0; f=0; hung=0; bad=""
for t in $(find "$ROOT" -name '*.tcyr' | sort); do
    [ -e "$t" ] || continue
    b=${t#tests/tcyr/}
    ok=1
    sh -c "cat '$t' | $CC_CMD > _lt 2>/dev/null" || ok=0
    [ -s _lt ] || ok=0
    if [ "$ok" = "1" ]; then
        chmod +x _lt
        [ "$DO_SIGN" = "1" ] && codesign -s - -f _lt >/dev/null 2>&1
        rc=0
        run_bounded ./_lt || rc=$?
        if [ "$rc" -eq 124 ]; then
            ok=0; hung=$((hung + 1)); b="${b}(HANG@${LT_TIMEOUT}s)"
        elif [ "$rc" -ne 0 ]; then
            ok=0
        fi
    fi
    if [ "$ok" = "1" ]; then p=$((p + 1)); else f=$((f + 1)); bad="$bad $b"; fi
done
[ "$hung" != "0" ] && echo "__LIBTEST_HUNG__ $hung test(s) killed at ${LT_TIMEOUT}s"
echo "__LIBTEST_SUMMARY__ $p $f"
[ -n "$bad" ] && echo "__LIBTEST_FAILED__$bad"
exit 0

#!/bin/sh
# Gate: the check driver's .tcyr phase runs each test with a THROWAWAY $HOME that holds the
# fdlopen helper, so the libssl groups run, and the invoking $HOME is never reached (6.6.17).
#
# THE DEFECT. The phase ran every test with EMPTY_ENVP (`CYRIUS_TEST_ENV=1` and nothing else).
# lib/fdlopen.cyr finds its helper only at $HOME/.cyrius/dlopen-helper, so with no HOME,
# tls_available() under the libssl backend read 0 and the libssl groups of
# tls_libssl_read_errors / _session_cache / _worker_thread SKIPped on every check.sh and
# release-gate run (measured 6 / 27 / 3 assertions there, against 348 / 60 / 83 with the
# helper). The only automated libssl coverage left was tls_libssl_hostname_binding.sh.
#
# ROWS — a staged root (build/cycc + lib symlinked, ONE probe at tests/tcyr/zz/), driven by a
# check driver built from this tree, TMPDIR and HOME pointed into this gate's mktemp dir:
#   staged   CYRIUS_HOME holds a helper (built here from programs/dlopen-helper.c), HOME is
#            empty -> the probe PASSES: it sees a HOME under the driver's private TMPDIR that is
#            not the invoking one, the helper is in it, and the libssl backend initialises
#   home     no CYRIUS_HOME, the helper only at the invoking $HOME/.cyrius -> PASS, and the
#            invoking HOME is left byte- and mtime-identical
#   none     no helper anywhere -> the probe FAILS on tls_available() (so it discriminates),
#            and the driver says the libssl groups SKIP
#   every run leaves the driver's TMPDIR empty (the throwaway HOME went with the run's dir)
# MUTATION (measured by hand, not run here): the driver with `_exec_capture_envp(..,
# _tcyr_envp())` put back to `_exec_capture_clean(..)` fails rows staged and home.
#
# SKIP (exit 77, named): no compiler, no C compiler for the helper, or no libssl.so.3.
# CHANGELOG [6.6.17]
set -u

NAME=check_tcyr_home_has_helper
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$ROOT" || { echo "FAIL: $NAME — cannot cd to $ROOT"; exit 1; }
CC=${CYCC:-"$ROOT/build/cycc"}
[ -x "$CC" ] || { echo "SKIP: $NAME — no compiler at $CC"; exit 77; }
case "$(uname -s)/$(uname -m)" in
    Linux/x86_64) ;;
    *) echo "SKIP: $NAME — the libssl backend is an x86_64-Linux fdlopen bridge"; exit 77 ;;
esac
CCC=""
for c in cc gcc; do command -v "$c" >/dev/null 2>&1 && { CCC=$c; break; }; done
[ -n "$CCC" ] || { echo "SKIP: $NAME — no C compiler to build the fdlopen helper"; exit 77; }
found=0
if ldconfig -p 2>/dev/null | grep -q 'libssl\.so\.3 '; then found=1; fi
for d in /usr/lib /usr/lib64 /lib /lib64 /usr/lib/x86_64-linux-gnu /lib/x86_64-linux-gnu /usr/local/lib; do
    [ -e "$d/libssl.so.3" ] && found=1
done
[ "$found" = 1 ] || { echo "SKIP: $NAME — libssl.so.3 not found"; exit 77; }

T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $NAME — mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
ulimit -c 0 2>/dev/null || true
fails=0
check() {
    if [ "$2" = "$3" ]; then echo "  ok: $1"
    else echo "  FAIL: $1 — expected $2, got $3"; fails=$((fails + 1)); fi
}
strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

( cd "$ROOT" && "$CC" < programs/checks/main.cyr > "$T/drv" 2> "$T/drv.err" ) \
    || { echo "FAIL: $NAME — the check driver does not compile"; sed 's/^/    /' "$T/drv.err"; exit 1; }
chmod +x "$T/drv"
mkdir -p "$T/ch"
"$CCC" -O2 -fPIE -pie -o "$T/ch/dlopen-helper" "$ROOT/programs/dlopen-helper.c" -ldl 2> "$T/cc.err" \
    || { echo "SKIP: $NAME — the fdlopen helper does not build here:"; sed 's/^/    /' "$T/cc.err"; exit 77; }

# ── the staged root and its one probe ──
R="$T/root"
mkdir -p "$R/build" "$R/tests/tcyr/zz" "$T/tmp" "$T/h_empty" "$T/h_none" "$T/h_helper/.cyrius"
ln -s "$CC" "$R/build/cycc"
ln -s "$ROOT/lib" "$R/lib"
echo 1 > "$R/tests/tcyr/CORPUS_FLOOR"
cp "$T/ch/dlopen-helper" "$T/h_helper/.cyrius/dlopen-helper"
# The probe embeds the driver's TMPDIR and both invoking HOMEs, so it can tell them apart from
# the HOME it is handed. Under `none` its helper and libssl asserts fail, which is the point.
cat > "$R/tests/tcyr/zz/home_probe.tcyr" <<EOF
include "lib/assert.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
include "lib/io.cyr"
include "lib/net.cyr"
include "lib/chrono.cyr"
include "lib/thread.cyr"
include "lib/tls.cyr"
alloc_init();
var h = getenv("HOME");
assert(h != 0, "the .tcyr child has a HOME");
if (h != 0) {
    var tmp = "$T/tmp/";
    assert_eq(memeq(h, tmp, strlen(tmp)), 1, "HOME is under the driver's private TMPDIR");
    assert_eq(streq(h, "$T/h_empty"), 0, "HOME is not the invoking HOME (staged row)");
    assert_eq(streq(h, "$T/h_helper"), 0, "HOME is not the invoking HOME (home row)");
    var hp = alloc(strlen(h) + 32);
    memcpy(hp, h, strlen(h));
    memcpy(hp + strlen(h), "/.cyrius/dlopen-helper", 23);
    assert_eq(file_exists(hp), 1, "the helper is in that HOME");
}
tls_set_backend(TLS_BACKEND_LIBSSL);
assert_eq(tls_available(), 1, "the libssl backend initialises in the .tcyr phase");
var r = assert_summary();
syscall(60, r);
EOF

# run_drv <label> <HOME> [CYRIUS_HOME] -> the probe's row (ANSI stripped), output in $T/<label>.out
run_drv() {
    if [ -n "${3:-}" ]; then
        ( cd "$R" && env -i PATH="$PATH" TMPDIR="$T/tmp" HOME="$2" CYRIUS_HOME="$3" \
            CYRIUS_CHECK_TIMEOUT=120 timeout 300 "$T/drv" tcyr ) > "$T/$1.raw" 2>&1
    else
        ( cd "$R" && env -i PATH="$PATH" TMPDIR="$T/tmp" HOME="$2" \
            CYRIUS_CHECK_TIMEOUT=120 timeout 300 "$T/drv" tcyr ) > "$T/$1.raw" 2>&1
    fi
    strip_ansi < "$T/$1.raw" > "$T/$1.out"
    grep -E '^  zz/home_probe ' "$T/$1.out" | sed -E 's/^  zz\/home_probe +//'
}
tmp_empty() { [ -z "$(ls -A "$T/tmp")" ] && echo yes || echo "no: $(ls -A "$T/tmp" | head -3 | tr '\n' ' ')"; }

touch -t 200001010000 "$T/h_helper" "$T/h_helper/.cyrius" "$T/h_helper/.cyrius/dlopen-helper"
touch -t 200101010000 "$T/stamp"

echo "row staged: helper in CYRIUS_HOME, the invoking HOME empty"
check "the probe PASSES" "PASS" "$(run_drv staged "$T/h_empty" "$T/ch")"
check "the driver names the helper it copied" "yes" \
    "$(grep -qF "a copy of $T/ch/dlopen-helper" "$T/staged.out" && echo yes || echo no)"
check "the invoking HOME is still empty" "" "$(ls -A "$T/h_empty")"
check "the driver's TMPDIR is empty after the run" "yes" "$(tmp_empty)"

echo "row home: no CYRIUS_HOME, the helper only at the invoking HOME"
check "the probe PASSES" "PASS" "$(run_drv home "$T/h_helper")"
check "the driver names the invoking HOME's helper" "yes" \
    "$(grep -qF "a copy of $T/h_helper/.cyrius/dlopen-helper" "$T/home.out" && echo yes || echo no)"
check "the invoking HOME is untouched (no file newer than the stamp)" "" "$(find "$T/h_helper" -newer "$T/stamp")"
check "the invoking HOME holds exactly what it held" ".cyrius/dlopen-helper" \
    "$(cd "$T/h_helper" && find . -mindepth 1 -type f | sed 's|^\./||')"
check "the driver's TMPDIR is empty after the run" "yes" "$(tmp_empty)"

echo "row none: no helper anywhere"
check "the probe FAILS (it discriminates)" "FAIL (2 failed)" "$(run_drv none "$T/h_none")"
check "the driver says the libssl groups SKIP" "yes" \
    "$(grep -q 'no dlopen-helper at .* the libssl groups SKIP' "$T/none.out" && echo yes || echo no)"
check "the invoking HOME is still empty" "" "$(ls -A "$T/h_none")"
check "the driver's TMPDIR is empty after the run" "yes" "$(tmp_empty)"

if [ "$fails" -gt 0 ]; then
    echo "FAIL: $NAME: $fails problem(s); driver output:"
    for r in staged home none; do echo "  -- $r"; grep -E 'zz/|helper|SKIP' "$T/$r.out" | head -4 | sed 's/^/     /'; done
    exit 1
fi
echo "PASS: $NAME (the .tcyr phase hands each test a throwaway HOME holding a copy of the helper, from CYRIUS_HOME or the invoking HOME; libssl initialises there; the invoking HOME is never written)"
exit 0

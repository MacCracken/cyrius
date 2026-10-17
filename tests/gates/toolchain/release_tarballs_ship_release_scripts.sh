#!/bin/sh
# Gate: every POSIX release tarball stages cyrius.cyml's [release] scripts through ONE helper (6.7.14).
#
# THE DEFECT. release.yml's "Package aarch64 tarball" step was a hand list (cycc, cyrsign, cyrius,
# cyrius-init, cyriusly) that never read the manifest's `scripts` array, so the aarch64-linux
# tarball shipped no cyrius-repl.sh, cyrius-watch.sh or cyrius-prompt-info, and a binary-installed
# aarch64 Linux box had no `cyrius repl`. The x86_64 step read the array with its own copy of the
# parse and lookup; the macOS builders call scripts/release-scripts.sh (6.7.12, the user's D4: ship
# every entry). Now all four builders call the helper, and none parses or copies the list itself.
#
# AXES (static: the release.yml steps run only on a tag)
#   1  each of the four builders — release.yml's "Package x86_64 tarball" and "Package aarch64
#      tarball" step bodies, scripts/build-macos-x86-tarball.sh, scripts/build-macos-arm64-tarball.sh —
#      runs `sh scripts/release-scripts.sh "<stage>/bin"` exactly once in code (comment lines
#      dropped), before its first compile when it compiles anything.
#   2  no builder parses the `scripts` array itself (`k="scripts"`) or names a [release] scripts
#      entry in code: a hand list is how the aarch64 step shipped none.
#   Anti-vacuous: both release.yml steps are found (each >= 10 code lines, ending in its `tar czf`),
#   the entry list has >= 3 names with cyrius-repl.sh among them, and the compile-line reader finds
#   the aarch64 step's and both macOS builders' compiles.
# The helper itself (lookup order, refusals) is tests/gates/toolchain/macos_tarball_ships_release_scripts.sh
# axes 2-3; the x86_64 step's tarball is installed and its `cyrius repl` run by
# ci_installs_the_release_tarball.sh axis 8; the aarch64 step is RUN by aarch64_tarball_ships_release_bins.sh.
#
# MUTATION LEDGER (measured 6.7.14, each on a copy of release.yml / the builder):
#   a. the 6.7.13 release.yml verbatim            -> RED: axis 1 (both Linux steps: 0 helper calls),
#                                                    axis 2 (the x86_64 step parses k="scripts")
#   b. only the aarch64 step's helper call dropped -> RED: axis 1 (aarch64, 0 calls)
#   c. the aarch64 call moved after its first      -> RED: axis 1 (order)
#      compile
#   d. a hand `cp scripts/cyrius-watch.sh` added   -> RED: axis 2 (names an entry)
#      to the aarch64 step
set -u
NAME=release_tarballs_ship_release_scripts
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
WF="$ROOT/.github/workflows/release.yml"
cd "$ROOT"
T=$(mktemp -d) && [ -d "$T" ] || { echo "FAIL: $NAME: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$T"' EXIT
FAIL=0
bad() { echo "  FAIL: $1"; FAIL=1; }

# The [release] scripts entries, parsed with sed/grep (not the helper's awk).
EXPECT=$(sed -n '/^\[release\]/,/^\[/p' cyrius.cyml | grep -E '^scripts[[:space:]]*=' | grep -oE '"[^"]+"' | tr -d '"' | tr '\n' ' ' | sed 's/ $//' || true)
n=0; for s in $EXPECT; do n=$((n + 1)); done
[ "$n" -ge 3 ] || { echo "FAIL: $NAME: read $n [release] scripts entries (floor 3): the parse is blind"; exit 1; }
case " $EXPECT " in *" cyrius-repl.sh "*) ;; *) echo "FAIL: $NAME: cyrius-repl.sh is not in [release] scripts ($EXPECT)"; exit 1 ;; esac

# step_body <step name> <out>: a release.yml step's `run: |` body, dedented (ci_installs_the_release_tarball.sh's reader).
step_body() {
    awk -v want="$1" '
        { line = $0; sub(/^ *- name: /, "", line) }
        $0 ~ /^ *- name: / && line == want { f = 1; next }
        f == 1 && $0 ~ /^ *run: \|/ { f = 2; next }
        f == 1 && $0 ~ /^ *- / { exit }
        f == 2 {
            if ($0 ~ /^[[:space:]]*$/) { print ""; next }
            match($0, /^ */); ind = RLENGTH
            if (base == "") base = ind
            if (ind < base) exit
            print substr($0, base + 1)
        }' "$WF" > "$2"
}
step_body "Package x86_64 tarball" "$T/x86_64-linux.sh"
step_body "Package aarch64 tarball" "$T/aarch64-linux.sh"
for k in x86_64-linux aarch64-linux; do
    nl=$(sed 's/^[[:space:]]*#.*$//' "$T/$k.sh" | grep -c . || true)
    { [ "$nl" -ge 10 ] && grep -qF 'tar czf "${STAGE}.tar.gz" "$STAGE"' "$T/$k.sh"; } \
        || { echo "FAIL: $NAME: could not read release.yml's $k package step ($nl code lines); update this gate's reader"; exit 1; }
done
cp scripts/build-macos-x86-tarball.sh "$T/x86_64-macos.sh"
cp scripts/build-macos-arm64-tarball.sh "$T/aarch64-macos.sh"

# ── axes 1 and 2 ───────────────────────────────────────────────────────────────────────────
ncomp=0
for k in x86_64-linux aarch64-linux x86_64-macos aarch64-macos; do
    code=$(sed 's/^[[:space:]]*#.*$//' "$T/$k.sh")
    nh=$(printf '%s\n' "$code" | grep -cE '^[[:space:]]*sh scripts/release-scripts\.sh "\$[A-Z_]+(/\$STAGE)?/bin"$' || true)
    hall=$(printf '%s\n' "$code" | grep -c 'release-scripts\.sh' || true)
    lh=$(printf '%s\n' "$code" | grep -n 'sh scripts/release-scripts\.sh ' | head -1 | cut -d: -f1 || true)
    lc=$(printf '%s\n' "$code" | grep -nE '\| *([A-Z_]+=[^ ]+ +)*(\./build/cycc[a-z_0-9]*|"\$WORK/cc_[lx]")( |$)' | head -1 | cut -d: -f1 || true)
    a1=0
    if [ "$nh" != 1 ] || [ "$hall" != 1 ]; then bad "axis 1: $k: runs sh scripts/release-scripts.sh \"<stage>/bin\" $nh time(s) in code, release-scripts.sh named $hall time(s) (want 1 and 1)"; a1=1
    elif [ -n "$lc" ] && [ "$lh" -gt "$lc" ]; then bad "axis 1: $k: stages the scripts at code line $lh, after its first compile at line $lc"; a1=1
    fi
    [ -n "$lc" ] && ncomp=$((ncomp + 1))
    [ "$a1" = 0 ] && echo "  ok axis 1: $k stages [release] scripts through scripts/release-scripts.sh$( [ -n "$lc" ] && echo ", before its first compile")"
    a2=0
    if printf '%s\n' "$code" | grep -q 'k="scripts"'; then bad "axis 2: $k parses the [release] scripts array itself"; a2=1; fi
    for s in $EXPECT; do
        h=$(printf '%s\n' "$code" | grep -nF "$s" | head -1 || true)
        [ -z "$h" ] || { bad "axis 2: $k names [release] scripts entry $s itself (code line ${h%%:*})"; a2=1; }
    done
    [ "$a2" = 0 ] && echo "  ok axis 2: $k neither parses nor hand-copies the [release] scripts list"
done
# Anti-vacuous: the order check read the compiles of the three builders that compile.
[ "$ncomp" -ge 3 ] || bad "the compile-line reader found compiles in $ncomp builder(s) (want the aarch64 step and both macOS builders): the order check read nothing"

if [ "$FAIL" != 0 ]; then echo "FAIL: $NAME"; exit 1; fi
echo "PASS: $NAME (all 4 POSIX tarball builders stage the $n [release] scripts ($EXPECT) through scripts/release-scripts.sh, and none parses or hand-copies the list)"

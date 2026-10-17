#!/bin/sh
# Gate: the aarch64-linux release tarball ships every cyrius.cyml [release] bin, built for aarch64
# (6.7.14, the user's D59).
#
# THE DEFECT. release.yml's "Package aarch64 tarball" step shipped a hand list: cycc, cyrsign,
# cyrius-init and scripts/cyriusly (the SHELL script) as bin/cyriusly, and copied build/cyrius only
# `if [ -f ]` — a file the build-aarch64 job never builds, so that copy always skipped. A binary
# install on aarch64 Linux had no `cyrius` CLI (no build, test or repl), no cyrfmt, cyrlint, cyrdoc,
# cyrius-lsp or the rest, and none of the [release] scripts. The step now builds every [release]
# bins entry for aarch64 (cybs excepted: the x86_64 assembly the seed assembles, with no aarch64
# form), arch-checks each, and stages the [release] scripts through scripts/release-scripts.sh.
#
# THE STEP IS release.yml's: its `run:` body is read out of the workflow and run under
# `bash -eo pipefail` (GitHub's `run:` shell) in a scratch checkout holding what it reads, with
# GITHUB_REF_NAME = VERSION. build/cycc_aarch64 there is the NATIVE aarch64 compiler, built as the
# job's "Build native aarch64 compiler" step builds it (the tree's cycc -> the cross compiler ->
# src/main_aarch64.cyr), and is what the step copies to bin/cycc. The runner RUNS that aarch64 ELF
# for each compile through qemu-user's binfmt registration; this host may have none, so the step's
# compile pipes (`| ./build/cycc_aarch64 >`) are pointed at the x86-hosted cross compiler built from
# the same src/main_aarch64.cyr, which writes the same bytes (measured 6.7.14 on cbt/cyrius.cyr:
# qemu + native == cross). The rewrite is counted, so a step whose compiles moved elsewhere fails.
#
# AXES
#   1  the step exits 0 and writes dist/cyrius-<v>-aarch64-linux.tar.gz (+ .sha256), every entry
#      under that one top-level directory.
#   2  its bin/ holds exactly every [release] bin but cybs and every [release] script (the lists
#      parsed here with sed/grep, not the step's awk; floors: 15 bins, 3 scripts): each bin an
#      executable ELF whose e_machine is AArch64 (read from the bytes, not `file`), bin/cycc
#      byte-identical to the native compiler, each script byte-identical to its source
#      (scripts/shims/ first); scripts/cyriusly is the tree's shell twin.
#   3  a manifest listing a bin with no source fails the step, naming it, with no tarball.
#   4  (qemu-aarch64) the packaged aarch64 tools run: bin/cycc compiles `var x = 42;` to a program
#      exiting 42, bin/cyrius answers `version` with VERSION, bin/cyriusly names the active slot, and
#      bin/cyrfmt prints a file formatted. Without qemu-aarch64 the axis says so by name and the gate exits 77.
#   Real hardware: pi ran an install of this tarball by hand (6.7.14: recorded in the CHANGELOG).
#
# MUTATION LEDGER (measured 6.7.14: this gate run from a scratch root carrying a mutated release.yml)
#   a. the 6.7.13 aarch64 step verbatim          -> RED: axis 2 (cyrius, cyrfmt, ... and the three
#                                                   scripts missing; cyriusly not an ELF)
#   b. the bins half reverted (scripts staged,    -> RED: axis 2 (13 bins missing, cyriusly not an
#      the hand list kept)                           ELF)
#   c. `cybs) continue ;` dropped                  -> RED: axis 1 (the step fails: no programs/cybs.cyr)
#   d. the `cyrius)` arm compiled with ./build/cycc -> RED: axis 1 (the step's own arch check names
#      (the x86_64 compiler)                           cyrius)
#   e. d with the step's arch check made vacuous    -> RED: axis 2 (bin/cyrius is an x86-64 ELF)
#   f. programs/cyrld.cyr's raw SYS_OPEN restored  -> RED: axis 1 (cyrld does not compile for
#                                                     aarch64: its peer has no SYS_OPEN)
set -u
NAME=aarch64_tarball_ships_release_bins
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
CC=${CYCC:-"$ROOT/build/cycc"}
WF="$ROOT/.github/workflows/release.yml"

for t in tar gzip sha256sum bash awk cmp od file; do
    command -v "$t" > /dev/null 2>&1 || { echo "SKIP: $NAME — no $t on this host"; exit 77; }
done
[ -x "$CC" ] || { echo "FAIL: $NAME — $CC missing"; exit 1; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $NAME: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
FAIL=0
bad() { echo "  FAIL $1"; FAIL=1; }
outtail() { sed 's/\x1b\[[0-9;]*m//g' "$1" | tail -4 | LC_ALL=C tr -c '[:print:]\n' '?' | tr '\n' '|'; }

V=$(tr -d '[:space:]' < "$ROOT/VERSION")
[ -n "$V" ] || { echo "FAIL: $NAME — empty VERSION"; exit 1; }
STAGE="cyrius-$V-aarch64-linux"
TB="$STAGE.tar.gz"

# ── the package step, read out of release.yml ──
awk '
    $0 ~ /^ *- name: Package aarch64 tarball *$/ { f = 1; next }
    f == 1 && $0 ~ /^ *run: \|/ { f = 2; next }
    f == 1 && $0 ~ /^ *- / { exit }
    f == 2 {
        if ($0 ~ /^[[:space:]]*$/) { print ""; next }
        match($0, /^ */); ind = RLENGTH
        if (base == "") base = ind
        if (ind < base) exit
        print substr($0, base + 1)
    }' "$WF" > "$W/step.sh"
NL=$(grep -c . "$W/step.sh" || true)
{ [ "$NL" -ge 10 ] && grep -qF 'tar czf "${STAGE}.tar.gz" "$STAGE"' "$W/step.sh" && grep -qF 'STAGE="cyrius-${VER}-aarch64-linux"' "$W/step.sh"; } \
    || { echo "FAIL: $NAME — could not read the 'Package aarch64 tarball' step out of release.yml ($NL lines); update this gate's reader"; exit 1; }
# Its compiles run the cross compiler (see the header); count them before and after.
NPIPE=$(grep -c '| \./build/cycc_aarch64 >' "$W/step.sh" || true)
sed 's#| \./build/cycc_aarch64 >#| ./build/cycc_aarch64_cross >#g' "$W/step.sh" > "$W/package.sh"
NLEFT=$(grep -c '| \./build/cycc_aarch64 >' "$W/package.sh" || true)
{ [ "$NPIPE" -ge 1 ] && [ "$NLEFT" = 0 ]; } \
    || { echo "FAIL: $NAME — the step's compile pipes: $NPIPE \`| ./build/cycc_aarch64 >\` found (want >= 1), $NLEFT left after the rewrite; update this gate's reader"; exit 1; }

# ── the manifest's lists, read here with sed/grep ──
_rel() { sed -n '/^\[release\]/,/^\[/p' "$1" | grep -E "^$2[[:space:]]*=" | grep -oE '"[^"]+"' | tr -d '"' | tr '\n' ' ' | sed 's/ $//' || true; }
BINS=$(_rel "$ROOT/cyrius.cyml" bins)
SCRIPTS=$(_rel "$ROOT/cyrius.cyml" scripts)
NBALL=$(echo $BINS | wc -w); NS=$(echo $SCRIPTS | wc -w)
EXPB=""; for b in $BINS; do [ "$b" = cybs ] || EXPB="$EXPB $b"; done
NB=$(echo $EXPB | wc -w)
{ [ "$NB" -ge 15 ] && [ "$NS" -ge 3 ]; } || { echo "FAIL: $NAME — read $NB aarch64 bins of $NBALL and $NS scripts from cyrius.cyml (floors 15 / 3): the reader is blind"; exit 1; }

# ── a scratch checkout holding what the step reads, and the two aarch64 compilers ──
CO="$W/co"
mkdir -p "$CO/build"
cp "$ROOT/cyrius.cyml" "$ROOT/VERSION" "$ROOT/LICENSE" "$CO/"
cp "$CC" "$CO/build/cycc"   # tracked, so every checkout has the x86_64 compiler too
for d in scripts lib programs cbt src; do cp -R "$ROOT/$d" "$CO/$d"; done
( cd "$ROOT" && "$CC" < src/main_aarch64.cyr > "$CO/build/cycc_aarch64_cross" 2> "$W/x.err" ) && [ -s "$CO/build/cycc_aarch64_cross" ] \
    || { echo "FAIL: $NAME — src/main_aarch64.cyr does not build: $(grep -m1 error "$W/x.err")"; exit 1; }
chmod 755 "$CO/build/cycc_aarch64_cross"
( cd "$ROOT" && "$CO/build/cycc_aarch64_cross" < src/main_aarch64.cyr > "$CO/build/cycc_aarch64" 2> "$W/n.err" ) && [ -s "$CO/build/cycc_aarch64" ] \
    || { echo "FAIL: $NAME — the cross compiler does not build the native aarch64 compiler: $(grep -m1 error "$W/n.err")"; exit 1; }
chmod 755 "$CO/build/cycc_aarch64"

# run_step <checkout>: the step under GitHub's run shell, in a clean environment.
run_step() {
    mkdir -p "$W/bhome" "$W/btmp"
    RC=0
    ( cd "$1" && env -i PATH="/usr/bin:/bin" HOME="$W/bhome" TMPDIR="$W/btmp" GITHUB_REF_NAME="$V" \
        bash -eo pipefail "$W/package.sh" ) > "$W/out" 2>&1 || RC=$?
}
# is_a64 <file>: an ELF whose e_machine (bytes 18-19) is 0xB7 (AArch64).
is_a64() { [ "$(od -An -tx1 -N4 "$1" | tr -d ' \n')" = 7f454c46 ] && [ "$(od -An -tx1 -j18 -N2 "$1" | tr -d ' \n')" = b700 ]; }
src_of() { if [ -f "$ROOT/scripts/shims/$1" ]; then echo "$ROOT/scripts/shims/$1"; else echo "$ROOT/scripts/$1"; fi; }

# ── axis 1 ──
run_step "$CO"
if [ "$RC" -ne 0 ] || [ ! -f "$CO/dist/$TB" ] || [ ! -f "$CO/dist/$TB.sha256" ]; then
    bad "axis 1: release.yml's aarch64 package step exit $RC; dist/$TB $( [ -f "$CO/dist/$TB" ] && echo present || echo MISSING): $(outtail "$W/out")"
    echo "FAIL: $NAME"; exit 1
fi
TOPS=$(tar tzf "$CO/dist/$TB" | sed 's|^\./||; s|/.*||' | LC_ALL=C sort -u | tr '\n' ' ')
mkdir -p "$W/x"
tar xzf "$CO/dist/$TB" -C "$W/x" || { echo "FAIL: $NAME — cannot unpack the built tarball"; exit 1; }
X="$W/x/$STAGE"
if [ "$TOPS" = "$STAGE " ]; then echo "  ok axis 1: the aarch64 package step built $TB — one top-level directory"
else bad "axis 1: the tarball's top-level entries are '$TOPS', not the one directory $STAGE"; fi

# ── axis 2 ──
a2=0
for b in $EXPB; do
    f="$X/bin/$b"
    if [ ! -f "$f" ]; then bad "axis 2: bin/$b is MISSING"; a2=1; continue; fi
    [ -x "$f" ] || { bad "axis 2: bin/$b is not executable"; a2=1; }
    is_a64 "$f" || { bad "axis 2: bin/$b is not an AArch64 ELF ($(file -b "$f" | cut -c1-48))"; a2=1; }
done
cmp -s "$X/bin/cycc" "$CO/build/cycc_aarch64" || { bad "axis 2: bin/cycc is not the native aarch64 compiler"; a2=1; }
for s in $SCRIPTS; do
    f="$X/bin/$s"
    { [ -x "$f" ] && cmp -s "$f" "$(src_of "$s")"; } \
        || { bad "axis 2: [release] script $s $( [ -e "$f" ] && echo "is not an executable copy of $(src_of "$s")" || echo "is MISSING from bin/")"; a2=1; }
done
extra=$(ls -A "$X/bin" | while read -r f; do case " $EXPB $SCRIPTS " in *" $f "*) ;; *) printf '%s ' "$f" ;; esac; done)
[ -z "$extra" ] || { bad "axis 2: bin/ holds what the manifest does not list: $extra"; a2=1; }
cmp -s "$X/scripts/cyriusly" "$ROOT/scripts/cyriusly" || { bad "axis 2: scripts/cyriusly is not the tree's shell twin"; a2=1; }
[ "$a2" -eq 0 ] && echo "  ok axis 2: bin/ holds exactly the $NB [release] bins but cybs (each an AArch64 ELF, cycc the native compiler) and the $NS [release] scripts; scripts/cyriusly is the shell twin"

# ── axis 3: a listed bin with no source fails the step by name ──
CO3="$W/co3"
mkdir -p "$CO3"
cp -R "$CO/." "$CO3/"
rm -rf "$CO3/dist" "$CO3/$STAGE"
sed 's/^bins = \[/bins = ["zz_nope_bin", /' "$ROOT/cyrius.cyml" > "$CO3/cyrius.cyml"
grep -q '^bins = \["zz_nope_bin", ' "$CO3/cyrius.cyml" || { echo "FAIL: $NAME — the fake-bin manifest was not made (no '^bins = [' line?)"; exit 1; }
run_step "$CO3"
if [ "$RC" -ne 0 ] && grep -q 'zz_nope_bin' "$W/out" && [ ! -e "$CO3/dist/$TB" ]; then
    echo "  ok axis 3: a listed bin with no source fails the step by name (exit $RC), no tarball"
else
    bad "axis 3: a listed bin with no source: the step exit $RC, $( grep -q 'zz_nope_bin' "$W/out" && echo named || echo 'NOT named'), tarball $( [ -e "$CO3/dist/$TB" ] && echo BUILT || echo absent)"
fi

# ── axis 4: the packaged tools run (qemu-aarch64) ──
a4skip=""
if ! command -v qemu-aarch64 > /dev/null 2>&1; then
    a4skip="no qemu-aarch64"
    echo "  SKIP axis 4: no qemu-aarch64 on PATH, so the packaged aarch64 tools cannot run here"
elif [ "$a2" -eq 0 ]; then
    R="$W/run"; mkdir -p "$R/h/.cyrius" "$R/tmp"
    echo "$V" > "$R/h/.cyrius/current"   # cyriusly's `version` names the active slot
    q() { ( cd "$R" && env HOME="$R/h" CYRIUS_HOME="$R/h/.cyrius" TMPDIR="$R/tmp" qemu-aarch64 "$@" ); }
    a4=0
    echo 'var x = 42;' > "$R/p.cyr"
    rc=0; q "$X/bin/cycc" < "$R/p.cyr" > "$R/p" 2> /dev/null || rc=$?
    chmod +x "$R/p"; prc=0; q "$R/p" || prc=$?
    { [ "$rc" = 0 ] && [ "$prc" = 42 ]; } || { bad "axis 4: bin/cycc: compile rc $rc, the program exit $prc (want 0 / 42)"; a4=1; }
    o=$(q "$X/bin/cyrius" version 2>&1 || true)
    echo "$o" | grep -q "^cyrius $V\$" || { bad "axis 4: bin/cyrius version said: $(echo "$o" | head -2 | tr '\n' '|')"; a4=1; }
    o=$(q "$X/bin/cyriusly" version 2>&1 || true)
    echo "$o" | grep -q "^cyriusly $V\$" || { bad "axis 4: bin/cyriusly version said: $(echo "$o" | head -2 | tr '\n' '|')"; a4=1; }
    printf 'fn f(){\nreturn 1;\n}\n' > "$R/f.cyr"
    o=$(q "$X/bin/cyrfmt" "$R/f.cyr" 2>&1 || true)
    echo "$o" | grep -q '^    return 1;$' || { bad "axis 4: bin/cyrfmt did not indent a body: $(echo "$o" | head -3 | tr '\n' '|')"; a4=1; }
    [ "$a4" -eq 0 ] && echo "  ok axis 4: under qemu-aarch64 the packaged cycc builds a program exiting 42, and cyrius, cyriusly and cyrfmt run"
else
    a4skip="axis 2 failed"
    echo "  SKIP axis 4: axis 2 failed, so there is no complete bin/ to run"
fi

if [ "$FAIL" != 0 ]; then echo "FAIL: $NAME"; exit 1; fi
if [ -n "$a4skip" ]; then echo "SKIP: $NAME (axes 1-3 green; axis 4 could not run: $a4skip)"; exit 77; fi
echo "PASS: $NAME (release.yml's aarch64 step ships the $NB [release] bins but cybs, each built for aarch64, and the $NS [release] scripts; a bin with no source fails it by name; the packaged tools run under qemu-aarch64)"

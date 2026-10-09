#!/bin/sh
# ci_installs_the_release_tarball.sh — 6.7.7. scripts/ci.sh installs the x86_64-linux tarball
# release.yml ACTUALLY publishes, and the gate builds that tarball with release.yml's own package
# step instead of a layout written by hand.
#
# ⛔ THE DEFECT. release.yml's "Package x86_64 tarball" step packs ONE top-level directory,
# `tar czf "${STAGE}.tar.gz" "$STAGE"` with STAGE=cyrius-<v>-x86_64-linux (bin/, lib/,
# programs/cyrius-init-templates/, scripts/cyriusly, VERSION, LICENSE, install.sh). ci.sh untarred
# that straight into $CYRIUS_HOME and then linked $CYRIUS_HOME/versions/<v>/bin/* — a layout no
# release has ever had — so every real install left the tree at $CYRIUS_HOME/cyrius-<v>-x86_64-linux/,
# linked nothing and failed "cycc not found". It read green because the two gates that ran ci.sh
# (release_verify_private_temp.sh, install_signature_required.sh) fed it a FABRICATED tarball in
# the versions/<v>/ shape the script expected: a check that shares a defect with what it checks.
#
# ⭐ THE TARBALL HERE IS release.yml's. The step's `run:` body is read out of the workflow and run
# under `bash -e` (GitHub's default `run:` shell) in a scratch checkout holding what it reads — the
# tree's cyrius.cyml, VERSION, LICENSE, scripts/, lib/, bootstrap/asm, the init templates, and a
# build/ with every [release] bin and cross-bin (the tracked build/cycc real, so the installed
# compiler can be RUN; the rest stubs). A change to the packaging is a change to what this gate
# installs. A stub curl serves the step's dist/ as the release host; no network, throwaway HOME /
# CYRIUS_HOME / TMPDIR, never the live store.
#
# AXES
#   1  ANTI-VACUOUS: the package step was found in release.yml, ran green, and produced
#      dist/cyrius-<v>-x86_64-linux.tar.gz (+ .sha256) whose every entry sits under that one
#      top-level directory.
#   2  ci.sh installs it, under `sh` and under `bash -eo pipefail`: exit 0, "cycc:  ok"; every
#      file of the tarball's bin/ lands byte-identical in versions/<v>/bin and resolves through
#      $CYRIUS_HOME/bin; versions/<v>/lib is the tarball's stdlib (syscalls.cyr present — what the
#      CLI's pinned-stdlib probe checks); versions/<v>/programs/cyrius-init-templates and
#      versions/<v>/scripts/cyriusly are the tree's; versions/<v>/VERSION and current name <v>;
#      nothing is left at $CYRIUS_HOME/cyrius-<v>-x86_64-linux and nothing in TMPDIR.
#   3  the INSTALLED cycc (through $CYRIUS_HOME/bin) compiles `var x = 42;` to a program that
#      exits 42 (x86_64 Linux hosts).
#   4  a tarball that is not release-shaped is REFUSED by name — non-zero, no cycc linked, no
#      `current`: the fabricated versions/<v>/ layout the old gates built, and a
#      cyrius-<v>-x86_64-linux/ with bin/ but no lib/ (install.sh refuses that one too).
#   5  over a home install.sh made — $CYRIUS_HOME/bin and lib DIRECTORY links into versions/<old>
#      (`_switch_active`) — under `sh` and `bash -eo pipefail`: exit 0; versions/<old> keeps exactly
#      its entries, each a regular file byte-identical to before (never a link into the new slot);
#      every tarball bin resolves through $CYRIUS_HOME/bin and $CYRIUS_HOME/lib is the new stdlib.
#
# MUTATION LEDGER (6.7.7, measured: this gate run from a scratch root carrying a mutated copy)
#   a. the 6.7.6 ci.sh verbatim                 -> axis 2 RED in both shells (exit 1, "cycc not
#                                                  found"), both axis-4 rows RED (the fabricated
#                                                  tarball INSTALLS, exit 0); axis 3 needs axis 2;
#                                                  axis 5 RED (exit 0, the OLD binaries and stdlib
#                                                  still active, current = <v>)
#   b. a half fix: still extracted into the home,  -> axis 2 RED (no versions/<v>/bin, lib,
#      linking $CYRIUS_HOME/cyrius-<v>-…/bin/*        templates, twin or VERSION; the tree left
#                                                  in the home), axis 4 RED (no-lib installs)
#   c. the templates copy dropped               -> axis 2 RED (both shells)
#   d. the shell-twin copy dropped              -> axis 2 RED (both shells)
#   e. the release-shape check dropped          -> axis 4 RED (both rows: refused, but by a cp
#                                                  error that names nothing)
#   f. only its `lib` half dropped              -> axis 4 RED (the no-lib row)
#   g. the stdlib copy dropped                  -> axis 2 RED (both shells)
#   h. release.yml's x86_64 STAGE renamed       -> RED before any install: the tarball is no
#                                                  longer the cyrius-<v>-x86_64-linux ci.sh fetches
#   i. the per-file `ln -sf` loop for every     -> axis 5 RED in both shells: every bin of the
#      home (the first cut of this fix)            tarball written into versions/<old>/bin, its cycc
#                                                  and cyrius now LINKS into versions/<v>; lib still
#                                                  the old slot's; axes 1-4 green
#   j. the lib re-point dropped                 -> axis 5 RED (lib still the old slot's stdlib)
#   k. `ln -sf` (no -n) for the bin link        -> axis 5 RED (versions/<old>/bin/bin appears; the
#                                                  old binaries still active)
# The tree -> PASS.
set -u
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
NAME=ci_installs_the_release_tarball
CC=${CYCC:-"$ROOT/build/cycc"}
WF="$ROOT/.github/workflows/release.yml"

for t in tar gzip sha256sum bash awk diff cmp; do
    command -v "$t" > /dev/null 2>&1 || { echo "SKIP: $NAME — no $t on this host"; exit 77; }
done
[ -x "$CC" ] || { echo "SKIP: $NAME — $CC missing"; exit 77; }
W=$(mktemp -d) && [ -d "$W" ] || { echo "FAIL: $NAME: mktemp -d failed (TMPDIR=${TMPDIR:-/tmp})"; exit 1; }
trap 'rm -rf "$W"' EXIT
fail=0
bad() { echo "  FAIL $1"; [ -f "$W/out" ] && sed 's/\x1b\[[0-9;]*m//g' "$W/out" | tail -4 | LC_ALL=C tr -c '[:print:]\n' '?' | sed 's/^/    /'; fail=1; }

V=$(tr -d '[:space:]' < "$ROOT/VERSION")
[ -n "$V" ] || { echo "FAIL: $NAME — empty VERSION"; exit 1; }
STAGE="cyrius-$V-x86_64-linux"
TB="$STAGE.tar.gz"

# ── the package step, read out of release.yml ──
awk '
    $0 ~ /^ *- name: Package x86_64 tarball *$/ { f = 1; next }
    f == 1 && $0 ~ /^ *run: \|/ { f = 2; next }
    f == 1 && $0 ~ /^ *- / { exit }
    f == 2 {
        if ($0 ~ /^[[:space:]]*$/) { print ""; next }
        match($0, /^ */); ind = RLENGTH
        if (base == "") base = ind
        if (ind < base) exit
        print substr($0, base + 1)
    }' "$WF" > "$W/package.sh"
a1=0
NL=$(grep -c . "$W/package.sh" || true)
{ [ "$NL" -ge 10 ] && grep -qF 'tar czf "${STAGE}.tar.gz" "$STAGE"' "$W/package.sh"; } \
    || { echo "FAIL: $NAME — could not read the 'Package x86_64 tarball' step out of release.yml ($NL lines); update this gate's reader"; exit 1; }
# the tarball name the step packs is the one ci.sh fetches (TARBALL="cyrius-${VERSION}-x86_64-linux.tar.gz")
grep -qF 'STAGE="cyrius-${VER}-x86_64-linux"' "$W/package.sh" \
    || { echo "FAIL: $NAME — release.yml's x86_64 package step no longer packs cyrius-\${VER}-x86_64-linux, the tarball scripts/ci.sh fetches: $(grep -m1 '^STAGE=' "$W/package.sh")"; exit 1; }
grep -qF 'TARBALL="cyrius-${VERSION}-x86_64-linux.tar.gz"' "$ROOT/scripts/ci.sh" \
    || { echo "FAIL: $NAME — scripts/ci.sh no longer fetches cyrius-\${VERSION}-x86_64-linux.tar.gz, the tarball release.yml's x86_64 step packs"; exit 1; }

# ── a scratch checkout holding what the step reads ──
CO="$W/co"
mkdir -p "$CO/build" "$CO/bootstrap" "$CO/programs" "$W/stub" "$W/bhome" "$W/btmp"
cp "$ROOT/cyrius.cyml" "$ROOT/VERSION" "$ROOT/LICENSE" "$CO/"
cp -R "$ROOT/scripts" "$CO/scripts"
cp -R "$ROOT/lib" "$CO/lib"
cp -R "$ROOT/programs/cyrius-init-templates" "$CO/programs/"
cp "$ROOT/bootstrap/asm" "$CO/bootstrap/asm"
_rel() {   # _rel <key> — one [release] array of cyrius.cyml (the step's and install.sh's reader)
    awk -v k="$1" '
        /^\[release\]/ { in_r = 1; next }
        in_r && /^\[/ { exit }
        in_r && $1 == k {
            sub(/^[^=]+= \[/, ""); sub(/\].*$/, "")
            gsub(/[",]/, " "); gsub(/ +/, " ")
            sub(/^ +/, ""); sub(/ +$/, ""); print; exit
        }' "$ROOT/cyrius.cyml"
}
NB=0
for b in $(_rel bins) $(_rel cross_bins); do
    printf '#!/bin/sh\necho "stub %s %s"\n' "$b" "$V" > "$CO/build/$b"
    chmod +x "$CO/build/$b"
    NB=$((NB + 1))
done
[ "$NB" -ge 10 ] || { echo "FAIL: $NAME — only $NB [release] bin(s) read from cyrius.cyml; the reader is blind"; exit 1; }
cp "$CC" "$CO/build/cycc"
# the release host (and anything the step might fetch): a stub curl, never the network
cat > "$W/stub/curl" <<EOF
#!/bin/sh
out=""; url=""
while [ \$# -gt 0 ]; do case "\$1" in -o) out=\$2; shift 2 ;; -*) shift ;; *) url=\$1; shift ;; esac; done
case "\$url" in
    */releases/download/$V/*) f="\$RELDIR/\${url##*/}" ;;
    *) exit 22 ;;
esac
[ -f "\$f" ] || exit 22
if [ -n "\$out" ]; then cp "\$f" "\$out"; else cat "\$f"; fi
EOF
chmod +x "$W/stub/curl"

RC=0
( cd "$CO" && env -i PATH="$W/stub:/usr/bin:/bin" HOME="$W/bhome" TMPDIR="$W/btmp" GITHUB_REF_NAME="$V" \
    bash -e "$W/package.sh" ) > "$W/out" 2>&1 || RC=$?
if [ "$RC" -ne 0 ] || [ ! -f "$CO/dist/$TB" ] || [ ! -f "$CO/dist/$TB.sha256" ]; then
    bad "axis 1: release.yml's package step exit $RC; dist/$TB $( [ -f "$CO/dist/$TB" ] && echo present || echo MISSING)"
    echo "FAIL: $NAME"; exit 1
fi
TOPS=$(tar tzf "$CO/dist/$TB" | sed 's|^\./||; s|/.*||' | LC_ALL=C sort -u | tr '\n' ' ')
[ "$TOPS" = "$STAGE " ] || { bad "axis 1: the tarball's top-level entries are '$TOPS', not the one directory $STAGE"; a1=1; }
mkdir -p "$W/expect"
tar xzf "$CO/dist/$TB" -C "$W/expect" || { echo "FAIL: $NAME — cannot unpack the built tarball"; exit 1; }
EXP="$W/expect/$STAGE"
NBIN=$(find "$EXP/bin" -type f | grep -c . || true)
[ "$NBIN" -ge "$NB" ] || { bad "axis 1: the tarball's bin/ holds $NBIN file(s), fewer than the $NB [release] bins staged"; a1=1; }
[ "$a1" -eq 0 ] && echo "  ok axis 1: release.yml's package step built $TB — one top-level directory, $NBIN files in bin/"

# run_ci <home> <shell...> — ci.sh <v> against the stub release host, in a fresh home
# (fresh_home <home> + run_ci_in <home> <shell...> to seed the home in between)
fresh_home() { rm -rf "$1"; mkdir -p "$1/tmp" "$1/cwd"; }
run_ci() { fresh_home "$1"; run_ci_in "$@"; }
run_ci_in() {
    _h=$1; shift
    RC=0
    ( cd "$_h/cwd" && env -i HOME="$_h" CYRIUS_HOME="$_h/.cyrius" PATH="$W/stub:/usr/bin:/bin" TMPDIR="$_h/tmp" \
        RELDIR="$RELDIR" "$@" "$ROOT/scripts/ci.sh" "$V" ) > "$W/out" 2>&1 || RC=$?
}

# ── axis 2 (+3): ci.sh installs the real tarball ──
RELDIR="$CO/dist"
for sh_ in "sh" "bash -eo pipefail"; do
    H="$W/h-${sh_%% *}/.cyrius"
    # shellcheck disable=SC2086  # the shell and its flags are words by construction
    run_ci "$W/h-${sh_%% *}" $sh_
    VD="$H/versions/$V"
    a2=0
    if [ "$RC" -ne 0 ] || ! grep -q 'cycc:  ok' "$W/out"; then
        bad "axis 2 [$sh_]: ci.sh exit $RC"; a2=1
    else
        for f in "$EXP/bin"/*; do
            b=$(basename "$f")
            cmp -s "$f" "$VD/bin/$b" || { bad "axis 2 [$sh_]: versions/$V/bin/$b $( [ -e "$VD/bin/$b" ] && echo 'differs from the tarball' || echo MISSING)"; a2=1; break; }
            cmp -s "$f" "$H/bin/$b" || { bad "axis 2 [$sh_]: \$CYRIUS_HOME/bin/$b does not resolve to the installed $b"; a2=1; break; }
        done
        { [ -f "$VD/lib/syscalls.cyr" ] && diff -r "$EXP/lib" "$VD/lib" > /dev/null 2>&1; } \
            || { bad "axis 2 [$sh_]: versions/$V/lib is not the tarball's stdlib"; a2=1; }
        diff -r "$ROOT/programs/cyrius-init-templates" "$VD/programs/cyrius-init-templates" > /dev/null 2>&1 \
            || { bad "axis 2 [$sh_]: versions/$V/programs/cyrius-init-templates is not the tree's"; a2=1; }
        cmp -s "$ROOT/scripts/cyriusly" "$VD/scripts/cyriusly" \
            || { bad "axis 2 [$sh_]: versions/$V/scripts/cyriusly is not the tree's shell twin"; a2=1; }
        { [ "$(cat "$VD/VERSION" 2>/dev/null)" = "$V" ] && [ "$(cat "$H/current" 2>/dev/null)" = "$V" ]; } \
            || { bad "axis 2 [$sh_]: versions/$V/VERSION or current does not name $V"; a2=1; }
        [ -e "$H/$STAGE" ] && { bad "axis 2 [$sh_]: the tarball's tree was left at \$CYRIUS_HOME/$STAGE"; a2=1; }
        [ -z "$(ls -A "$W/h-${sh_%% *}/tmp" 2>/dev/null)" ] || { bad "axis 2 [$sh_]: ci.sh left files in TMPDIR: $(ls -A "$W/h-${sh_%% *}/tmp" | head -3 | tr '\n' ' ')"; a2=1; }
    fi
    [ "$a2" -eq 0 ] && echo "  ok axis 2 [$sh_]: ci.sh installed the release tarball — bin/ ($NBIN files, linked), lib/, the init templates and the shell twin in versions/$V, current = $V"
    # axis 3: the installed compiler runs
    if [ "$a2" -eq 0 ] && [ "$(uname -s)" = Linux ] && [ "$(uname -m)" = x86_64 ]; then
        RC3=0
        echo 'var x = 42;' | "$H/bin/cycc" > "$W/p42" 2> /dev/null && chmod +x "$W/p42" && "$W/p42" || RC3=$?
        [ "$RC3" -eq 42 ] && echo "  ok axis 3 [$sh_]: the installed cycc compiles var x = 42; to a program exiting 42" \
            || bad "axis 3 [$sh_]: the installed cycc's program exited $RC3, not 42"
        rm -f "$W/p42"
    elif [ "$a2" -eq 0 ]; then
        echo "  skip axis 3 [$sh_]: the x86_64-linux cycc cannot run on $(uname -s)-$(uname -m)"
    fi
done

# ── axis 4: a tarball that is not release-shaped is refused ──
mkdir -p "$W/fab/versions/$V/bin" "$W/fab/versions/$V/lib" "$W/fabrel"
printf '#!/bin/sh\necho fabricated\n' > "$W/fab/versions/$V/bin/cycc"
cp "$W/fab/versions/$V/bin/cycc" "$W/fab/versions/$V/bin/cyrius"
chmod +x "$W/fab/versions/$V/bin/cycc" "$W/fab/versions/$V/bin/cyrius"
printf 'fn x(): i64 { return 0; }\n' > "$W/fab/versions/$V/lib/x.cyr"
{ ( cd "$W/fab" && tar czf "$W/fabrel/$TB" versions ) && ( cd "$W/fabrel" && sha256sum "$TB" > "$TB.sha256" ); } \
    || { echo "FAIL: $NAME — cannot build the axis-4 tarball"; exit 1; }
RELDIR="$W/fabrel"
run_ci "$W/h-fab" sh
H="$W/h-fab/.cyrius"
if [ "$RC" -ne 0 ] && grep -q "not a Cyrius release tarball" "$W/out" && [ ! -e "$H/bin/cycc" ] && [ ! -e "$H/current" ]; then
    echo "  ok axis 4: a tarball in the fabricated versions/<v>/ layout is refused by name (exit $RC), nothing linked or activated"
else
    bad "axis 4: the fabricated versions/<v>/ tarball: exit $RC, cycc $( [ -e "$H/bin/cycc" ] && echo LINKED || echo absent), current $( [ -e "$H/current" ] && echo WRITTEN || echo absent)"
fi
# a release-shaped directory with bin/ and NO lib/ is not a toolchain either (install.sh refuses it too)
rm -rf "$W/fab" "$W/fabrel"
mkdir -p "$W/fab/$STAGE/bin" "$W/fabrel"
cp "$EXP/bin/cycc" "$EXP/bin/cyrius" "$W/fab/$STAGE/bin/"
{ ( cd "$W/fab" && tar czf "$W/fabrel/$TB" "$STAGE" ) && ( cd "$W/fabrel" && sha256sum "$TB" > "$TB.sha256" ); } \
    || { echo "FAIL: $NAME — cannot build the axis-4 no-lib tarball"; exit 1; }
run_ci "$W/h-nolib" sh
H="$W/h-nolib/.cyrius"
if [ "$RC" -ne 0 ] && grep -q "has no $STAGE/lib/" "$W/out" && [ ! -e "$H/bin/cycc" ] && [ ! -e "$H/current" ]; then
    echo "  ok axis 4: a release-shaped tarball with no lib/ is refused by name (exit $RC), nothing linked or activated"
else
    bad "axis 4: the no-lib tarball: exit $RC, cycc $( [ -e "$H/bin/cycc" ] && echo LINKED || echo absent), current $( [ -e "$H/current" ] && echo WRITTEN || echo absent)"
fi

# ── axis 5: over a home install.sh made, ci.sh re-points the links and leaves the old slot alone ──
# install.sh's `_switch_active` makes $CYRIUS_HOME/bin and lib DIRECTORY links into the active
# slot. The per-file `ln -sf versions/<v>/bin/X $CYRIUS_HOME/bin/X` wrote THROUGH that link, turning
# every binary of the old slot into a link into the new one (lib stayed on the old stdlib).
RELDIR="$CO/dist"
OLD=0.0.1
for sh_ in "sh" "bash -eo pipefail"; do
    HH="$W/h5-${sh_%% *}"; H="$HH/.cyrius"; OD="$H/versions/$OLD"
    fresh_home "$HH"
    mkdir -p "$OD/bin" "$OD/lib"
    for b in cycc cyrius; do printf '#!/bin/sh\necho "old %s %s"\n' "$b" "$OLD" > "$OD/bin/$b"; done
    chmod 755 "$OD/bin/cycc" "$OD/bin/cyrius"
    printf '# only in the old slot\n' > "$OD/lib/old_only.cyr"
    echo "$OLD" > "$OD/VERSION"; echo "$OLD" > "$H/current"
    ln -s "$OD/bin" "$H/bin"; ln -s "$OD/lib" "$H/lib"
    rm -rf "$W/old5"; cp -R "$OD" "$W/old5"
    # shellcheck disable=SC2086  # the shell and its flags are words by construction
    run_ci_in "$HH" $sh_
    a5=0
    { [ "$RC" -eq 0 ] && grep -q 'cycc:  ok' "$W/out"; } || { bad "axis 5 [$sh_]: ci.sh over an install.sh-shaped home exit $RC"; a5=1; }
    # the old slot: the same entries, every one a regular file (never a link), byte-identical
    [ "$(cd "$OD" && find . | LC_ALL=C sort | tr '\n' ' ')" = "$(cd "$W/old5" && find . | LC_ALL=C sort | tr '\n' ' ')" ] \
        || { bad "axis 5 [$sh_]: versions/$OLD's entries changed: $(cd "$OD" && find . | LC_ALL=C sort | tr '\n' ' ')"; a5=1; }
    for f in bin/cycc bin/cyrius lib/old_only.cyr VERSION; do
        { [ -f "$OD/$f" ] && [ ! -L "$OD/$f" ] && cmp -s "$W/old5/$f" "$OD/$f"; } \
            || { bad "axis 5 [$sh_]: versions/$OLD/$f $( [ -L "$OD/$f" ] && echo "is now a LINK to $(readlink "$OD/$f")" || echo 'changed or gone')"; a5=1; }
    done
    # the active names: every bin and the stdlib resolve into the new slot
    for f in "$EXP/bin"/*; do
        b=$(basename "$f")
        cmp -s "$f" "$H/bin/$b" || { bad "axis 5 [$sh_]: \$CYRIUS_HOME/bin/$b does not resolve to versions/$V/bin/$b"; a5=1; break; }
    done
    diff -r "$EXP/lib" "$H/lib" > /dev/null 2>&1 \
        || { bad "axis 5 [$sh_]: \$CYRIUS_HOME/lib is not versions/$V/lib$( [ -e "$H/lib/old_only.cyr" ] && echo " (still the old slot's stdlib)")"; a5=1; }
    [ "$(cat "$H/current" 2>/dev/null)" = "$V" ] || { bad "axis 5 [$sh_]: current does not name $V"; a5=1; }
    [ "$a5" -eq 0 ] && echo "  ok axis 5 [$sh_]: over a home whose bin / lib link into versions/$OLD, ci.sh re-points both to versions/$V and leaves versions/$OLD byte-identical"
done

[ "$fail" -eq 0 ] || { echo "FAIL: $NAME"; exit 1; }
echo "PASS: $NAME (ci.sh installs the tarball release.yml's package step builds — bin/, lib/, the init templates and the shell twin into versions/<v>, linked and runnable — refuses one that is not release-shaped, and re-points an install.sh home without touching its old slot)"
